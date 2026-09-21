#!/usr/bin/env node
// craft-user-agent — DPoP (RFC 9449) client for Craft's per-user `/user/agent`
// gateway. curl can drive every hop EXCEPT minting the DPoP proof: a proof is an
// ES256 JWS whose signature must be raw r‖s (IEEE P1363), and openssl emits DER.
// Node's WebCrypto signs P1363 directly — and is the same primitive a browser
// agent uses — so this small client is the proof-bearing engine of the skill.
//
// Subcommands:
//   request-otp <email>           → POST /auth {email}; sends the 6-digit PIN
//   login --email E --code NNNNNN → OTP verify → PKCE consent → DPoP-bound token,
//                                   cached (with its holder keypair) at the store
//   run --caps a,b [--file f.js]  → submit a worker to /user/agent, DPoP-signed
//                                   (auto nonce-challenge retry + token refresh)
//   whoami                        → print the cached identity (no secrets)
//
// The cache (default ~/.craft/user-agent.json, override with CRAFT_USER_AGENT_STORE)
// holds the access/refresh tokens AND the private holder key — the token is inert
// without it (that's the sender-constraint). Treat it as a credential (chmod 600).

import { readFileSync, writeFileSync, existsSync, mkdirSync, chmodSync } from "node:fs";
import { homedir } from "node:os";
import { dirname } from "node:path";

const BASE = process.env.CRAFT_BASE || "https://craft.everygoodwork.dev";
const STORE = process.env.CRAFT_USER_AGENT_STORE || `${homedir()}/.craft/user-agent.json`;
const REDIRECT_URI = "http://localhost/cb";
const subtle = crypto.subtle;
const enc = new TextEncoder();

const b64url = (b) => Buffer.from(b).toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const sha256url = async (s) => b64url(await subtle.digest("SHA-256", enc.encode(s)));
const die = (msg) => { console.error(`error: ${msg}`); process.exit(1); };

function loadStore() {
  if (!existsSync(STORE)) die(`no cached identity at ${STORE} — run "login" first`);
  return JSON.parse(readFileSync(STORE, "utf8"));
}
function saveStore(s) {
  mkdirSync(dirname(STORE), { recursive: true });
  writeFileSync(STORE, JSON.stringify(s, null, 2));
  chmodSync(STORE, 0o600);
}

async function importSigningKey(jwk) {
  return subtle.importKey("jwk", jwk, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}
// Build + sign a DPoP proof. The public JWK is embedded in the header; the server
// derives the thumbprint from it and matches it to the token's cnf.jkt.
async function makeProof(privKey, publicJwk, { htm, htu, ath, nonce, iat }) {
  const header = b64url(enc.encode(JSON.stringify({ typ: "dpop+jwt", alg: "ES256", jwk: publicJwk })));
  const claims = { jti: b64url(crypto.getRandomValues(new Uint8Array(16))), htm, htu, iat: iat ?? Math.floor(Date.now() / 1000) };
  if (ath) claims.ath = ath;
  if (nonce) claims.nonce = nonce;
  const payload = b64url(enc.encode(JSON.stringify(claims)));
  const sig = await subtle.sign({ name: "ECDSA", hash: "SHA-256" }, privKey, enc.encode(`${header}.${payload}`));
  return `${header}.${payload}.${b64url(sig)}`;
}

const form = (obj) => new URLSearchParams(obj).toString();
const FORM = "application/x-www-form-urlencoded";

// ── request-otp ──────────────────────────────────────────────────────────────
async function requestOtp(email) {
  if (!email) die("request-otp <email>");
  const r = await fetch(`${BASE}/auth`, {
    method: "POST",
    headers: { Origin: BASE, "Datastar-Request": "true", "content-type": "application/json" },
    body: JSON.stringify({ email }),
  });
  console.log(`request-otp ${email} → ${r.status} (check the inbox for the 6-digit PIN)`);
}

// ── login: OTP → cookie → PKCE consent → DPoP-bound token ────────────────────
async function login(email, code) {
  if (!email || !code) die("login --email E --code NNNNNN");

  const vr = await fetch(`${BASE}/auth`, {
    method: "POST",
    headers: { Origin: BASE, "Datastar-Request": "true", "content-type": "application/json" },
    body: JSON.stringify({ email, code }),
  });
  const cookie = ((vr.headers.get("set-cookie") || "").match(/(__Host-)?craft_session=[^;]+/) || [])[0];
  if (!cookie) die(`OTP verify failed (status ${vr.status}) — wrong/expired code?`);

  // Generate the holder keypair (the token will be bound to its thumbprint).
  const kp = await subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const privJwk = await subtle.exportKey("jwk", kp.privateKey);
  const pub = await subtle.exportKey("jwk", kp.publicKey);
  const publicJwk = { kty: "EC", crv: "P-256", x: pub.x, y: pub.y };

  // PKCE + consent (the user self-authorizes their own agent; the OTP was the
  // human-in-the-loop step). POST /consent registers a public client + returns
  // the code on a localhost redirect.
  const verifier = b64url(crypto.getRandomValues(new Uint8Array(32)));
  const challenge = await sha256url(verifier);
  const cr = await fetch(`${BASE}/consent`, {
    method: "POST", redirect: "manual",
    headers: { Origin: BASE, Cookie: cookie, "content-type": FORM },
    body: form({ decision: "approve", client_name: "craft-user-agent", redirect_uri: REDIRECT_URI, code_challenge: challenge, code_challenge_method: "S256", state: b64url(crypto.getRandomValues(new Uint8Array(8))), scope: "read write publish" }),
  });
  const loc = cr.headers.get("location") || "";
  // Decode the percent-encoded redirect params — the shard-routable code is `{email}:{grant}:{rand}`,
  // whose `@`/`:` arrive percent-encoded; capturing them raw and re-encoding double-encodes the code,
  // so the AS routes to the wrong shard + a mismatched hash → "authorization code not found" (craft#114).
  const qsDecode = (m) => (m ? decodeURIComponent(m[1]) : undefined);
  const authCode = qsDecode(loc.match(/[?&]code=([^&]+)/));
  const clientId = qsDecode(loc.match(/[?&]client_id=([^&]+)/));
  if (!authCode || !clientId) die(`consent failed (status ${cr.status}); location=${loc}`);

  // Token exchange WITH a DPoP proof → the issued token carries cnf.jkt.
  const tokenUrl = `${BASE}/oauth/token`;
  const proof = await makeProof(kp.privateKey, publicJwk, { htm: "POST", htu: tokenUrl });
  const tr = await fetch(tokenUrl, {
    method: "POST",
    headers: { Origin: BASE, DPoP: proof, "content-type": FORM },
    body: form({ grant_type: "authorization_code", code: authCode, redirect_uri: REDIRECT_URI, client_id: clientId, code_verifier: verifier }),
  });
  const tok = await tr.json().catch(() => ({}));
  if (tr.status !== 200 || !tok.access_token) die(`token exchange failed (status ${tr.status}): ${JSON.stringify(tok)}`);

  saveStore({ base: BASE, email, client_id: clientId, priv_jwk: privJwk, public_jwk: publicJwk, access_token: tok.access_token, refresh_token: tok.refresh_token, obtained_at: Date.now(), expires_in: tok.expires_in });
  console.log(`logged in as ${email} — DPoP-bound token cached at ${STORE} (expires_in=${tok.expires_in}s)`);
}

// ── refresh: rotate the access token, preserving the bound key ───────────────
async function refreshToken(store, privKey) {
  if (!store.refresh_token) return false;
  const tokenUrl = `${store.base}/oauth/token`;
  // /oauth/token enforces the RFC 9449 §8 server-nonce too — mirror callAgent: first proof sans nonce, re-sign with the challenged nonce, retry once.
  const attempt = async (nonce) => {
    const proof = await makeProof(privKey, store.public_jwk, { htm: "POST", htu: tokenUrl, nonce });
    return fetch(tokenUrl, {
      method: "POST",
      headers: { Origin: store.base, DPoP: proof, "content-type": FORM },
      body: form({ grant_type: "refresh_token", refresh_token: store.refresh_token, client_id: store.client_id }),
    });
  };
  let tr = await attempt(undefined);
  if (tr.status === 401) {
    const ch = await tr.clone().json().catch(() => ({}));
    const nonce = tr.headers.get("dpop-nonce");
    if (nonce && ch.error === "use_dpop_nonce") tr = await attempt(nonce);
  }
  const tok = await tr.json().catch(() => ({}));
  if (tr.status !== 200 || !tok.access_token) {
    console.error(`[refresh] /oauth/token -> ${tr.status} ${JSON.stringify(tok)}`);
    return false;
  }
  store.access_token = tok.access_token;
  if (tok.refresh_token) store.refresh_token = tok.refresh_token;
  store.obtained_at = Date.now();
  store.expires_in = tok.expires_in;
  saveStore(store);
  return true;
}

// ── run: submit a worker to /user/agent, DPoP-signed ─────────────────────────
async function callAgent(store, privKey, body) {
  const agentUrl = `${store.base}/user/agent`;
  const ath = await sha256url(store.access_token);
  // First attempt with no nonce — the server challenges with one (RFC 9449 §8),
  // then we re-sign (fresh jti) and retry once.
  const attempt = async (nonce) => {
    const proof = await makeProof(privKey, store.public_jwk, { htm: "POST", htu: agentUrl, ath, nonce });
    return fetch(agentUrl, { method: "POST", headers: { Origin: store.base, Authorization: `DPoP ${store.access_token}`, DPoP: proof, "content-type": "application/json" }, body });
  };
  let res = await attempt(undefined);
  if (res.status === 401) {
    const challenge = await res.clone().json().catch(() => ({}));
    const nonce = res.headers.get("dpop-nonce");
    if (nonce && challenge.error === "use_dpop_nonce") res = await attempt(nonce);
  }
  return res;
}

async function run(caps, codeFile) {
  const store = loadStore();
  const privKey = await importSigningKey(store.priv_jwk);
  const code = codeFile ? readFileSync(codeFile, "utf8") : readFileSync(0, "utf8");
  if (!code.trim()) die("no worker source (pass --file f.js or pipe code on stdin)");
  const body = JSON.stringify({ code, capabilities: caps });

  let res = await callAgent(store, privKey, body);
  // Token expired (not a nonce challenge) → refresh once, retry.
  if (res.status === 401) {
    const j = await res.clone().json().catch(() => ({}));
    if (j.error !== "use_dpop_nonce" && (await refreshToken(store, privKey))) {
      res = await callAgent(store, privKey, body);
    }
  }
  const out = await res.json().catch(() => ({}));
  console.log(JSON.stringify(out, null, 2));
  process.exit(out.ok === true ? 0 : 1);
}

function whoami() {
  const s = loadStore();
  const ageMin = Math.round((Date.now() - s.obtained_at) / 60000);
  console.log(`identity: ${s.email}\nbase:     ${s.base}\njkt:      bound (holder key cached)\ntoken:    obtained ${ageMin} min ago, expires_in=${s.expires_in}s`);
}

// ── arg parse ────────────────────────────────────────────────────────────────
const [cmd, ...rest] = process.argv.slice(2);
const flag = (name) => { const i = rest.indexOf(`--${name}`); return i >= 0 ? rest[i + 1] : undefined; };
switch (cmd) {
  case "request-otp": await requestOtp(rest[0] || flag("email")); break;
  case "login": await login(flag("email"), flag("code")); break;
  case "run": await run((flag("caps") || "").split(",").filter(Boolean), flag("file")); break;
  case "whoami": whoami(); break;
  default:
    console.error("usage: dpop.mjs <request-otp|login|run|whoami> [opts]\n  request-otp <email>\n  login --email E --code NNNNNN\n  run --caps App:create,User:ping [--file worker.js]   (else reads stdin)\n  whoami");
    process.exit(1);
}
