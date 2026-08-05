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
 * APP ID: our registered **Custom Receiver**, hosted at /cast/. It is what
 * carries the side-loaded WebVTT subtitles, the public-domain provenance
 * credit, and real error text instead of a black screen.
 *
 * ⚠️ A registered receiver is UNPUBLISHED until the owner publishes it in the
 * Cast console, and an unpublished receiver launches ONLY on devices added
 * under Console → Devices (by serial number). So before publication, casting
 * works on registered test devices and silently fails everywhere else — that
 * is Google's behaviour, not a bug here. Publish before any public release
 * (backlog C1/O1).
 */
(function () {
  'use strict';

  // Archive Watch custom receiver (registered 2026-08-05, hosted at /cast/).
  // Google's Default Media Receiver 'CC1AD845' remains a working fallback if
  // the custom receiver ever needs to be bypassed — it needs no registration
  // but drops subtitles and provenance.
  var CAST_APP_ID = '58AF34C3';
  var USING_DEFAULT_RECEIVER = (CAST_APP_ID === 'CC1AD845');

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
      // NEVER el.src — that is a blob: URL scoped to this document (see
      // addSubtitleTrack in watch.js). The receiver needs the real https URL.
      t.trackContentId = el.dataset.awSrc || el.src;
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
