/**
 * Deploy (from repo root):
 *   cd functions && npm install
 *   firebase functions:secrets:set DIDIT_API_KEY
 *   firebase deploy --only functions
 *
 * New-message email (notifyOnNewChatMessage): SMTP via nodemailer.
 *   firebase functions:secrets:set SMTP_HOST
 *   firebase functions:secrets:set SMTP_USER
 *   firebase functions:secrets:set SMTP_PASS
 * Optional params: MAIL_FROM, APP_PUBLIC_URL, SMTP_PORT (587), SMTP_SECURE (false)
 */
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { defineSecret, defineString } = require('firebase-functions/params');

if (!admin.apps.length) {
  admin.initializeApp();
}

const diditApiKey = defineSecret('DIDIT_API_KEY');

const smtpHost = defineSecret('SMTP_HOST');
const smtpUser = defineSecret('SMTP_USER');
const smtpPass = defineSecret('SMTP_PASS');
const smtpPort = defineString('SMTP_PORT', { default: '587' });
const smtpSecure = defineString('SMTP_SECURE', { default: 'false' });
const mailFrom = defineString('MAIL_FROM', { default: '' });
const appPublicUrl = defineString('APP_PUBLIC_URL', {
  default: 'https://gathr-5b405.web.app',
});

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

const _maxPreviewLen = 600;

/**
 * Sends email to the other participant when a direct message is created.
 * Requires SMTP_HOST, SMTP_USER, SMTP_PASS (secrets). For SendGrid, SMTP_USER is "apikey" —
 * you must set MAIL_FROM to a verified sender (e.g. Public Commons App <you@domain.com>).
 *
 * Opt out per user: set `users/{uid}.emailNewMessage` to false in Firestore.
 */
exports.notifyOnNewChatMessage = onDocumentCreated(
  {
    document: 'conversations/{conversationId}/messages/{messageId}',
    region: 'us-central1',
    secrets: [smtpHost, smtpUser, smtpPass],
  },
  async (event) => {
    const snap = event.data;
    if (!snap?.exists) {
      return;
    }

    const message = snap.data();
    const senderId =
      typeof message.senderId === 'string' ? message.senderId.trim() : '';
    const messageText =
      typeof message.text === 'string' ? message.text.trim() : '';
    if (!senderId || !messageText) {
      return;
    }

    const conversationId = event.params.conversationId;
    const convRef = admin.firestore().doc(`conversations/${conversationId}`);
    const convSnap = await convRef.get();
    if (!convSnap.exists) {
      return;
    }

    const conv = convSnap.data() || {};
    const participantIds = conv.participantIds;
    if (!Array.isArray(participantIds) || participantIds.length !== 2) {
      return;
    }

    const recipientIds = participantIds.filter((id) => id && id !== senderId);
    if (recipientIds.length !== 1) {
      return;
    }
    const recipientUid = String(recipientIds[0]);

    const userDoc = await admin.firestore().doc(`users/${recipientUid}`).get();
    if (userDoc.exists && userDoc.data()?.emailNewMessage === false) {
      return;
    }

    let recipientEmail;
    try {
      const rec = await admin.auth().getUser(recipientUid);
      recipientEmail = rec.email;
    } catch (e) {
      console.warn('notifyOnNewChatMessage: getUser failed', recipientUid, e?.message || e);
      return;
    }
    if (!recipientEmail) {
      console.info('notifyOnNewChatMessage: no email for', recipientUid);
      return;
    }

    const names =
      conv.participantNames && typeof conv.participantNames === 'object'
        ? conv.participantNames
        : {};
    const senderNameRaw = names[senderId];
    const senderName =
      typeof senderNameRaw === 'string' && senderNameRaw.trim()
        ? senderNameRaw.trim()
        : 'Someone';

    const preview =
      messageText.length > _maxPreviewLen
        ? `${messageText.slice(0, _maxPreviewLen)}…`
        : messageText;
    const baseUrl = appPublicUrl.value().replace(/\/$/, '');
    const openUrl = `${baseUrl}/chat/${encodeURIComponent(conversationId)}`;

    const smtpUserVal = smtpUser.value();
    let from = mailFrom.value().trim();
    if (!from) {
      if (smtpUserVal.toLowerCase() === 'apikey') {
        console.error(
          'notifyOnNewChatMessage: MAIL_FROM must be set to a SendGrid-verified sender ' +
            '(SMTP_USER is "apikey" — it cannot be used as the From address). ' +
            'Use e.g. "Public Commons App <verified@yourdomain.com>".',
        );
        return;
      }
      from = smtpUserVal;
    }

    const subject = `New message from ${senderName} — Public Commons App`;
    const text =
      `${senderName} sent you a message on Public Commons App:\n\n` +
      `${preview}\n\n` +
      `Open the conversation: ${openUrl}\n`;
    const html =
      `<p><strong>${escapeHtml(senderName)}</strong> sent you a message on Public Commons App:</p>` +
      `<blockquote style="margin:12px 0;padding:8px 12px;border-left:3px solid #ccc;">` +
      `${escapeHtml(preview).replace(/\n/g, '<br/>')}</blockquote>` +
      `<p><a href="${escapeHtml(openUrl)}">Open the conversation</a></p>`;

    const port = Number.parseInt(smtpPort.value(), 10) || 587;
    const secure = smtpSecure.value() === 'true';
    const transporter = nodemailer.createTransport({
      host: smtpHost.value(),
      port,
      secure,
      auth: {
        user: smtpUser.value(),
        pass: smtpPass.value(),
      },
    });

    try {
      console.info(
        'notifyOnNewChatMessage: sending',
        JSON.stringify({ to: recipientEmail, from, conversationId }),
      );
      await transporter.sendMail({
        from,
        to: recipientEmail,
        subject,
        text,
        html,
      });
      console.info('notifyOnNewChatMessage: sent OK', recipientEmail);
    } catch (err) {
      console.error('notifyOnNewChatMessage: SMTP send failed', err?.message ?? err);
      throw err;
    }
  },
);

/** Minimal escaping for HTML email body fragments. */
function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}
