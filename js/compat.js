/* Archive Watch — platform gaps on older TV browsers.
 *
 * Samsung's 2022 TVs (Tizen 6.5) run Chromium 85, and the app supports them
 * (owner, 2026-10-03: "everything from 2022 onward"). This file loads before
 * every other script and fills only what Chromium 85 lacks; on a current
 * browser every branch is skipped. Checked by rendering the TV layer in a real
 * Chromium 85 build (docs/tizen-submission.md, "Older Samsung TVs").
 */
(function () {
  'use strict';

  // AbortSignal.timeout — Chromium 103.
  if (typeof AbortSignal !== 'undefined' && !AbortSignal.timeout) {
    AbortSignal.timeout = function (ms) {
      var c = new AbortController();
      setTimeout(function () { c.abort(); }, ms);
      return c.signal;
    };
  }

  // replaceChildren — Chromium 86.
  [Element, Document, DocumentFragment].forEach(function (C) {
    if (C && C.prototype && !C.prototype.replaceChildren) {
      C.prototype.replaceChildren = function () {
        while (this.lastChild) this.removeChild(this.lastChild);
        this.append.apply(this, arguments);
      };
    }
  });
})();
