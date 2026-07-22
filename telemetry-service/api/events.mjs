const allowedKeys = new Set([
  "schemaVersion",
  "event",
  "mode",
  "word",
  "applicationCategory",
  "appVersion",
  "osMajorVersion",
]);

const allowedEvents = new Set(["replacement_applied", "replacement_rejected"]);
const allowedModes = new Set(["snippet", "spelling", "bilingual", "danish", "other"]);
const allowedCategories = new Set(["browser", "messaging", "writing", "other", "unknown"]);

export function validatePayload(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  if (Object.keys(value).some((key) => !allowedKeys.has(key))) return null;
  if (value.schemaVersion !== 1) return null;
  if (!allowedEvents.has(value.event)) return null;
  if (!allowedModes.has(value.mode)) return null;
  if (!allowedCategories.has(value.applicationCategory)) return null;
  if (typeof value.appVersion !== "string" || value.appVersion.length < 1 || value.appVersion.length > 24) return null;
  if (!Number.isInteger(value.osMajorVersion) || value.osMajorVersion < 14 || value.osMajorVersion > 99) return null;
  if (value.word !== null && value.word !== undefined) {
    if (typeof value.word !== "string" || !/^[\p{L}'-]{2,32}$/u.test(value.word)) return null;
    if (value.event !== "replacement_rejected" || value.applicationCategory === "browser") return null;
  }

  return {
    schemaVersion: 1,
    event: value.event,
    mode: value.mode,
    word: value.word ?? null,
    applicationCategory: value.applicationCategory,
    appVersion: value.appVersion,
    osMajorVersion: value.osMajorVersion,
  };
}

export default function handler(request, response) {
  if (request.method !== "POST") {
    response.setHeader("Allow", "POST");
    return response.status(405).json({ error: "method_not_allowed" });
  }

  const contentLength = Number(request.headers["content-length"] ?? 0);
  if (contentLength > 2048) {
    return response.status(413).json({ error: "payload_too_large" });
  }

  const payload = validatePayload(request.body);
  if (!payload) {
    return response.status(400).json({ error: "invalid_event" });
  }

  // Deliberately log only the validated aggregate event. Request headers, IP
  // addresses, surrounding text, exact bundle IDs, and device IDs are omitted.
  console.log(JSON.stringify({ type: "layoutpilot_usage", ...payload }));
  return response.status(202).json({ accepted: true });
}
