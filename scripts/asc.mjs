// Talking to App Store Connect.
//
// Two scripts need this now — the one that works out the next build number and
// the one that writes the "what to test" card — so the ten lines of ES256 JWT
// live here rather than in both.

import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export const APP_ID = process.env.ASC_APP_ID || "6821508828";
const KEY_ID = process.env.ASC_KEY_ID || "L7V5YSAY53";
const ISSUER = process.env.ASC_ISSUER_ID || "c78ac3f0-011a-464e-8710-d101fa9031d8";

/// Downloadable exactly once, so it lives where Apple's own tools look for it
/// rather than anywhere in this repo.
const KEY_PATH = path.join(
  os.homedir(), ".appstoreconnect", "private_keys", `AuthKey_${KEY_ID}.p8`
);

function token() {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const now = Math.floor(Date.now() / 1000);
  const input =
    `${b64({ alg: "ES256", kid: KEY_ID, typ: "JWT" })}.` +
    `${b64({ iss: ISSUER, iat: now, exp: now + 600, aud: "appstoreconnect-v1" })}`;
  const signature = crypto.sign("SHA256", Buffer.from(input), {
    key: crypto.createPrivateKey(fs.readFileSync(KEY_PATH, "utf8")),
    dsaEncoding: "ieee-p1363",
  });
  return `${input}.${signature.toString("base64url")}`;
}

/// One request. Throws with what Apple actually said rather than a status
/// code, because "409" on its own has never helped anybody at eleven at night.
export async function asc(pathAndQuery, { method = "GET", body } = {}) {
  const response = await fetch(`https://api.appstoreconnect.apple.com${pathAndQuery}`, {
    method,
    headers: {
      authorization: `Bearer ${token()}`,
      ...(body ? { "content-type": "application/json" } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  if (!response.ok) {
    const said = await response.text();
    throw new Error(`app store connect said ${response.status}: ${said.slice(0, 400)}`);
  }
  return response.status === 204 ? null : response.json();
}
