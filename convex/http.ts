import { httpRouter } from "convex/server";

import { internal } from "./_generated/api";
import { httpAction } from "./_generated/server";
import {
  parseWorkerCompletionPayload,
  parseWorkerConsumePayload,
  verifyWorkerServiceRequest,
  workerServiceCompletePath,
  workerServiceConsumePath,
} from "./workerServiceBridge";

declare const process: {
  env: Record<string, string | undefined>;
};

const maximumServiceBodyByteCount = 2_048;

function jsonResponse(
  status: number,
  body: Record<string, unknown>,
): Response {
  return Response.json(body, {
    status,
    headers: {
      "cache-control": "no-store",
      "content-type": "application/json; charset=utf-8",
    },
  });
}

function serviceCredentials() {
  return {
    currentKeyId: process.env.WORKER_HMAC_CURRENT_KEY_ID ?? "",
    currentKey: process.env.WORKER_HMAC_CURRENT_KEY ?? "",
    previousKeyId: process.env.WORKER_HMAC_PREVIOUS_KEY_ID,
    previousKey: process.env.WORKER_HMAC_PREVIOUS_KEY,
  };
}

async function readBoundedRequestBytes(
  request: Request,
): Promise<Uint8Array | null> {
  if (request.body === null) {
    return new Uint8Array();
  }
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let totalByteCount = 0;
  while (true) {
    const result = await reader.read();
    if (result.done) {
      break;
    }
    totalByteCount += result.value.byteLength;
    if (totalByteCount > maximumServiceBodyByteCount) {
      await reader.cancel();
      return null;
    }
    chunks.push(result.value);
  }
  const bodyBytes = new Uint8Array(totalByteCount);
  let offset = 0;
  for (const chunk of chunks) {
    bodyBytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bodyBytes;
}

async function readAuthenticatedBody(
  request: Request,
  expectedPath: string,
): Promise<{ bodyBytes: Uint8Array; body: unknown } | Response> {
  if (request.headers.get("content-type") !== "application/json") {
    return jsonResponse(400, { error: "invalid_request" });
  }
  const contentLength = request.headers.get("content-length");
  if (
    contentLength !== null &&
    (!/^[0-9]+$/.test(contentLength) ||
      Number(contentLength) > maximumServiceBodyByteCount)
  ) {
    return jsonResponse(400, { error: "invalid_request" });
  }
  const bodyBytes = await readBoundedRequestBytes(request);
  if (bodyBytes === null) {
    return jsonResponse(400, { error: "invalid_request" });
  }
  const keyId = request.headers.get("x-sticky-key-id");
  const timestamp = request.headers.get("x-sticky-timestamp");
  const requestId = request.headers.get("x-sticky-request-id");
  const signature = request.headers.get("x-sticky-signature");
  if (
    keyId === null ||
    timestamp === null ||
    requestId === null ||
    signature === null ||
    !(await verifyWorkerServiceRequest({
      method: request.method,
      path: expectedPath,
      body: bodyBytes,
      headers: { keyId, timestamp, requestId, signature },
      credentials: serviceCredentials(),
      now: Date.now(),
    }))
  ) {
    return jsonResponse(401, { error: "service_auth_failed" });
  }
  try {
    const bodyText = new TextDecoder("utf-8", { fatal: true }).decode(
      bodyBytes,
    );
    return { bodyBytes, body: JSON.parse(bodyText) as unknown };
  } catch {
    return jsonResponse(400, { error: "invalid_request" });
  }
}

const http = httpRouter();

http.route({
  path: workerServiceConsumePath,
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    const authenticatedBody = await readAuthenticatedBody(
      request,
      workerServiceConsumePath,
    );
    if (authenticatedBody instanceof Response) {
      return authenticatedBody;
    }
    const payload = parseWorkerConsumePayload(authenticatedBody.body);
    if (payload === null) {
      return jsonResponse(400, { error: "invalid_request" });
    }
    try {
      const result = await ctx.runMutation(
        internal.workerRequestTicketMutations.consume,
        payload,
      );
      return jsonResponse(200, {
        consumptionId: result.consumptionId,
        policyVersion: result.policyVersion,
        policy: result.policy,
      });
    } catch {
      return jsonResponse(403, { error: "request_denied" });
    }
  }),
});

http.route({
  path: workerServiceCompletePath,
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    const authenticatedBody = await readAuthenticatedBody(
      request,
      workerServiceCompletePath,
    );
    if (authenticatedBody instanceof Response) {
      return authenticatedBody;
    }
    const payload = parseWorkerCompletionPayload(authenticatedBody.body);
    if (payload === null) {
      return jsonResponse(400, { error: "invalid_request" });
    }
    try {
      await ctx.runMutation(
        internal.workerRequestTicketMutations.complete,
        payload,
      );
      return jsonResponse(200, { ok: true });
    } catch {
      return jsonResponse(403, { error: "request_denied" });
    }
  }),
});

export default http;
