/**
 * App — Main Application Logic
 *
 * Architecture: single IIFE wrapping the entire app.
 * Views are <section> elements toggled by showView().
 * Feature modules are nested IIFEs for encapsulation.
 *
 * Conventions:
 *  - $('id') is shorthand for document.getElementById
 *  - All API calls go through API (js/api.js)
 *  - State is plain JS objects/variables (no framework)
 *  - DOM updates use textContent (safe) or innerHTML (only with escHtml)
 *
 * See CLAUDE.md for full conventions and DECISIONS.md for architecture choices.
 */

// Dark mode — flash-free init (runs before DOM renders)
(function() {
  const saved = localStorage.getItem('app_theme');
  if (saved === 'dark') document.documentElement.setAttribute('data-theme', 'dark');
})();

(function () {
  'use strict';

  /* ---- Helpers ---- */
  const $ = (id) => document.getElementById(id);

  function escHtml(str) {
    const d = document.createElement('div');
    d.textContent = str;
    return d.innerHTML;
  }

  function showLoading() { /* TODO: show global loading indicator */ }
  function hideLoading() { /* TODO: hide global loading indicator */ }

  /* ---- DOM Refs ---- */
  const authScreen = $('auth-screen');
  const appScreen  = $('app-screen');
  // Add more DOM refs as views are created:
  // const viewHome = $('view-home');
  // const navHomeBtn = $('nav-home-btn');

  /* ---- State ---- */
  let currentView = 'home';

  /* ================================================================
     VIEW SYSTEM
  ================================================================ */

  /**
   * Switch the active view. Hides all views, shows the target.
   * Updates sidebar nav active state and browser history.
   */
  function showView(name, fromHistory = false) {
    currentView = name;

    // Define your views and nav buttons here:
    const views = {
      // home: viewHome,
    };
    const navBtns = {
      // home: navHomeBtn,
    };

    Object.entries(views).forEach(([n, el]) => {
      if (el) { el.hidden = n !== name; }
    });

    Object.entries(navBtns).forEach(([n, btn]) => {
      if (btn) {
        btn.classList.toggle('active', n === name);
        btn.setAttribute('aria-current', n === name ? 'page' : 'false');
      }
    });

    // Close mobile sidebar on navigation
    $('channels-sidebar')?.classList.remove('open');

    if (!fromHistory) {
      const url = name === 'home' ? '?' : `?view=${name}`;
      history.pushState({ view: name }, '', url);
    }

    // Stop/cleanup for views that need it when leaving:
    // if (name !== 'tv') window.tvStop?.();
  }

  /* ================================================================
     AUTH
  ================================================================ */

  // FILL IN: Your auth flow
  // Example pattern:
  // $('auth-form').addEventListener('submit', async (e) => {
  //   e.preventDefault();
  //   try {
  //     const session = await API.login(handle, password);
  //     localStorage.setItem('session', JSON.stringify(session));
  //     authScreen.hidden = true;
  //     appScreen.hidden = false;
  //     init();
  //   } catch (err) {
  //     $('auth-error').textContent = err.message;
  //     $('auth-error').hidden = false;
  //   }
  // });

  /* ================================================================
     INITIALIZATION
  ================================================================ */

  async function init() {
    // Check for saved session
    // If authenticated: hide auth, show app, load first view
    // If not: show auth screen

    // URL routing (deep links / bookmarks)
    const params = new URLSearchParams(window.location.search);
    const urlView = params.get('view');
    if (urlView) {
      showView(urlView, true);
    } else {
      showView('home', true);
    }
  }

  // Browser back/forward
  window.addEventListener('popstate', (e) => {
    const view = e.state?.view || 'home';
    showView(view, true);
  });

  /* ================================================================
     BOOT
  ================================================================ */
  init();
})();
