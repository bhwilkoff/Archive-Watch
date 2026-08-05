/* Archive Watch — Google Cast sender (web).
 *
 * Adds a Cast button to the player that hands the current film to a Chromecast,
 * a Google TV, or any Chromecast-built-in TV — which is the ONLY realistic way
 * to reach Vizio sets, since Vizio has no self-serve developer program
 * (docs/TV-PLATFORM-EXPANSION.md, Decision 047).
 *
 * Additive and self-disabling, exactly like tv.js: if the Cast framework never
 * loads (any non-Chromium browser, or an extension blocking gstatic) every
 * function here no-ops and the button stays hidden. Nothing else in the viewer
 * knows this file exists.
 *
 * ⚠️ APP ID: `CAST_APP_ID` below is Google's **Default Media Receiver**, which
 * works without any registration and is what makes this testable today. Once
 * the owner completes the $5 Cast registration (backlog O1) and the custom
 * receiver at /cast/ has an ID, put it here — the custom receiver is what
 * carries subtitles and the provenance credit.
 */
(function () {
  'use strict';

  // Default Media Receiver — replace with the registered custom-receiver ID.
  var CAST_APP_ID = 'CC1AD845';
  var USING_DEFAULT_RECEIVER = true;

  var castContext = null;
  var button = null;

  function $(id) { return document.getElementById(id); }

  /** The Cast framework calls this global when it finishes loading. */
  window.__onGCastApiAvailable = function (isAvailable) {
    if (!isAvailable) return;
    try { init(); } catch (e) { /* never break the player */ }
  };

  function init() {
    castContext = cast.framework.CastContext.getInstance();
    castContext.setOptions({
      receiverApplicationId: CAST_APP_ID,
      // Stop casting when the tab goes away — leaving a TV stranded on a
      // half-played film is worse than ending the session.
      autoJoinPolicy: chrome.cast.AutoJoinPolicy.ORIGIN_SCOPED,
    });

    button = $('player-cast');
    if (!button) return;
    button.hidden = false;
    button.addEventListener('click', onCastClick);

    castContext.addEventListener(
      cast.framework.CastContextEventType.CAST_STATE_CHANGED,
      function (ev) {
        if (!button) return;
        var connected = ev.castState === cast.framework.CastState.CONNECTED;
        button.setAttribute('aria-pressed', String(connected));
        button.classList.toggle('is-casting', connected);
      },
    );
  }

  function onCastClick() {
    if (!castContext) return;
    var session = castContext.getCurrentSession();
    if (session) {
      // Already casting → the button ends the session (and playback resumes
      // locally only if the viewer presses play; we do not auto-resume, which
      // would start a film unexpectedly).
      castContext.endCurrentSession(true);
      return;
    }
    castContext.requestSession().then(castCurrentVideo).catch(function () {
      /* user dismissed the device picker — nothing to do */
    });
  }

  /** Hand whatever the local player is showing to the connected receiver. */
  function castCurrentVideo() {
    var session = castContext && castContext.getCurrentSession();
    var video = $('video');
    if (!session || !video || !video.src) return;

    var info = new chrome.cast.media.MediaInfo(video.src, 'video/mp4');
    info.streamType = chrome.cast.media.StreamType.BUFFERED;

    var meta = new chrome.cast.media.MovieMediaMetadata();
    meta.title = ($('player-overlay-title') || {}).textContent || '';
    meta.subtitle = ($('player-overlay-desc') || {}).textContent || '';
    info.metadata = meta;

    // Carry the side-loaded WebVTT subtitle tracks across (Decision 039). The
    // Default Media Receiver drops these; the custom receiver at /cast/ keeps
    // them, which is one of the reasons it exists.
    var tracks = [];
    var trackEls = video.querySelectorAll('track');
    for (var i = 0; i < trackEls.length; i++) {
      var el = trackEls[i];
      var t = new chrome.cast.media.Track(i + 1, chrome.cast.media.TrackType.TEXT);
      t.trackContentId = el.src;
      t.trackContentType = 'text/vtt';
      t.subtype = chrome.cast.media.TextTrackType.SUBTITLES;
      t.name = el.label || el.srclang;
      t.language = el.srclang || 'en';
      tracks.push(t);
    }
    if (tracks.length) info.tracks = tracks;

    var request = new chrome.cast.media.LoadRequest(info);
    // Resume the cast where the local player is — casting mid-film should not
    // restart it.
    request.currentTime = Math.max(0, Math.floor(video.currentTime || 0));
    request.autoplay = true;

    session.loadMedia(request).then(function () {
      // The TV owns playback now; stop the local copy so audio isn't doubled.
      try { video.pause(); } catch (e) { /* ignore */ }
    }).catch(function (err) {
      // eslint-disable-next-line no-console
      console.error('[AW cast] loadMedia failed', err);
    });
  }

  /** Exposed for diagnostics + the browser test suite. */
  window.AWCast = {
    get available() { return castContext != null; },
    get usingDefaultReceiver() { return USING_DEFAULT_RECEIVER; },
    get appId() { return CAST_APP_ID; },
    castCurrentVideo: castCurrentVideo,
  };
})();
