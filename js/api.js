/**
 * API Abstraction Layer
 *
 * ALL external API calls go through this module. Views and app.js never
 * call fetch() directly. This ensures:
 *  - Single place for auth header injection
 *  - Consistent error handling
 *  - Easy to swap base URLs or add retry logic
 *
 * Usage: const data = await API.get('/endpoint', { param: 'value' });
 */
const API = (() => {
  'use strict';

  // FILL IN: Your API base URL
  const BASE_URL = '';

  function getAuthHeaders() {
    // FILL IN: Return auth headers (e.g., { Authorization: 'Bearer ...' })
    return {};
  }

  async function get(endpoint, params = {}) {
    const url = new URL(BASE_URL + endpoint);
    Object.entries(params).forEach(([k, v]) => {
      if (v !== undefined && v !== null) url.searchParams.set(k, v);
    });
    const resp = await fetch(url, { headers: getAuthHeaders() });
    if (!resp.ok) throw new Error(`API ${resp.status}: ${resp.statusText}`);
    return resp.json();
  }

  async function post(endpoint, body = {}, contentType = 'application/json') {
    const headers = { ...getAuthHeaders() };
    let fetchBody;
    if (contentType === 'application/json') {
      headers['Content-Type'] = 'application/json';
      fetchBody = JSON.stringify(body);
    } else {
      headers['Content-Type'] = contentType;
      fetchBody = body;
    }
    const resp = await fetch(BASE_URL + endpoint, { method: 'POST', headers, body: fetchBody });
    if (!resp.ok) throw new Error(`API ${resp.status}: ${resp.statusText}`);
    return resp.json();
  }

  // FILL IN: Add your specific API methods here
  // Example:
  // async function getTimeline(limit = 50, cursor) {
  //   return get('/app.bsky.feed.getTimeline', { limit, cursor });
  // }

  return {
    get,
    post,
    getAuthHeaders,
    // Export your API methods here
  };
})();
