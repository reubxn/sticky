import type { WorkerRequestScope } from "./workerRequestPolicy";

export const workerServiceTimestampToleranceMs = 30_000;
export const workerServiceConsumePath =
  "/internal/worker/request-tickets/consume";
export const workerServiceCompletePath =
  "/internal/worker/request-tickets/complete";

const digestPattern = /^[0-9a-f]{64}$/;
const requestIdPattern = /^[A-Za-z0-9_-]{16,128}$/;
const keyIdPattern = /^[A-Za-z0-9_.-]{1,64}$/;
const signaturePattern = /^[0-9a-f]{64}$/;
const textEncoder = new TextEncoder();

type WorkerServiceCredentials = {
  currentKeyId: string;
  currentKey: string;
  previousKeyId?: string;
  previousKey?: string;
};

export type WorkerServiceAuthHeaders = {
  keyId: string;
  timestamp: string;
  requestId: string;
  signature: string;
};

export type WorkerConsumePayload = {
  ticketDigest: string;
  expectedScope: WorkerRequestScope;
  expectedRequestBodyDigest: string;
  expectedRequestBodyByteCount: number;
  workerRequestId: string;
};

export type WorkerCompletionPayload = {
  consumptionId: string;
  workerRequestId: string;
  completion: {
    outcome: "succeeded" | "provider_error" | "client_disconnected";
    providerRequestId?: string;
    httpStatusClass?: number;
    latencyMs: number;
    usage: {
      inputUnits?: number;
      outputUnits?: number;
    };
    errorCode?: string;
  };
};

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return (
    typeof value === "object" &&
    value !== null &&
    !Array.isArray(value) &&
    Object.getPrototypeOf(value) === Object.prototype
  );
}

function hasExactKeys(
  value: Record<string, unknown>,
  requiredKeys: readonly string[],
  optionalKeys: readonly string[] = [],
): boolean {
  const actualKeys = Object.keys(value);
  const allowedKeys = new Set([...requiredKeys, ...optionalKeys]);
  return (
    requiredKeys.every((key) => Object.hasOwn(value, key)) &&
    actualKeys.every((key) => allowedKeys.has(key))
  );
}

function isWorkerRequestScope(value: unknown): value is WorkerRequestScope {
  return (
    value === "onboarding_chat" ||
    value === "onboarding_tts" ||
    value === "onboarding_transcribe"
  );
}

function isSafeIntegerInRange(
  value: unknown,
  minimum: number,
  maximum: number,
): value is number {
  return (
    typeof value === "number" &&
    Number.isSafeInteger(value) &&
    value >= minimum &&
    value <= maximum
  );
}

function isBoundedString(
  value: unknown,
  minimumLength: number,
  maximumLength: number,
): value is string {
  return (
    typeof value === "string" &&
    value.length >= minimumLength &&
    value.length <= maximumLength
  );
}

export function parseWorkerConsumePayload(
  value: unknown,
): WorkerConsumePayload | null {
  if (
    !isPlainObject(value) ||
    !hasExactKeys(value, [
      "ticketDigest",
      "expectedScope",
      "expectedRequestBodyDigest",
      "expectedRequestBodyByteCount",
      "workerRequestId",
    ]) ||
    typeof value.ticketDigest !== "string" ||
    !digestPattern.test(value.ticketDigest) ||
    !isWorkerRequestScope(value.expectedScope) ||
    typeof value.expectedRequestBodyDigest !== "string" ||
    !digestPattern.test(value.expectedRequestBodyDigest) ||
    !isSafeIntegerInRange(value.expectedRequestBodyByteCount, 0, 4_096) ||
    typeof value.workerRequestId !== "string" ||
    !requestIdPattern.test(value.workerRequestId)
  ) {
    return null;
  }
  return {
    ticketDigest: value.ticketDigest,
    expectedScope: value.expectedScope,
    expectedRequestBodyDigest: value.expectedRequestBodyDigest,
    expectedRequestBodyByteCount: value.expectedRequestBodyByteCount,
    workerRequestId: value.workerRequestId,
  };
}

function parseWorkerCompletion(
  value: unknown,
): WorkerCompletionPayload["completion"] | null {
  if (
    !isPlainObject(value) ||
    !hasExactKeys(
      value,
      ["outcome", "latencyMs", "usage"],
      ["providerRequestId", "httpStatusClass", "errorCode"],
    ) ||
    (value.outcome !== "succeeded" &&
      value.outcome !== "provider_error" &&
      value.outcome !== "client_disconnected") ||
    !isSafeIntegerInRange(value.latencyMs, 0, 3_600_000) ||
    !isPlainObject(value.usage) ||
    !hasExactKeys(value.usage, [], ["inputUnits", "outputUnits"])
  ) {
    return null;
  }
  if (
    value.providerRequestId !== undefined &&
    (!isBoundedString(value.providerRequestId, 1, 128) ||
      !/^[A-Za-z0-9._:-]+$/.test(value.providerRequestId))
  ) {
    return null;
  }
  if (
    value.httpStatusClass !== undefined &&
    value.httpStatusClass !== 2 &&
    value.httpStatusClass !== 4 &&
    value.httpStatusClass !== 5
  ) {
    return null;
  }
  if (
    value.errorCode !== undefined &&
    (!isBoundedString(value.errorCode, 1, 64) ||
      !/^[A-Z0-9_]+$/.test(value.errorCode))
  ) {
    return null;
  }
  const inputUnits = value.usage.inputUnits;
  const outputUnits = value.usage.outputUnits;
  for (const unitCount of [inputUnits, outputUnits]) {
    if (
      unitCount !== undefined &&
      !isSafeIntegerInRange(unitCount, 0, 10_000_000)
    ) {
      return null;
    }
  }
  return {
    outcome: value.outcome,
    ...(value.providerRequestId === undefined
      ? {}
      : { providerRequestId: value.providerRequestId }),
    ...(value.httpStatusClass === undefined
      ? {}
      : { httpStatusClass: value.httpStatusClass }),
    latencyMs: value.latencyMs,
    usage: {
      ...(inputUnits === undefined
        ? {}
        : { inputUnits: inputUnits as number }),
      ...(outputUnits === undefined
        ? {}
        : { outputUnits: outputUnits as number }),
    },
    ...(value.errorCode === undefined ? {} : { errorCode: value.errorCode }),
  };
}

export function parseWorkerCompletionPayload(
  value: unknown,
): WorkerCompletionPayload | null {
  if (
    !isPlainObject(value) ||
    !hasExactKeys(value, [
      "consumptionId",
      "workerRequestId",
      "completion",
    ]) ||
    !isBoundedString(value.consumptionId, 1, 128) ||
    typeof value.workerRequestId !== "string" ||
    !requestIdPattern.test(value.workerRequestId)
  ) {
    return null;
  }
  const completion = parseWorkerCompletion(value.completion);
  if (completion === null) {
    return null;
  }
  return {
    consumptionId: value.consumptionId,
    workerRequestId: value.workerRequestId,
    completion,
  };
}

export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", Uint8Array.from(bytes));
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function canonicalWorkerServiceRequest(
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

function hexToBytes(value: string): Uint8Array {
  const bytes = new Uint8Array(value.length / 2);
  for (let index = 0; index < value.length; index += 2) {
    bytes[index / 2] = Number.parseInt(value.slice(index, index + 2), 16);
  }
  return bytes;
}

function selectServiceKey(
  keyId: string,
  credentials: WorkerServiceCredentials,
): string | null {
  if (keyId === credentials.currentKeyId) {
    return credentials.currentKey;
  }
  if (
    credentials.previousKeyId !== undefined &&
    credentials.previousKey !== undefined &&
    keyId === credentials.previousKeyId
  ) {
    return credentials.previousKey;
  }
  return null;
}

export async function verifyWorkerServiceRequest(options: {
  method: string;
  path: string;
  body: Uint8Array;
  headers: WorkerServiceAuthHeaders;
  credentials: WorkerServiceCredentials;
  now: number;
}): Promise<boolean> {
  const { headers, credentials } = options;
  if (
    !keyIdPattern.test(headers.keyId) ||
    !requestIdPattern.test(headers.requestId) ||
    !signaturePattern.test(headers.signature) ||
    !/^[0-9]{13}$/.test(headers.timestamp)
  ) {
    return false;
  }
  const timestamp = Number(headers.timestamp);
  if (
    !Number.isSafeInteger(timestamp) ||
    Math.abs(options.now - timestamp) > workerServiceTimestampToleranceMs
  ) {
    return false;
  }
  const keyValue = selectServiceKey(headers.keyId, credentials);
  if (keyValue === null || keyValue.length < 32 || keyValue.length > 512) {
    return false;
  }
  const bodyDigest = await sha256Hex(options.body);
  const canonicalRequest = canonicalWorkerServiceRequest(
    options.method,
    options.path,
    headers.timestamp,
    headers.requestId,
    bodyDigest,
  );
  const key = await crypto.subtle.importKey(
    "raw",
    textEncoder.encode(keyValue),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
  return await crypto.subtle.verify(
    "HMAC",
    key,
    Uint8Array.from(hexToBytes(headers.signature)),
    textEncoder.encode(canonicalRequest),
  );
}
