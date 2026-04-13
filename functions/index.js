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
 *
 * Callable sendPublicCommonsInvite: signed-in users send join invites by email (same SMTP).
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
  default: 'https://publiccommons.app',
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

function buildSmtpTransporter() {
  const port = Number.parseInt(smtpPort.value(), 10) || 587;
  const secure = smtpSecure.value() === 'true';
  return nodemailer.createTransport({
    host: smtpHost.value(),
    port,
    secure,
    auth: {
      user: smtpUser.value(),
      pass: smtpPass.value(),
    },
  });
}

/**
 * @returns {string|null} From header, or null if SendGrid "apikey" user without MAIL_FROM.
 */
function resolveMailFromHeader() {
  const smtpUserVal = smtpUser.value();
  let from = mailFrom.value().trim();
  if (!from) {
    if (smtpUserVal.toLowerCase() === 'apikey') {
      return null;
    }
    from = smtpUserVal;
  }
  return from;
}

/** Display name in recipients’ inboxes; address still comes from verified MAIL_FROM. */
const outboundMailDisplayName = 'Public Commons App';


function resolveBrandedMailFrom() {
  const raw = resolveMailFromHeader();
  if (!raw) return null;
  const m = raw.match(/<([^>]+)>/);
  const addr = (m ? m[1] : raw).trim();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(addr)) {
    return raw;
  }
  return `${outboundMailDisplayName} <${addr}>`;
}

function isLikelyValidEmail(s) {
  const t = String(s || '').trim();
  if (t.length < 3 || t.length > 320) return false;
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(t);
}

/**
 * Signed-in user sends a join invite to an email address.
 */
exports.sendPublicCommonsInvite = onCall(
  {
    secrets: [smtpHost, smtpUser, smtpPass],
    region: 'us-central1',
    cors: true,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in required.');
    }

    const raw = request.data?.email;
    if (typeof raw !== 'string' || !isLikelyValidEmail(raw)) {
      throw new HttpsError('invalid-argument', 'Enter a valid email address.');
    }
    const to = raw.trim().toLowerCase();

    const from = resolveBrandedMailFrom();
    if (!from) {
      throw new HttpsError(
        'failed-precondition',
        'Server email is not configured (set MAIL_FROM for your SMTP provider).',
      );
    }

    const inviterUser = await admin.auth().getUser(request.auth.uid);
    const inviterLabel =
      (inviterUser.displayName && inviterUser.displayName.trim()) ||
      inviterUser.email ||
      'Someone';

    const baseUrl = appPublicUrl.value().replace(/\/$/, '');
    const joinUrl = `${baseUrl}/sign-in`;

    const subject = "You're invited to Public Commons";
    const text =
      `${inviterLabel} invited you to join Public Commons — a local place for help, events, and neighbors.\n\n` +
      `Create an account or sign in here:\n${joinUrl}\n`;
    const html =
      `<p><strong>${escapeHtml(inviterLabel)}</strong> invited you to join ` +
      `<strong>Public Commons</strong> — a local place for help, events, and neighbors.</p>` +
      `<p><a href="${escapeHtml(joinUrl)}">Join Public Commons</a></p>` +
      `<p style="color:#666;font-size:14px;">If the link doesn’t work, copy and paste:<br/>${escapeHtml(
        joinUrl,
      )}</p>`;

    const transporter = buildSmtpTransporter();
    try {
      await transporter.sendMail({
        from,
        to,
        subject,
        text,
        html,
      });
    } catch (err) {
      console.error('sendPublicCommonsInvite: SMTP failed', err?.message ?? err);
      throw new HttpsError('unavailable', 'Could not send email right now. Try again later.');
    }

    return { ok: true };
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

    const from = resolveBrandedMailFrom();
    if (!from) {
      console.error(
        'notifyOnNewChatMessage: MAIL_FROM must be set to a SendGrid-verified sender ' +
        '(SMTP_USER is "apikey" — it cannot be used as the From address). ' +
        'Use e.g. "Public Commons App <verified@yourdomain.com>".',
      );
      return;
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

    const transporter = buildSmtpTransporter();

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
