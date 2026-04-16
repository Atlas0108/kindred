#!/usr/bin/env node
/**
 * Seeds Kindred with 5 demo users (Firebase Auth + `users` docs), 3 community-event posts,
 * 3 help-offer posts, and 3 help-request posts (creators include nonprofit + business accounts).
 * Events use the same `posts` collection as offers/requests with kind `community_event` (see lib/core/models/post.dart).
 *
 *   If GOOGLE_APPLICATION_CREDENTIALS is unset, the script uses repo secrets/firebase-adminsdk.json
 *   when that file exists (gitignored). Otherwise set the env var to your service account JSON path.
 *   optional: export DEMO_SEED_PASSWORD="YourSharedPassword123!"
 *   cd scripts/seed_demo && npm install
 *   node seed_demo.mjs              # dry-run
 *   node seed_demo.mjs --execute    # write data
 *
 * Re-running with --execute creates additional posts (new IDs). Auth users are reused if the
 * emails already exist. Optional: FIREBASE_STORAGE_BUCKET (default ${projectId}.firebasestorage.app).
 */

import admin from 'firebase-admin';
import ngeohash from 'ngeohash';
import { randomUUID } from 'node:crypto';

import {
  applyDefaultGoogleApplicationCredentialsIfUnset,
  assertValidGoogleApplicationCredentialsPath,
  resolveFirebaseProjectId,
} from '../resolve_firebase_project.mjs';

const execute = process.argv.includes('--execute');
const wantHelp = process.argv.includes('--help') || process.argv.includes('-h');

if (wantHelp) {
  console.log(`
Usage: node seed_demo.mjs [--execute]

  (default)  Print what would be created.
  --execute  Create Auth users (if missing) and write Firestore documents.

Env:
  GOOGLE_APPLICATION_CREDENTIALS  (optional if secrets/firebase-adminsdk.json exists) service account JSON path
  GOOGLE_CLOUD_PROJECT / GCLOUD_PROJECT / FIREBASE_PROJECT_ID  (optional; else project_id in key or repo firebase.json)
  DEMO_SEED_PASSWORD                (optional) password for all demo accounts; default built-in demo password
`);
  process.exit(0);
}

const DEMO_PASSWORD =
  process.env.DEMO_SEED_PASSWORD || 'KindredDemo2026!';

// Default seed target after project migration. Still overridable via:
// GOOGLE_CLOUD_PROJECT / GCLOUD_PROJECT / FIREBASE_PROJECT_ID
process.env.FIREBASE_PROJECT_ID ??= 'public-commons';

/** All seeded posts use this point (Portland, Oregon) so local feeds map to one metro. */
const SEED_POST_LAT = 45.5152;
const SEED_POST_LNG = -122.6784;

/** Match lib/core/geo/geo_utils.dart: precision 5 (~4.9 km cells). JS ngeohash uses lat, lng. */
function geohash5(lat, lng) {
  return ngeohash.encode(lat, lng, 5);
}

let db;
let auth;
let projectId = '(dry-run)';
let GeoPoint;
let Timestamp;

if (execute) {
  applyDefaultGoogleApplicationCredentialsIfUnset(import.meta.url);
  assertValidGoogleApplicationCredentialsPath();
  const resolvedProjectId = resolveFirebaseProjectId(import.meta.url);
  if (!admin.apps.length) {
    admin.initializeApp(resolvedProjectId ? { projectId: resolvedProjectId } : {});
  }
  db = admin.firestore();
  auth = admin.auth();
  projectId = admin.app().options.projectId || resolvedProjectId;
  if (!projectId) {
    console.error(
      'Could not determine Firebase project ID. Set GOOGLE_CLOUD_PROJECT, use a service account JSON with "project_id", or run from the repo so ../../firebase.json is found.',
    );
    process.exit(1);
  }
  GeoPoint = admin.firestore.GeoPoint;
  Timestamp = admin.firestore.Timestamp;
}

const demoUsers = [
  {
    email: 'kindred-demo-maya@example.invalid',
    displayName: 'Maya Chen',
    neighborhood: 'Northside Neighbor',
    lat: 37.7765,
    lng: -122.4172,
  },
  {
    email: 'kindred-demo-jordan@example.invalid',
    displayName: 'Jordan Reed',
    neighborhood: 'Mission Roots',
    lat: 37.7599,
    lng: -122.4148,
  },
  {
    email: 'kindred-demo-sam@example.invalid',
    displayName: 'Sam Okonkwo',
    neighborhood: 'Bayview Block',
    lat: 37.7308,
    lng: -122.3834,
  },
  {
    email: 'kindred-demo-social-good-fund@example.invalid',
    displayName: 'Social Good Fund',
    accountType: 'nonprofit',
    organizationName: 'Social Good Fund',
    neighborhood: 'Portland Metro',
    lat: 45.5152,
    lng: -122.6784,
  },
  {
    email: 'kindred-demo-mazlo@example.invalid',
    displayName: 'Mazlo',
    accountType: 'business',
    businessName: 'Mazlo',
    neighborhood: 'Pearl District',
    lat: 45.5253,
    lng: -122.6844,
  },
];

/** organizerIndex / authorIndex: 0–2 personal demos, 3 = Social Good Fund (nonprofit), 4 = Mazlo (business). */
const demoEvents = [
  {
    title: 'Community garden workday',
    description:
      'Mulch paths, plant winter greens, and share tools. Gloves provided; bring a water bottle.',
    locationDescription: 'SE Portland community garden — meet at the tool shed',
    organizerIndex: 3,
    startsInDays: 3,
    durationHours: 3,
  },
  {
    title: 'Neighborhood potluck',
    description:
      'Bring a dish to share (label ingredients). Live music and kids’ craft table in the back.',
    locationDescription: 'Alberta Arts district — check the map pin for the cross street',
    organizerIndex: 4,
    startsInDays: 10,
    durationHours: 4,
  },
  {
    title: 'Snow shovel brigade signup',
    description:
      'We pair volunteers with neighbors who need walks cleared after storms. Sign up for your block.',
    locationDescription: 'Virtual kickoff + shared spreadsheet — link in event chat',
    organizerIndex: 2,
    startsInDays: 45,
    durationHours: 2,
  },
];

const demoOffers = [
  {
    authorIndex: 3,
    title: 'Grant-writing office hours (virtual)',
    body: 'Social Good Fund is offering two 30-minute slots this week for small neighborhood projects — questions on applications, budgets, or timelines welcome.',
  },
  {
    authorIndex: 4,
    title: 'Complimentary tastings — new spring menu',
    body: 'Mazlo is sampling our spring pastries and pour-over bar Saturday 9–12; stop by and say hi to the team.',
  },
  {
    authorIndex: 0,
    title: 'Free compost delivery',
    body: 'I have extra finished compost from my bins — happy to drop off a few buckets within 2 miles.',
  },
];

const demoRequests = [
  {
    authorIndex: 4,
    title: 'Borrow a folding table for weekend pop-up',
    body: 'Mazlo needs one sturdy 6-foot folding table Sat–Sun for a sidewalk tasting; will pick up and return clean.',
  },
  {
    authorIndex: 3,
    title: 'Volunteers for supply sorting day',
    body: 'Social Good Fund needs 4–6 people for a 3-hour sort at our warehouse — gloves and snacks provided.',
  },
  {
    authorIndex: 1,
    title: 'Help setting up a used laptop',
    body: 'Bought a refurbished Mac for my kid; would love 30 minutes with someone patient to get accounts and parental controls sorted.',
  },
];

async function getOrCreateUser({ email, password, displayName }) {
  try {
    const existing = await auth.getUserByEmail(email);
    return existing;
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    return auth.createUser({
      email,
      password,
      displayName,
      emailVerified: false,
    });
  }
}

async function seedUserDoc(uid, u) {
  const gp = new GeoPoint(u.lat, u.lng);
  const accountType = u.accountType || 'personal';
  const data = {
    displayName: u.displayName,
    accountType,
    discoveryRadiusMiles: 25,
    karma: 12,
    createdAt: Timestamp.now(),
    homeGeoPoint: gp,
    neighborhoodLabel: u.neighborhood,
    eventsAttended: 4,
    requestsFulfilled: 2,
  };
  const FieldValue = admin.firestore.FieldValue;
  if (accountType === 'nonprofit') {
    data.organizationName = u.organizationName || u.displayName;
    data.firstName = FieldValue.delete();
    data.lastName = FieldValue.delete();
    data.businessName = FieldValue.delete();
  } else if (accountType === 'business') {
    data.businessName = u.businessName || u.displayName;
    data.firstName = FieldValue.delete();
    data.lastName = FieldValue.delete();
    data.organizationName = FieldValue.delete();
  }
  await db.collection('users').doc(uid).set(data, { merge: true });
}

async function seedCommunityEventPost(template, usersByIndex) {
  const org = usersByIndex[template.organizerIndex];
  const id = randomUUID();
  if (!execute) return id;

  const starts = new Date();
  starts.setDate(starts.getDate() + template.startsInDays);
  starts.setHours(10, 0, 0, 0);
  const ends = new Date(starts.getTime() + template.durationHours * 60 * 60 * 1000);
  const gp = new GeoPoint(SEED_POST_LAT, SEED_POST_LNG);
  /** Matches KindredPost.toCreateMap() for PostKind.communityEvent (lib/core/models/post.dart). */
  const data = {
    authorId: org.uid,
    authorName: org.displayName,
    kind: 'community_event',
    title: template.title,
    body: template.description,
    geoPoint: gp,
    geohash: geohash5(SEED_POST_LAT, SEED_POST_LNG),
    status: 'open',
    createdAt: Timestamp.now(),
    startsAt: Timestamp.fromDate(starts),
    endsAt: Timestamp.fromDate(ends),
    locationDescription: template.locationDescription,
  };
  await db.collection('posts').doc(id).set(data);
  return id;
}

/** @param {'help_offer' | 'help_request'} kind */
async function seedHelpDeskPost(template, usersByIndex, kind) {
  const author = usersByIndex[template.authorIndex];
  const id = randomUUID();
  if (!execute) return id;

  const gp = new GeoPoint(SEED_POST_LAT, SEED_POST_LNG);
  const data = {
    authorId: author.uid,
    authorName: author.displayName,
    kind,
    title: template.title,
    body: template.body,
    geoPoint: gp,
    geohash: geohash5(SEED_POST_LAT, SEED_POST_LNG),
    status: 'open',
    createdAt: Timestamp.now(),
  };
  await db.collection('posts').doc(id).set(data);
  return id;
}

async function main() {
  if (!execute) {
    console.log('Dry run (no writes). Add --execute to seed.\n');
  }

  console.log(`Project: ${projectId}`);
  console.log(`Demo password (new users only): ${DEMO_PASSWORD}\n`);

  const usersByIndex = [];

  for (const u of demoUsers) {
    if (execute) {
      const rec = await getOrCreateUser({
        email: u.email,
        password: DEMO_PASSWORD,
        displayName: u.displayName,
      });
      await seedUserDoc(rec.uid, u);
      usersByIndex.push({
        uid: rec.uid,
        email: u.email,
        displayName: u.displayName,
        lat: u.lat,
        lng: u.lng,
      });
      console.log(`User: ${u.displayName} <${u.email}>  uid=${rec.uid}`);
    } else {
      usersByIndex.push({
        uid: '(dry-run)',
        email: u.email,
        displayName: u.displayName,
        lat: u.lat,
        lng: u.lng,
      });
      console.log(`User: ${u.displayName} <${u.email}>`);
    }
  }

  console.log('');
  for (const ev of demoEvents) {
    const id = await seedCommunityEventPost(ev, usersByIndex);
    console.log(`Event post: "${ev.title}" → ${execute ? id : '(would create)'}`);
  }

  console.log('');
  for (const off of demoOffers) {
    const id = await seedHelpDeskPost(off, usersByIndex, 'help_offer');
    console.log(`Offer: "${off.title}" → ${execute ? id : '(would create)'}`);
  }

  console.log('');
  for (const req of demoRequests) {
    const id = await seedHelpDeskPost(req, usersByIndex, 'help_request');
    console.log(`Request: "${req.title}" → ${execute ? id : '(would create)'}`);
  }

  if (execute) {
    console.log('\nSeed complete. Sign in with any demo email and the password above.');
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
