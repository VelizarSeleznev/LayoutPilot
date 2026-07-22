import assert from "node:assert/strict";
import test from "node:test";
import { validatePayload } from "./events.mjs";

const valid = {
  schemaVersion: 1,
  event: "replacement_rejected",
  mode: "bilingual",
  word: "example",
  applicationCategory: "writing",
  appVersion: "1.2",
  osMajorVersion: 15,
};

test("accepts the bounded anonymous event shape", () => {
  assert.deepEqual(validatePayload(valid), valid);
});

test("rejects context and identifier fields", () => {
  assert.equal(validatePayload({ ...valid, bundleID: "com.apple.Notes" }), null);
  assert.equal(validatePayload({ ...valid, deviceID: "abc" }), null);
  assert.equal(validatePayload({ ...valid, contextBefore: ["private"] }), null);
});

test("never accepts a word from a browser", () => {
  assert.equal(validatePayload({ ...valid, applicationCategory: "browser" }), null);
});

test("accepts applied events only without a word", () => {
  assert.ok(validatePayload({ ...valid, event: "replacement_applied", word: null }));
  assert.equal(validatePayload({ ...valid, event: "replacement_applied" }), null);
});
