#!/usr/bin/env node
/**
 * Deletes every document in Firestore `posts` and removes Storage files under
 * `post_images/` except filenames starting with `profile_` (avatar uploads).
 *
 *   export GOOGLE_APPLICATION_CREDENTIALS="$HOME/Downloads/your-project-firebase-adminsdk-xxxxx.json"
 *   cd scripts/delete_all_posts && npm install
 *   node delete_all_posts.mjs              # dry-run: counts only
 *   node delete_all_posts.mjs --execute    # actually delete
 *
 * Optional: FIREBASE_STORAGE_BUCKET (default: ${projectId}.firebasestorage.app)
 */

import admin from 'firebase-admin';

import {
  assertValidGoogleApplicationCredentialsPath,
  resolveFirebaseProjectId,
} from '../resolve_firebase_project.mjs';

const execute = process.argv.includes('--execute');
const wantHelp = process.argv.includes('--help') || process.argv.includes('-h');

if (wantHelp) {
  console.log(`
Usage: node delete_all_posts.mjs [--execute]

  (default)    Show how many post documents and storage objects would be removed.
  --execute    Delete all Firestore docs in "posts" and matching Storage files.

Set GOOGLE_APPLICATION_CREDENTIALS to a service account JSON with permissions
for Cloud Datastore (Firestore) and Storage (e.g. Firebase Admin or Editor).
`);
  process.exit(0);
}

assertValidGoogleApplicationCredentialsPath();

const resolvedProjectId = resolveFirebaseProjectId(import.meta.url);
if (!admin.apps.length) {
  admin.initializeApp(resolvedProjectId ? { projectId: resolvedProjectId } : {});
}

const db = admin.firestore();
const projectId = admin.app().options.projectId || resolvedProjectId;
if (!projectId) {
  console.error(
    'Could not determine Firebase project ID. Set GOOGLE_CLOUD_PROJECT, use a key JSON with "project_id", or run from the repo so ../../firebase.json is found.',
  );
  process.exit(1);
}

const bucketName =
  process.env.FIREBASE_STORAGE_BUCKET || `${projectId}.firebasestorage.app`;
const bucket = admin.storage().bucket(bucketName);

const POSTS = 'posts';
const STORAGE_PREFIX = 'post_images/';

function isProfileAvatarObject(name) {
  const base = name.split('/').pop() ?? '';
  return base.startsWith('profile_');
}

async function listAllPostDocIds() {
  const ids = [];
  let q = db.collection(POSTS).orderBy(admin.firestore.FieldPath.documentId()).limit(500);
  for (;;) {
    const snap = await q.get();
    if (snap.empty) break;
    for (const d of snap.docs) ids.push(d.id);
    const last = snap.docs[snap.docs.length - 1];
    q = db
      .collection(POSTS)
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(500)
      .startAfter(last);
  }
  return ids;
}

async function deletePostDocuments() {
  const ids = await listAllPostDocIds();
  console.log(`Firestore ${POSTS}: ${ids.length} document(s)`);
  if (!execute || ids.length === 0) return 0;

  let deleted = 0;
  for (let i = 0; i < ids.length; i += 500) {
    const batch = db.batch();
    const chunk = ids.slice(i, i + 500);
    for (const id of chunk) {
      batch.delete(db.collection(POSTS).doc(id));
    }
    await batch.commit();
    deleted += chunk.length;
    console.log(`  … Firestore batch committed (${deleted}/${ids.length})`);
  }
  return deleted;
}

async function deletePostImages() {
  const [files] = await bucket.getFiles({ prefix: STORAGE_PREFIX });
  const targets = files.filter((f) => !isProfileAvatarObject(f.name));
  console.log(
    `Storage gs://${bucket.name}/${STORAGE_PREFIX}: ${targets.length} object(s) (skipping profile_*)`,
  );
  if (!execute || targets.length === 0) return 0;

  let deleted = 0;
  for (const f of targets) {
    await f.delete();
    deleted++;
    if (deleted % 50 === 0) console.log(`  … deleted ${deleted}/${targets.length} files`);
  }
  if (targets.length % 50 !== 0) console.log(`  … deleted ${deleted}/${targets.length} files`);
  return deleted;
}

async function main() {
  if (!execute) {
    console.log('Dry run (no deletions). Add --execute to delete.\n');
  }

  console.log(`Project: ${projectId}, bucket: ${bucketName}\n`);

  const docCount = await deletePostDocuments();
  const fileCount = await deletePostImages();

  if (execute) {
    console.log('\nDone.');
    console.log(`  Firestore documents removed: ${docCount}`);
    console.log(`  Storage objects removed: ${fileCount}`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
