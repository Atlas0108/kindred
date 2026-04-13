/**
 * Deploy (from repo root):
 *   cd functions && npm install
 *   firebase functions:secrets:set DIDIT_API_KEY
 *   firebase deploy --only functions
 */
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');

const diditApiKey = defineSecret('DIDIT_API_KEY');

/**
 * Proxies Didit POST /v3/session/ so the browser never calls Didit directly (CORS).
 */
exports.createDiditSession = onCall(
  {
    secrets: [diditApiKey],
    region: 'us-central1',
    cors: true,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in required.');
    }

    const { workflowId, vendorData, callbackUrl, portraitImage } = request.data || {};
    if (typeof workflowId !== 'string' || workflowId.trim() === '') {
      throw new HttpsError('invalid-argument', 'workflowId is required.');
    }
    if (typeof vendorData !== 'string' || vendorData.trim() === '') {
      throw new HttpsError('invalid-argument', 'vendorData is required.');
    }

    const body = {
      workflow_id: workflowId.trim(),
      vendor_data: vendorData.trim(),
    };
    if (typeof callbackUrl === 'string' && callbackUrl.trim() !== '') {
      body.callback = callbackUrl.trim();
    }
    if (typeof portraitImage === 'string' && portraitImage.trim() !== '') {
      let b64 = portraitImage.trim();
      const dataUrl = /^data:image\/\w+;base64,/i.exec(b64);
      if (dataUrl) {
        b64 = b64.slice(dataUrl[0].length);
      }
      body.portrait_image = b64;
    }

    let resp;
    try {
      resp = await fetch('https://verification.didit.me/v3/session/', {
        method: 'POST',
        headers: {
          'x-api-key': diditApiKey.value(),
          'Content-Type': 'application/json',
          Accept: 'application/json',
        },
        body: JSON.stringify(body),
      });
    } catch (e) {
      console.error('Didit fetch failed', e);
      throw new HttpsError('unavailable', 'Could not reach Didit verification API.');
    }

    const text = await resp.text();
    let json = null;
    try {
      json = JSON.parse(text);
    } catch (_) {
      /* handled below */
    }

    if (!resp.ok) {
      let detail =
        json && typeof json.detail === 'string' ? json.detail : null;
      if (!detail && json && typeof json === 'object' && !Array.isArray(json)) {
        const parts = [];
        for (const [k, v] of Object.entries(json)) {
          if (typeof v === 'string') parts.push(`${k}: ${v}`);
        }
        if (parts.length) detail = parts.join(' ');
      }
      if (!detail) detail = text.slice(0, 800) || `HTTP ${resp.status}`;
      console.error('Didit error', resp.status, detail);
      throw new HttpsError('failed-precondition', detail);
    }

    if (!json || typeof json !== 'object') {
      throw new HttpsError('internal', 'Invalid JSON from Didit.');
    }

    const url = json.url || json.verification_url;
    if (typeof url !== 'string' || url.length === 0) {
      throw new HttpsError('internal', 'Didit response missing url.');
    }

    return {
      url,
      sessionId: json.session_id ?? null,
      sessionToken: json.session_token ?? null,
    };
  },
);
