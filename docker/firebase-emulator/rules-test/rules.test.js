// firestore.rules, checked against the Firestore emulator.
//
// Django reaches Firestore through the Admin SDK, which bypasses the rules, so
// no client should reach the data directly at all: the rules deny everything.
// These checks hold them to that. Every kind of client access (get, list,
// query, collection-group query, create, set, update, delete, batch,
// transaction) is tried on every collection the API writes, signed out and
// signed in: as a stranger, as the document's own owner, and with admin and
// verified-email claims. Each must be refused with permission-denied, and
// after every refused write the data is checked unchanged.
//
// The last group loads looser rules and shows the same checks fail, so a
// check can't pass by never reaching the rules.
//
// Run with `make test-rules`, or in CI's Firestore Rules job.

import { after, before, beforeEach, describe, test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  collection,
  collectionGroup,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  runTransaction,
  setDoc,
  setLogLevel,
  updateDoc,
  where,
  writeBatch,
} from "firebase/firestore";

// Every refused request is otherwise logged as an error.
setLogLevel("silent");

const RULES_PATH =
  process.env.FIRESTORE_RULES ??
  fileURLToPath(new URL("../../../firestore.rules", import.meta.url));
const RULES = readFileSync(RULES_PATH, "utf8");

// The emulator's address; firebase emulators:exec sets this.
const [host, port] = (process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080").split(":");

const OWNER = "owner-a";

// One document of each kind the API stores, with its owner where it has one
// (backend/apps/*/repositories.py has the layout).
const DOCS = {
  "user_profiles/owner-a": { owner_key: OWNER, city: "Leeds" },
  "people/p1": { owner_key: OWNER, first_name: "Ada", city: "London" },
  "people/public": { owner_key: null, first_name: "Grace" },
  "people/p1/contact_logs/l1": { owner_key: OWNER, log_id: "l1", channel: "call" },
  "trips/t1": { owner_key: OWNER, name: "Spring" },
  "trips/t1/stops/s1": { owner_key: OWNER, sequence_order: 0 },
  "trips/t1/legs/g1": { owner_key: OWNER, leg_id: "g1", mode: "train" },
};
const COLLECTIONS = ["user_profiles", "people", "people/p1/contact_logs", "trips", "trips/t1/stops", "trips/t1/legs"];
const GROUPS = ["contact_logs", "stops", "legs"];

// Who tries. Firebase Auth tokens are what a direct client would present.
const CALLERS = {
  "signed out": (env) => env.unauthenticatedContext(),
  "a stranger": (env) => env.authenticatedContext("stranger"),
  "the owner": (env) => env.authenticatedContext(OWNER),
  "the owner with a verified email": (env) =>
    env.authenticatedContext(OWNER, { email: "a@example.com", email_verified: true }),
  "an admin claim": (env) => env.authenticatedContext("someone", { admin: true }),
};

async function seed(env) {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [path, data] of Object.entries(DOCS)) {
      await setDoc(doc(db, path), data);
    }
  });
}

// Every document, read with the rules off, so a refused write can be shown to
// have changed nothing.
async function snapshot(env) {
  const out = {};
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const path of Object.keys(DOCS)) {
      const snap = await getDoc(doc(db, path));
      out[path] = snap.exists() ? snap.data() : undefined;
    }
    for (const name of COLLECTIONS) {
      const snaps = await getDocs(collection(db, name));
      for (const d of snaps.docs) out[d.ref.path] = d.data();
    }
  });
  return out;
}

// The reads and writes a client could try, each as [name, fn(db)].
function reads() {
  const tries = [];
  for (const path of Object.keys(DOCS)) {
    tries.push([`get ${path}`, (db) => getDoc(doc(db, path))]);
  }
  for (const name of COLLECTIONS) {
    tries.push([`list ${name}`, (db) => getDocs(collection(db, name))]);
    tries.push([
      `query ${name} for the owner's documents`,
      (db) => getDocs(query(collection(db, name), where("owner_key", "==", OWNER))),
    ]);
  }
  for (const group of GROUPS) {
    tries.push([
      `collection-group query ${group}`,
      (db) => getDocs(query(collectionGroup(db, group), where("owner_key", "==", OWNER))),
    ]);
  }
  return tries;
}

function writes() {
  const tries = [];
  for (const path of Object.keys(DOCS)) {
    tries.push([`overwrite ${path}`, (db) => setDoc(doc(db, path), { owner_key: "stranger" })]);
    tries.push([`update ${path}`, (db) => updateDoc(doc(db, path), { owner_key: "stranger" })]);
    tries.push([`delete ${path}`, (db) => deleteDoc(doc(db, path))]);
  }
  for (const name of COLLECTIONS) {
    tries.push([
      `create a document in ${name}`,
      (db) => setDoc(doc(db, `${name}/new-doc`), { owner_key: OWNER }),
    ]);
  }
  tries.push([
    "create a top-level collection the API doesn't use",
    (db) => setDoc(doc(db, "anything/new-doc"), { a: 1 }),
  ]);
  tries.push([
    "commit a batch",
    (db) => {
      const batch = writeBatch(db);
      batch.set(doc(db, "people/batched"), { owner_key: OWNER });
      batch.delete(doc(db, "people/p1"));
      return batch.commit();
    },
  ]);
  tries.push([
    "run a transaction",
    (db) =>
      runTransaction(db, async (txn) => {
        await txn.get(doc(db, "people/p1"));
        txn.update(doc(db, "people/p1"), { city: "Paris" });
      }),
  ]);
  return tries;
}

async function environment(projectId, rules) {
  return initializeTestEnvironment({
    projectId,
    firestore: { rules, host, port: Number(port) },
  });
}

describe("firestore.rules", () => {
  let env;
  let before_;

  before(async () => {
    env = await environment("demo-rules-deny", RULES);
    await seed(env);
    before_ = await snapshot(env);
  });
  after(() => env.cleanup());

  test("the rules under test are the repository's", () => {
    assert.match(RULES, /allow read, write: if false;/);
  });

  for (const [caller, contextFor] of Object.entries(CALLERS)) {
    describe(`as ${caller}`, () => {
      for (const [what, attempt] of reads()) {
        test(`can't ${what}`, async () => {
          await assertFails(attempt(contextFor(env).firestore()));
        });
      }
      for (const [what, attempt] of writes()) {
        test(`can't ${what}, and nothing changes`, async () => {
          await assertFails(attempt(contextFor(env).firestore()));
          assert.deepEqual(await snapshot(env), before_);
        });
      }
    });
  }
});

// The checks above pass on permission-denied only. Under rules that let the
// owner in, the same attempts succeed, so they're really reaching the rules.
describe("the checks catch looser rules", () => {
  const OPEN_TO_OWNERS = `rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if request.auth != null
        && (resource == null || resource.data.owner_key == request.auth.uid);
    }
  }
}`;
  let env;

  before(async () => {
    env = await environment("demo-rules-loose", OPEN_TO_OWNERS);
  });
  beforeEach(() => seed(env));
  after(() => env.cleanup());

  test("the owner's get is refused by the real rules but not these", async () => {
    const db = env.authenticatedContext(OWNER).firestore();
    await assertSucceeds(getDoc(doc(db, "people/p1")));
  });

  test("the owner's update goes through, and the snapshot sees it", async () => {
    const db = env.authenticatedContext(OWNER).firestore();
    await assertSucceeds(updateDoc(doc(db, "people/p1"), { city: "Paris" }));
    const after = await snapshot(env);
    assert.equal(after["people/p1"].city, "Paris");
  });

  test("a stranger is still refused, so assertFails sees permission-denied", async () => {
    const db = env.authenticatedContext("stranger").firestore();
    await assertFails(getDoc(doc(db, "people/p1")));
  });
});
