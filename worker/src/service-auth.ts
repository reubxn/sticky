const textEncoder = new TextEncoder();

type WorkerServiceEnvironment = Pick<
  Env,
  | "CONVEX_SITE_URL"
  | "WORKER_HMAC_CURRENT_KEY_ID"
  | "WORKER_HMAC_CURRENT_KEY"
>;

export const convexConsumePath =
  "/internal/worker/request-tickets/consume";
export const convexCompletePath =
  "/internal/worker/request-tickets/complete";

export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function canonicalServiceRequest(
  method: string,
  path: string,
  timestamp: string,
  requestId: string,
  bodyDigest: string,
): string {
  return [
    method.toUpperCase(),
    path,
    timestamp,
    requestId,
    bodyDigest,
  ].join("\n");
}

async function hmacSha256Hex(keyValue: string, value: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    textEncoder.encode(keyValue),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    textEncoder.encode(value),
  );
  return Array.from(new Uint8Array(signature))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function convexEndpoint(siteUrl: string, path: string): string {
  const url = new URL(siteUrl);
  if (url.pathname !== "/" || url.search !== "" || url.hash !== "") {
    throw new Error("CONVEX_SITE_URL must be an origin");
  }
  url.pathname = path;
  return url.toString();
}

export async function createSignedServiceHeaders(options: {
  method: string;
  path: string;
  timestamp: string;
  requestId: string;
  body: Uint8Array;
  keyId: string;
  key: string;
}): Promise<Record<string, string>> {
  const bodyDigest = await sha256Hex(options.body);
  const canonicalRequest = canonicalServiceRequest(
    options.method,
    options.path,
    options.timestamp,
    options.requestId,
    bodyDigest,
  );
  return {
    "content-type": "application/json",
    "x-sticky-key-id": options.keyId,
    "x-sticky-timestamp": options.timestamp,
    "x-sticky-request-id": options.requestId,
    "x-sticky-signature": await hmacSha256Hex(
      options.key,
      canonicalRequest,
    ),
  };
}

export async function signedConvexRequest(options: {
  env: WorkerServiceEnvironment;
  path: string;
  body: Uint8Array;
  requestId?: string;
}): Promise<Response> {
  const timestamp = Date.now().toString();
  const requestId = options.requestId ?? crypto.randomUUID();
  const headers = await createSignedServiceHeaders({
    method: "POST",
    path: options.path,
    timestamp,
    requestId,
    body: options.body,
    keyId: options.env.WORKER_HMAC_CURRENT_KEY_ID,
    key: options.env.WORKER_HMAC_CURRENT_KEY,
  });
  return await fetch(
    convexEndpoint(options.env.CONVEX_SITE_URL, options.path),
    {
      method: "POST",
      headers,
      body: options.body,
    },
  );
}
