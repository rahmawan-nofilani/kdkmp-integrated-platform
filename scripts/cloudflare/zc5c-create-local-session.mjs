import fs from "node:fs";
import { createServerClient } from "@supabase/ssr";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

if (!supabaseUrl || !publishableKey) {
  throw new Error("Local Supabase URL/publishable key are required for ZC-5C.");
}

if (!/^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?\/?$/i.test(supabaseUrl)) {
  throw new Error("ZC-5C refuses any non-loopback Supabase URL.");
}

const cookieJar = new Map();
const supabase = createServerClient(supabaseUrl, publishableKey, {
  cookies: {
    getAll() {
      return [...cookieJar.entries()].map(([name, entry]) => ({
        name,
        value: entry.value,
      }));
    },
    setAll(cookiesToSet) {
      for (const { name, value, options } of cookiesToSet) {
        if (options?.maxAge === 0 || value === "") {
          cookieJar.delete(name);
          continue;
        }
        cookieJar.set(name, { value, options: options ?? {} });
      }
    },
  },
});

const runId = process.env.GITHUB_RUN_ID ?? `${Date.now()}`;
const email = `zc5c-${runId}-${process.pid}@example.test`;
const password = `Zc5c-local-${runId}-${process.pid}!Aa9`;

let session;
const signUp = await supabase.auth.signUp({ email, password });
if (signUp.error) {
  throw signUp.error;
}
session = signUp.data.session;

if (!session) {
  const signIn = await supabase.auth.signInWithPassword({ email, password });
  if (signIn.error || !signIn.data.session) {
    throw signIn.error ?? new Error("Local sign-in did not return a session.");
  }
  session = signIn.data.session;
}

const claims = await supabase.auth.getClaims();
if (claims.error || !claims.data?.claims?.sub) {
  throw claims.error ?? new Error("Local session claims could not be verified.");
}

if (cookieJar.size === 0) {
  throw new Error("Supabase SSR did not persist an auth cookie.");
}

const cookieHeader = [...cookieJar.entries()]
  .map(([name, entry]) => `${name}=${entry.value}`)
  .join("; ");

fs.writeFileSync("/tmp/zc5c-cookie-header.txt", cookieHeader, {
  encoding: "utf8",
  mode: 0o600,
});
fs.writeFileSync(
  "/tmp/zc5c-session-meta.json",
  JSON.stringify(
    {
      expires_at: session.expires_at,
      cookie_names: [...cookieJar.keys()],
      subject_present: true,
    },
    null,
    2,
  ),
  { encoding: "utf8", mode: 0o600 },
);

console.log("local_auth_session_created=true");
console.log(`local_auth_cookie_count=${cookieJar.size}`);
console.log("local_auth_claims_verified=true");
console.log("remote_supabase_touched=false");
