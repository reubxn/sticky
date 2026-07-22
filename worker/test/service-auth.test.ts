import { describe, expect, test } from "vitest";

import { workerServiceHmacVector } from "../../test-fixtures/workerServiceHmacVector";
import {
  canonicalServiceRequest,
  createSignedServiceHeaders,
  sha256Hex,
} from "../src/service-auth";

const textEncoder = new TextEncoder();

describe("Worker service HMAC compatibility", () => {
  test("matches the shared deterministic canonical request vector", async () => {
    const body = textEncoder.encode(workerServiceHmacVector.body);
    await expect(sha256Hex(body)).resolves.toBe(
      workerServiceHmacVector.bodyDigest,
    );
    expect(
      canonicalServiceRequest(
        workerServiceHmacVector.method,
        workerServiceHmacVector.path,
        workerServiceHmacVector.timestamp,
        workerServiceHmacVector.requestId,
        workerServiceHmacVector.bodyDigest,
      ),
    ).toBe(
      [
        workerServiceHmacVector.method,
        workerServiceHmacVector.path,
        workerServiceHmacVector.timestamp,
        workerServiceHmacVector.requestId,
        workerServiceHmacVector.bodyDigest,
      ].join("\n"),
    );
    await expect(
      createSignedServiceHeaders({
        method: workerServiceHmacVector.method,
        path: workerServiceHmacVector.path,
        timestamp: workerServiceHmacVector.timestamp,
        requestId: workerServiceHmacVector.requestId,
        body,
        keyId: workerServiceHmacVector.keyId,
        key: workerServiceHmacVector.key,
      }),
    ).resolves.toEqual({
      "content-type": "application/json",
      "x-sticky-key-id": workerServiceHmacVector.keyId,
      "x-sticky-timestamp": workerServiceHmacVector.timestamp,
      "x-sticky-request-id": workerServiceHmacVector.requestId,
      "x-sticky-signature": workerServiceHmacVector.signature,
    });
  });
});
