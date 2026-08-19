export type KdkmpEnvironment = "development" | "staging" | "production";

const ALLOWED_ENVIRONMENTS = new Set<KdkmpEnvironment>([
  "development",
  "staging",
  "production",
]);

export function getAppEnvironment(): KdkmpEnvironment {
  const configured = process.env.KDKMP_APP_ENV?.trim().toLowerCase();

  // Safe default for the existing zero-cost DEVELOPMENT runtime. A future
  // staging/production deployment must opt in explicitly through environment
  // configuration rather than being inferred from a hosting-provider label.
  if (!configured) return "development";

  if (!ALLOWED_ENVIRONMENTS.has(configured as KdkmpEnvironment)) {
    throw new Error("KDKMP_APP_ENV_INVALID");
  }

  return configured as KdkmpEnvironment;
}

export function getSupabaseProjectRef(supabaseUrl: string | undefined) {
  if (!supabaseUrl) return null;

  try {
    const hostname = new URL(supabaseUrl).hostname.toLowerCase();
    const suffix = ".supabase.co";
    if (!hostname.endsWith(suffix)) return null;
    const ref = hostname.slice(0, -suffix.length);
    return ref || null;
  } catch {
    return null;
  }
}

export function getEnvironmentTargetGuard() {
  const environment = getAppEnvironment();
  const expectedSupabaseRef = process.env.KDKMP_EXPECTED_SUPABASE_REF?.trim() || null;
  const actualSupabaseRef = getSupabaseProjectRef(process.env.NEXT_PUBLIC_SUPABASE_URL);

  // DEVELOPMENT keeps compatibility with the current environment while
  // staging/production require an explicit target pin. This prevents a future
  // production deployment from silently using the DEVELOPMENT database.
  const expectedTargetConfigured = Boolean(expectedSupabaseRef);
  const targetMatches = expectedSupabaseRef
    ? actualSupabaseRef === expectedSupabaseRef
    : environment === "development";

  return {
    environment,
    expectedTargetConfigured,
    targetMatches,
  };
}
