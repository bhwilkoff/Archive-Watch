/**
 * Archive Watch — Browser Archive.org client
 *
 * The dashboard runs entirely client-side; it talks directly to the
 * public Archive.org APIs from the curator's browser. CORS is granted
 * on these endpoints (the metadata + scrape APIs both send permissive
 * headers for *.archive.org assets).
 *
 * No auth, no server, no persistence beyond localStorage.
 */
const API = (() => {
  'use strict';

  const META_URL    = 'https://archive.org/metadata/';
  const SCRAPE_URL  = 'https://archive.org/services/search/v1/scrape';
  const THUMB_URL   = 'https://archive.org/services/img/';
  const DETAILS_URL = 'https://archive.org/details/';

  /* ----------------------------------------------------------------
     Identifier helpers
  ---------------------------------------------------------------- */

  /** Normalize input into a bare Archive identifier. */
  function normalizeIdentifier(input) {
    if (!input) return null;
    const s = String(input).trim();
    if (!s) return null;
    // Full URL → grab the segment after /details/
    const detailsMatch = s.match(/archive\.org\/details\/([^/?#]+)/i);
    if (detailsMatch) return detailsMatch[1];
    // Already a bare identifier
    return s;
  }

  function detailsURL(id) { return DETAILS_URL + encodeURIComponent(id); }
  function thumbnailURL(id) { return THUMB_URL + encodeURIComponent(id); }

  /* ----------------------------------------------------------------
     Metadata API
  ---------------------------------------------------------------- */

  async function fetchMetadata(identifier) {
    const id = normalizeIdentifier(identifier);
    if (!id) throw new Error('No identifier provided');
    const resp = await fetch(META_URL + encodeURIComponent(id), {
      headers: { 'Accept': 'application/json' }
    });
    if (!resp.ok) throw new Error(`Archive ${resp.status} for "${id}"`);
    const data = await resp.json();
    if (!data || !data.metadata) {
      throw new Error(`No item found for "${id}"`);
    }
    return data;
  }

  /**
   * Compact summary used by the dashboard for previews.
   * Mirrors the shape that EnrichmentService.swift would derive — keeps
   * the curator's mental model aligned with what ships in the tvOS app.
   */
  function summarize(metadataResponse) {
    const m = metadataResponse.metadata || {};
    const files = metadataResponse.files || [];

    const collections = oneOrMany(m.collection);
    const subjects    = oneOrMany(m.subject);
    const description = firstString(m.description);
    const externalIDs = oneOrMany(m['external-identifier']);

    // Year — try `year`, then first 4 digits of `date`.
    let year = null;
    if (m.year) {
      const n = parseInt(String(m.year).slice(0, 4), 10);
      if (!isNaN(n)) year = n;
    } else if (m.date) {
      const n = parseInt(String(m.date).slice(0, 4), 10);
      if (!isNaN(n)) year = n;
    }

    // IMDb tt-ID, anywhere in external-identifier.
    let imdbID = null;
    for (const urn of externalIDs) {
      const match = String(urn).toLowerCase().match(/tt\d{6,10}/);
      if (match) { imdbID = match[0]; break; }
    }

    // Best playable derivative (matches Swift DerivativePicker tiers).
    const videoFile = pickVideo(files);

    return {
      identifier: m.identifier,
      title: m.title || m.identifier,
      year,
      runtime: m.runtime || null,
      mediatype: m.mediatype || null,
      collections,
      subjects,
      description,
      imdbID,
      hasIMDb: !!imdbID,
      videoFile,
      hasPlayable: !!videoFile,
      thumbnail: thumbnailURL(m.identifier || ''),
      detailsURL: detailsURL(m.identifier || '')
    };
  }

  /** Mirror of Swift DerivativePicker — keep the two in sync. */
  function pickVideo(files) {
    const videos = files.filter(isVideo);
    if (videos.length === 0) return null;

    const tiers = [
      { tier: 1, reason: 'h.264 MP4 derivative',   pred: f => isDerivative(f) && /h\.?264/i.test(f.format || '') },
      { tier: 2, reason: 'MP4 derivative',         pred: f => isDerivative(f) && /mp4/i.test(f.format || '') },
      { tier: 3, reason: '512Kb MPEG4 derivative', pred: f => isDerivative(f) && /512kb/i.test(f.format || '') && /mpeg4/i.test(f.format || '') },
      { tier: 4, reason: 'MPEG4 derivative',       pred: f => isDerivative(f) && /mpeg-?4/i.test(f.format || '') },
      { tier: 5, reason: 'WebM/Matroska/Ogg',      pred: f => isDerivative(f) && /(webm|matroska|ogg)/i.test(f.format || '') },
      { tier: 6, reason: 'MP4/H.264 original',     pred: f => isOriginal(f)   && /(mp4|h\.?264)/i.test(f.format || '') },
      { tier: 7, reason: 'Any video original',     pred: f => isOriginal(f) }
    ];

    for (const { tier, reason, pred } of tiers) {
      const match = videos.filter(pred).sort(bySizeDesc)[0];
      if (match) {
        return { name: match.name, format: match.format, size: match.size, sizeBytes: parseInt(match.size, 10) || 0, tier, reason };
      }
    }
    return null;
  }

  function isVideo(f) {
    const fmt = (f.format || '').toLowerCase();
    return /(mp4|h\.?264|mpeg-?4|ogg video|matroska|quicktime|avi|webm)/.test(fmt);
  }
  function isDerivative(f) { return (f.source || '').toLowerCase() === 'derivative'; }
  function isOriginal(f)   { return (f.source || '').toLowerCase() === 'original'; }
  function bySizeDesc(a, b) { return (parseInt(b.size, 10) || 0) - (parseInt(a.size, 10) || 0); }

  function oneOrMany(value) {
    if (value == null) return [];
    return Array.isArray(value) ? value : [value];
  }
  function firstString(value) {
    const arr = oneOrMany(value);
    return arr.length ? String(arr[0]) : null;
  }

  /* ----------------------------------------------------------------
     Scrape API (paginated browse)
  ---------------------------------------------------------------- */

  async function scrape({ q, sorts = [], count = 24, cursor = null, fields = null }) {
    const defaultFields = ['identifier', 'title', 'creator', 'year', 'date', 'mediatype', 'collection', 'downloads'];
    const params = new URLSearchParams();
    params.set('q', q);
    params.set('fields', (fields || defaultFields).join(','));
    params.set('count', String(Math.max(count, 100))); // API minimum is 100
    if (sorts.length) params.set('sorts', sorts.join(','));
    if (cursor) params.set('cursor', cursor);

    const resp = await fetch(SCRAPE_URL + '?' + params.toString(), {
      headers: { 'Accept': 'application/json' }
    });
    if (!resp.ok) throw new Error(`Archive scrape ${resp.status}`);
    const data = await resp.json();
    return {
      items: (data.items || []).slice(0, count),
      cursor: data.cursor || null
    };
  }

  return {
    normalizeIdentifier,
    detailsURL,
    thumbnailURL,
    fetchMetadata,
    summarize,
    scrape
  };
})();
