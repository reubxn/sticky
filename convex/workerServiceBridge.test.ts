/// <reference types="vite/client" />

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";

import { workerServiceHmacVector } from "../test-fixtures/workerServiceHmacVector";
import schema from "./schema";
import {
  canonicalWorkerServiceRequest,
  parseWorkerCompletionPayload,
  parseWorkerConsumePayload,
  sha256Hex,
  verifyWorkerServiceRequest,
  workerServiceConsumePath,
} from "./workerServiceBridge";

const modules = import.meta.glob("./**/*.ts");
const textEncoder = new TextEncoder();
const currentKey = "c".repeat(32);
const previousKey = "p".repeat(32);
const now = 1_800_000_000_000;

async function signRequest(options: {
  key: string;
  body: Uint8Array;
  timestamp?: string;
  requestId?: string;
}) {
  const timestamp = options.timestamp ?? String(now);
  const requestId = options.requestId ?? "worker_request_1234";
  const canonical = canonicalWorkerServiceRequest(
    "POST",
    workerServiceConsumePath,
    timestamp,
    requestId,
    await sha256Hex(options.body),
  );
  const importedKey = await crypto.subtle.importKey(
    "raw",
    textEncoder.encode(options.key),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    importedKey,
    textEncoder.encode(canonical),
  );
  return {
    timestamp,
    requestId,
    signature: Array.from(new Uint8Array(signature))
      .map((byte) => byte.toString(16).padStart(2, "0"))
      .join(""),
  };
}

describe("Worker service request authentication", () => {
  test("accepts the shared Worker signature and rejects a mutated body byte", async () => {
    const body = textEncoder.encode(workerServiceHmacVector.body);
    const options = {
      method: workerServiceHmacVector.method,
      path: workerServiceHmacVector.path,
      headers: {
        keyId: workerServiceHmacVector.keyId,
        timestamp: workerServiceHmacVector.timestamp,
        requestId: workerServiceHmacVector.requestId,
        signature: workerServiceHmacVector.signature,
      },
      credentials: {
        currentKeyId: workerServiceHmacVector.keyId,
        currentKey: workerServiceHmacVector.key,
      },
      now: Number(workerServiceHmacVector.timestamp),
    };
    await expect(
      verifyWorkerServiceRequest({ ...options, body }),
    ).resolves.toBe(true);

    const mutatedBody = Uint8Array.from(body);
    mutatedBody[mutatedBody.byteLength - 1] ^= 1;
    await expect(
      verifyWorkerServiceRequest({ ...options, body: mutatedBody }),
    ).resolves.toBe(false);
  });

  test("canonicalizes method, path, timestamp, request ID, and body digest", () => {
    expect(
      canonicalWorkerServiceRequest(
        "post",
        workerServiceConsumePath,
        "1800000000000",
        "worker_request_1234",
        "a".repeat(64),
      ),
    ).toBe(
      [
        "POST",
        workerServiceConsumePath,
        "1800000000000",
        "worker_request_1234",
        "a".repeat(64),
      ].join("\n"),
    );
  });

  test("accepts current and previous keys but rejects unknown key IDs", async () => {
    const body = textEncoder.encode('{"ticketDigest":"value"}');
    const credentials = {
      currentKeyId: "current-2026-07",
      currentKey,
      previousKeyId: "previous-2026-06",
      previousKey,
    };
    for (const [keyId, key] of [
      [credentials.currentKeyId, currentKey],
      [credentials.previousKeyId, previousKey],
    ] as const) {
      const signed = await signRequest({ key, body });
      await expect(
        verifyWorkerServiceRequest({
          method: "POST",
          path: workerServiceConsumePath,
          body,
          headers: { keyId, ...signed },
          credentials,
          now,
        }),
      ).resolves.toBe(true);
    }
    const signed = await signRequest({ key: currentKey, body });
    await expect(
      verifyWorkerServiceRequest({
        method: "POST",
        path: workerServiceConsumePath,
        body,
        headers: { keyId: "unknown", ...signed },
        credentials,
        now,
      }),
    ).resolves.toBe(false);
  });

  test("rejects stale, future, malformed, and tampered requests", async () => {
    const body = textEncoder.encode("{}");
    const credentials = {
      currentKeyId: "current",
      currentKey,
    };
    const valid = await signRequest({ key: currentKey, body });
    const scenarios = [
      {
        body,
        headers: {
          keyId: "current",
          ...(await signRequest({
            key: currentKey,
            body,
            timestamp: String(now - 30_001),
          })),
        },
      },
      {
        body,
        headers: {
          keyId: "current",
          ...(await signRequest({
            key: currentKey,
            body,
            timestamp: String(now + 30_001),
          })),
        },
      },
      {
        body,
        headers: { keyId: "current", ...valid, requestId: "short" },
      },
      {
        body,
        headers: { keyId: "current", ...valid, signature: "0".repeat(64) },
      },
      {
        body: textEncoder.encode('{"tampered":true}'),
        headers: { keyId: "current", ...valid },
      },
    ];
    for (const scenario of scenarios) {
      await expect(
        verifyWorkerServiceRequest({
          method: "POST",
          path: workerServiceConsumePath,
          body: scenario.body,
          headers: scenario.headers,
          credentials,
          now,
        }),
      ).resolves.toBe(false);
    }
  });
});

describe("Worker service payload validation", () => {
  const validConsume = {
    ticketDigest: "a".repeat(64),
    expectedScope: "onboarding_chat",
    expectedRequestBodyDigest: "b".repeat(64),
    expectedRequestBodyByteCount: 42,
    workerRequestId: "worker_request_1234",
  };
  const validCompletion = {
    consumptionId: "consumption_1234",
    workerRequestId: "worker_request_1234",
    completion: {
      outcome: "succeeded",
      latencyMs: 12,
      usage: { inputUnits: 1, outputUnits: 2 },
    },
  };

  test("accepts strict consume and completion payloads", () => {
    expect(parseWorkerConsumePayload(validConsume)).toEqual(validConsume);
    expect(parseWorkerCompletionPayload(validCompletion)).toEqual(
      validCompletion,
    );
  });

  test("rejects plaintext tickets, unknown keys, invalid types, and malformed completion", () => {
    for (const value of [
      { ...validConsume, ticket: "plaintext-ticket" },
      { ...validConsume, ticketDigest: "A".repeat(64) },
      { ...validConsume, expectedRequestBodyByteCount: 1.5 },
      { ...validConsume, expectedScope: "chat" },
      { ...validConsume, workerRequestId: "short" },
    ]) {
      expect(parseWorkerConsumePayload(value)).toBeNull();
    }
    for (const value of [
      { ...validCompletion, extra: true },
      {
        ...validCompletion,
        completion: { ...validCompletion.completion, prompt: "private" },
      },
      {
        ...validCompletion,
        completion: { ...validCompletion.completion, latencyMs: -1 },
      },
      {
        ...validCompletion,
        completion: {
          ...validCompletion.completion,
          usage: { inputUnits: "1" },
        },
      },
    ]) {
      expect(parseWorkerCompletionPayload(value)).toBeNull();
    }
  });
});

describe("Worker service HTTP route closure", () => {
  test("registers only exact POST routes and rejects malformed bodies generically", async () => {
    const testBackend = convexTest(schema, modules);
    const wrongMethod = await testBackend.fetch(workerServiceConsumePath, {
      method: "GET",
    });
    expect(wrongMethod.status).toBe(404);

    const wrongPath = await testBackend.fetch(
      `${workerServiceConsumePath}/extra`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: "{}",
      },
    );
    expect(wrongPath.status).toBe(404);

    const wrongContentType = await testBackend.fetch(
      workerServiceConsumePath,
      {
        method: "POST",
        headers: { "content-type": "text/plain" },
        body: "{}",
      },
    );
    expect(wrongContentType.status).toBe(400);
    await expect(wrongContentType.json()).resolves.toEqual({
      error: "invalid_request",
    });

    const oversized = await testBackend.fetch(workerServiceConsumePath, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "x".repeat(2_049),
    });
    expect(oversized.status).toBe(400);
    await expect(oversized.json()).resolves.toEqual({
      error: "invalid_request",
    });

    const unauthenticated = await testBackend.fetch(
      workerServiceConsumePath,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: "{}",
      },
    );
    expect(unauthenticated.status).toBe(401);
    await expect(unauthenticated.json()).resolves.toEqual({
      error: "service_auth_failed",
    });
  });
});
