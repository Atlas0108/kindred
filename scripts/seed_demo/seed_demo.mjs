#!/usr/bin/env node
/**
 * Seeds Kindred with 3 demo users (Firebase Auth + `users` docs), 3 events, and 3 help-offer posts.
 *
 *   export GOOGLE_APPLICATION_CREDENTIALS="$HOME/Downloads/your-project-firebase-adminsdk-xxxxx.json"
 *   optional: export DEMO_SEED_PASSWORD="YourSharedPassword123!"
 *   cd scripts/seed_demo && npm install
 *   node seed_demo.mjs              # dry-run
 *   node seed_demo.mjs --execute    # write data
 *
 * Re-running with --execute creates additional events/posts (new IDs). Auth users are reused if the
 * emails already exist. Optional: FIREBASE_STORAGE_BUCKET (default ${projectId}.firebasestorage.app).
 */

import admin from 'firebase-admin';
import ngeohash from 'ngeohash';
import { randomUUID } from 'node:crypto';

import {
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
  GOOGLE_APPLICATION_CREDENTIALS  (required for --execute) service account JSON path
  GOOGLE_CLOUD_PROJECT / GCLOUD_PROJECT / FIREBASE_PROJECT_ID  (optional; else project_id in key or repo firebase.json)
  DEMO_SEED_PASSWORD                (optional) password for all demo accounts; default built-in demo password
`);
  process.exit(0);
}

const DEMO_PASSWORD =
  process.env.DEMO_SEED_PASSWORD || 'KindredDemo2026!';

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
];

const demoEvents = [
  {
    title: 'Community garden workday',
    description:
      'Mulch paths, plant winter greens, and share tools. Gloves provided; bring a water bottle.',
    tags: ['outdoors', 'volunteer', 'garden'],
    locationDescription: 'Sunset Community Garden, 37.776°N — meet at the tool shed',
    organizerIndex: 0,
    startsInDays: 3,
    durationHours: 3,
  },
  {
    title: 'Neighborhood potluck',
    description:
      'Bring a dish to share (label ingredients). Live music and kids’ craft table in the back.',
    tags: ['food', 'social', 'family'],
    locationDescription: 'Jordan’s front yard — check the map pin for the cross street',
    organizerIndex: 1,
    startsInDays: 10,
    durationHours: 4,
  },
  {
    title: 'Snow shovel brigade signup',
    description:
      'We pair volunteers with neighbors who need walks cleared after storms. Sign up for your block.',
    tags: ['winter', 'help', 'seniors'],
    locationDescription: 'Virtual kickoff + shared spreadsheet — link in event chat',
    organizerIndex: 2,
    startsInDays: 45,
    durationHours: 2,
  },
];

const demoOffers = [
  {
    authorIndex: 0,
    title: 'Free compost delivery',
    body: 'I have extra finished compost from my bins — happy to drop off a few buckets within 2 miles.',
    tags: ['garden', 'sustainability'],
    lat: 37.7765,
    lng: -122.4172,
  },
  {
    authorIndex: 1,
    title: 'Loan power tools for weekend projects',
    body: 'Circular saw, drill, and ladder available Fri–Sun if you pick up and return in good shape.',
    tags: ['tools', 'diy'],
    lat: 37.7599,
    lng: -122.4148,
  },
  {
    authorIndex: 2,
    title: 'Dog walking when you travel',
    body: 'I WFH and walk my pup daily — can add yours for short trips (small/medium dogs).',
    tags: ['pets', 'neighbors'],
    lat: 37.7308,
    lng: -122.3834,
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
  const data = {
    displayName: u.displayName,
    discoveryRadiusMiles: 25,
    karma: 12,
    createdAt: Timestamp.now(),
    homeGeoPoint: gp,
    neighborhoodLabel: u.neighborhood,
    profileTags: ['COMMUNITY ORGANIZER'],
    eventsAttended: 4,
    requestsFulfilled: 2,
  };
  await db.collection('users').doc(uid).set(data, { merge: true });
}

async function seedEvent(template, usersByIndex) {
  const org = usersByIndex[template.organizerIndex];
  const id = randomUUID();
  if (!execute) return id;

  const starts = new Date();
  starts.setDate(starts.getDate() + template.startsInDays);
  starts.setHours(10, 0, 0, 0);
  const ends = new Date(starts.getTime() + template.durationHours * 60 * 60 * 1000);
  const gp = new GeoPoint(org.lat, org.lng);
  const data = {
    organizerId: org.uid,
    title: template.title,
    description: template.description,
    startsAt: Timestamp.fromDate(starts),
    endsAt: Timestamp.fromDate(ends),
    organizerName: org.displayName,
    tags: template.tags,
    locationDescription: template.locationDescription,
    geoPoint: gp,
    geohash: geohash5(org.lat, org.lng),
    createdAt: Timestamp.now(),
  };
  await db.collection('events').doc(id).set(data);
  return id;
}

async function seedOffer(template, usersByIndex) {
  const author = usersByIndex[template.authorIndex];
  const id = randomUUID();
  if (!execute) return id;

  const gp = new GeoPoint(template.lat, template.lng);
  const data = {
    authorId: author.uid,
    authorName: author.displayName,
    kind: 'help_offer',
    tags: template.tags,
    title: template.title,
    body: template.body,
    geoPoint: gp,
    geohash: geohash5(template.lat, template.lng),
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
    const id = await seedEvent(ev, usersByIndex);
    console.log(`Event: "${ev.title}" → ${execute ? id : '(would create)'}`);
  }

  console.log('');
  for (const off of demoOffers) {
    const id = await seedOffer(off, usersByIndex);
    console.log(`Offer: "${off.title}" → ${execute ? id : '(would create)'}`);
  }

  if (execute) {
    console.log('\nSeed complete. Sign in with any demo email and the password above.');
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
