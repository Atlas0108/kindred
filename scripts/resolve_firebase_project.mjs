import { readFileSync, existsSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

/** Same path FlutterFire writes in this repo (`firebase.json`). */
function readProjectIdFromRepoFirebaseJson(fromDir) {
  const root = join(fromDir, '..', '..', 'firebase.json');
  if (!existsSync(root)) return undefined;
  try {
    const j = JSON.parse(readFileSync(root, 'utf8'));
    const pid = j?.flutter?.platforms?.dart?.['lib/firebase_options.dart']?.projectId;
    if (typeof pid === 'string' && pid.trim()) return pid.trim();
  } catch {
    /* ignore */
  }
  return undefined;
}

/**
 * Resolves Firebase/Google project id for Admin SDK init.
 * Order: env vars → service account JSON `project_id` → repo `firebase.json`.
 */
export function resolveFirebaseProjectId(scriptImportMetaUrl) {
  const fromEnv =
    process.env.GOOGLE_CLOUD_PROJECT?.trim() ||
    process.env.GCLOUD_PROJECT?.trim() ||
    process.env.FIREBASE_PROJECT_ID?.trim();
  if (fromEnv) return fromEnv;

  const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (credPath) {
    try {
      const j = JSON.parse(readFileSync(credPath, 'utf8'));
      if (typeof j.project_id === 'string' && j.project_id.trim()) {
        return j.project_id.trim();
      }
    } catch {
      /* missing file, invalid JSON, or unreadable path */
    }
  }

  const scriptDir = dirname(fileURLToPath(scriptImportMetaUrl));
  return readProjectIdFromRepoFirebaseJson(scriptDir);
}

/**
 * Ensures GOOGLE_APPLICATION_CREDENTIALS points at a real JSON key file before Admin SDK init.
 * Exits the process with a short how-to if not.
 */
export function assertValidGoogleApplicationCredentialsPath() {
  const raw = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!raw || !String(raw).trim()) {
    console.error(
      'Set GOOGLE_APPLICATION_CREDENTIALS to the full path of your Firebase service account JSON.',
    );
    process.exit(1);
  }
  const p = raw.trim();
  if (!existsSync(p)) {
    console.error(
      `Service account file not found:\n  ${p}\n\n` +
        'Do not use a placeholder path from the docs. Download a real key:\n' +
        '  Firebase Console → Project settings → Service accounts → Generate new private key\n' +
        'Then export the variable, for example:\n' +
        '  export GOOGLE_APPLICATION_CREDENTIALS="$HOME/Downloads/your-project-firebase-adminsdk-xxxxx.json"\n',
    );
    process.exit(1);
  }
  try {
    if (!statSync(p).isFile()) {
      console.error(`GOOGLE_APPLICATION_CREDENTIALS must be a file, not a directory:\n  ${p}`);
      process.exit(1);
    }
  } catch (err) {
    console.error(`Cannot access GOOGLE_APPLICATION_CREDENTIALS:\n  ${p}\n${err?.message ?? err}`);
    process.exit(1);
  }
}
