import {
  convexCompletePath,
  convexConsumePath,
  sha256Hex,
  signedConvexRequest,
} from "./service-auth";

const textEncoder = new TextEncoder();
const jsonHeaders = {
  "cache-control": "no-store",
  "content-type": "application/json; charset=utf-8",
};

type OnboardingEnvironment = Omit<Env, "ONBOARDING_ROUTES_ENABLED">;

type OnboardingScope =
  | "onboarding_chat"
  | "onboarding_tts"
  | "onboarding_transcribe";

type TrustedPolicy =
  | {
      kind: "onboarding_chat";
      model: string;
      systemPrompt: string;
      maximumOutputTokens: number;
    }
  | {
      kind: "onboarding_tts";
      voiceId: string;
      model: string;
      outputFormat: string;
      stability: number;
      similarityBoost: number;
    }
  | {
      kind: "onboarding_transcribe";
      redemptionWindowSeconds: number;
      maximumSessionSeconds: number;
    };

type ConsumedTicket = {
  consumptionId: string;
  policyVersion: number;
  policy: TrustedPolicy;
};

type Completion = {
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

function jsonError(status: number, error: string): Response {
  return Response.json({ error }, { status, headers: jsonHeaders });
}

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
): boolean {
  const actualKeys = Object.keys(value);
  return (
    actualKeys.length === requiredKeys.length &&
    requiredKeys.every((key) => Object.hasOwn(value, key))
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

async function readBoundedBody(
  request: Request,
  maximumByteCount: number,
): Promise<Uint8Array | null> {
  const contentLength = request.headers.get("content-length");
  if (
    contentLength !== null &&
    (!/^[0-9]+$/.test(contentLength) ||
      Number(contentLength) > maximumByteCount)
  ) {
    return null;
  }
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
    if (totalByteCount > maximumByteCount) {
      await reader.cancel();
      return null;
    }
    chunks.push(result.value);
  }
  const body = new Uint8Array(totalByteCount);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return body;
}

function parseJsonBytes(body: Uint8Array): unknown | null {
  try {
    const text = new TextDecoder("utf-8", {
      fatal: true,
      ignoreBOM: false,
    }).decode(body);
    return JSON.parse(text) as unknown;
  } catch {
    return null;
  }
}

function parseChatBody(
  body: Uint8Array,
): { text: string; clientTurnId: string } | null {
  const value = parseJsonBytes(body);
  if (
    !isPlainObject(value) ||
    !hasExactKeys(value, ["text", "clientTurnId"]) ||
    !isBoundedString(value.text, 1, 2_000) ||
    textEncoder.encode(value.text).byteLength > 2_000 ||
    !isBoundedString(value.clientTurnId, 1, 128) ||
    !/^[A-Za-z0-9._:-]+$/.test(value.clientTurnId)
  ) {
    return null;
  }
  return { text: value.text, clientTurnId: value.clientTurnId };
}

function parseTTSBody(body: Uint8Array): { text: string } | null {
  const value = parseJsonBytes(body);
  if (
    !isPlainObject(value) ||
    !hasExactKeys(value, ["text"]) ||
    !isBoundedString(value.text, 1, 4_000) ||
    textEncoder.encode(value.text).byteLength > 4_000
  ) {
    return null;
  }
  return { text: value.text };
}

function parseTrustedPolicy(value: unknown): TrustedPolicy | null {
  if (!isPlainObject(value) || typeof value.kind !== "string") {
    return null;
  }
  if (
    value.kind === "onboarding_chat" &&
    hasExactKeys(value, [
      "kind",
      "model",
      "systemPrompt",
      "maximumOutputTokens",
    ]) &&
    isBoundedString(value.model, 1, 128) &&
    isBoundedString(value.systemPrompt, 1, 8_192) &&
    isSafeIntegerInRange(value.maximumOutputTokens, 1, 4_096)
  ) {
    return {
      kind: value.kind,
      model: value.model,
      systemPrompt: value.systemPrompt,
      maximumOutputTokens: value.maximumOutputTokens,
    };
  }
  if (
    value.kind === "onboarding_tts" &&
    hasExactKeys(value, [
      "kind",
      "voiceId",
      "model",
      "outputFormat",
      "stability",
      "similarityBoost",
    ]) &&
    isBoundedString(value.voiceId, 1, 64) &&
    /^[A-Za-z0-9_-]+$/.test(value.voiceId) &&
    isBoundedString(value.model, 1, 64) &&
    isBoundedString(value.outputFormat, 1, 64) &&
    typeof value.stability === "number" &&
    Number.isFinite(value.stability) &&
    value.stability >= 0 &&
    value.stability <= 1 &&
    typeof value.similarityBoost === "number" &&
    Number.isFinite(value.similarityBoost) &&
    value.similarityBoost >= 0 &&
    value.similarityBoost <= 1
  ) {
    return {
      kind: value.kind,
      voiceId: value.voiceId,
      model: value.model,
      outputFormat: value.outputFormat,
      stability: value.stability,
      similarityBoost: value.similarityBoost,
    };
  }
  if (
    value.kind === "onboarding_transcribe" &&
    hasExactKeys(value, [
      "kind",
      "redemptionWindowSeconds",
      "maximumSessionSeconds",
    ]) &&
    isSafeIntegerInRange(value.redemptionWindowSeconds, 1, 600) &&
    isSafeIntegerInRange(value.maximumSessionSeconds, 60, 10_800)
  ) {
    return {
      kind: value.kind,
      redemptionWindowSeconds: value.redemptionWindowSeconds,
      maximumSessionSeconds: value.maximumSessionSeconds,
    };
  }
  return null;
}

function parseConsumedTicket(value: unknown): ConsumedTicket | null {
  if (
    !isPlainObject(value) ||
    !hasExactKeys(value, ["consumptionId", "policyVersion", "policy"]) ||
    !isBoundedString(value.consumptionId, 1, 128) ||
    !isSafeIntegerInRange(value.policyVersion, 1, 1_000)
  ) {
    return null;
  }
  const policy = parseTrustedPolicy(value.policy);
  if (policy === null) {
    return null;
  }
  return {
    consumptionId: value.consumptionId,
    policyVersion: value.policyVersion,
    policy,
  };
}

function ticketFromAuthorization(request: Request): string | null {
  const authorization = request.headers.get("authorization");
  if (authorization === null) {
    return null;
  }
  const match = /^StickyTicket ([A-Za-z0-9_-]{43})$/.exec(authorization);
  return match?.[1] ?? null;
}

async function consumeTicket(options: {
  request: Request;
  env: OnboardingEnvironment;
  scope: OnboardingScope;
  body: Uint8Array;
  workerRequestId: string;
}): Promise<ConsumedTicket | null> {
  const ticket = ticketFromAuthorization(options.request);
  if (ticket === null) {
    return null;
  }
  const consumePayload = textEncoder.encode(
    JSON.stringify({
      ticketDigest: await sha256Hex(textEncoder.encode(ticket)),
      expectedScope: options.scope,
      expectedRequestBodyDigest: await sha256Hex(options.body),
      expectedRequestBodyByteCount: options.body.byteLength,
      workerRequestId: options.workerRequestId,
    }),
  );
  const response = await signedConvexRequest({
    env: options.env,
    path: convexConsumePath,
    body: consumePayload,
  });
  if (!response.ok) {
    await response.body?.cancel();
    return null;
  }
  const responseBody = await readBoundedBody(
    new Request("https://internal.invalid", {
      method: "POST",
      body: response.body,
      headers: response.headers,
    }),
    16_384,
  );
  if (responseBody === null) {
    return null;
  }
  return parseConsumedTicket(parseJsonBytes(responseBody));
}

async function reportCompletion(options: {
  env: OnboardingEnvironment;
  consumptionId: string;
  workerRequestId: string;
  completion: Completion;
}): Promise<void> {
  const body = textEncoder.encode(
    JSON.stringify({
      consumptionId: options.consumptionId,
      workerRequestId: options.workerRequestId,
      completion: options.completion,
    }),
  );
  const maximumAttempts = 3;
  for (let attempt = 1; attempt <= maximumAttempts; attempt += 1) {
    let shouldRetry = true;
    try {
      const response = await signedConvexRequest({
        env: options.env,
        path: convexCompletePath,
        body,
      });
      await response.body?.cancel();
      if (response.ok) {
        return;
      }
      // These statuses can be caused by transient edge/load conditions.
      // Other 4xx responses mean the signed request or ticket was denied.
      shouldRetry =
        response.status === 408 ||
        response.status === 425 ||
        response.status === 429 ||
        (response.status >= 500 && response.status <= 599);
    } catch {
      shouldRetry = true;
    }
    if (!shouldRetry || attempt === maximumAttempts) {
      return;
    }
    await new Promise<void>((resolve) => {
      setTimeout(resolve, 25 * attempt);
    });
  }
}

function providerRequestId(response: Response): string | undefined {
  const requestId =
    response.headers.get("request-id") ??
    response.headers.get("x-request-id");
  if (
    requestId !== null &&
    requestId.length <= 128 &&
    /^[A-Za-z0-9._:-]+$/.test(requestId)
  ) {
    return requestId;
  }
  return undefined;
}

function completionLatencyMs(startedAt: number): number {
  return Math.min(Math.max(Date.now() - startedAt, 0), 3_600_000);
}

function streamedProviderResponse(options: {
  response: Response;
  abortController: AbortController;
  env: OnboardingEnvironment;
  ctx: ExecutionContext;
  consumptionId: string;
  workerRequestId: string;
  startedAt: number;
  fallbackContentType: string;
}): Response {
  if (options.response.body === null) {
    options.ctx.waitUntil(
      reportCompletion({
        env: options.env,
        consumptionId: options.consumptionId,
        workerRequestId: options.workerRequestId,
        completion: {
          outcome: "provider_error",
          httpStatusClass: 5,
          latencyMs: completionLatencyMs(options.startedAt),
          usage: {},
          errorCode: "EMPTY_PROVIDER_STREAM",
        },
      }),
    );
    return jsonError(502, "provider_unavailable");
  }
  const reader = options.response.body.getReader();
  let didFinalize = false;
  const finalize = (
    outcome: Completion["outcome"],
    errorCode?: string,
  ): void => {
    if (didFinalize) {
      return;
    }
    didFinalize = true;
    options.ctx.waitUntil(
      reportCompletion({
        env: options.env,
        consumptionId: options.consumptionId,
        workerRequestId: options.workerRequestId,
        completion: {
          outcome,
          providerRequestId: providerRequestId(options.response),
          httpStatusClass: 2,
          latencyMs: completionLatencyMs(options.startedAt),
          usage: {},
          ...(errorCode === undefined ? {} : { errorCode }),
        },
      }),
    );
  };
  const body = new ReadableStream<Uint8Array>({
    async pull(controller) {
      try {
        const result = await reader.read();
        if (result.done) {
          finalize("succeeded");
          controller.close();
          return;
        }
        controller.enqueue(result.value);
      } catch {
        finalize("provider_error", "PROVIDER_STREAM_ERROR");
        controller.error(new Error("Provider stream failed"));
      }
    },
    async cancel() {
      options.abortController.abort();
      try {
        await reader.cancel();
      } finally {
        finalize("client_disconnected");
      }
    },
  });
  return new Response(body, {
    status: options.response.status,
    headers: {
      "cache-control": "no-store",
      "content-type":
        options.response.headers.get("content-type") ??
        options.fallbackContentType,
    },
  });
}

function completeProviderFailure(options: {
  env: OnboardingEnvironment;
  ctx: ExecutionContext;
  consumed: ConsumedTicket;
  workerRequestId: string;
  startedAt: number;
  status: number;
  errorCode: string;
}): Response {
  options.ctx.waitUntil(
    reportCompletion({
      env: options.env,
      consumptionId: options.consumed.consumptionId,
      workerRequestId: options.workerRequestId,
      completion: {
        outcome: "provider_error",
        httpStatusClass:
          options.status >= 500 && options.status <= 599 ? 5 : 4,
        latencyMs: completionLatencyMs(options.startedAt),
        usage: {},
        errorCode: options.errorCode,
      },
    }),
  );
  return jsonError(502, "provider_unavailable");
}

export async function handleOnboardingChat(
  request: Request,
  env: OnboardingEnvironment,
  ctx: ExecutionContext,
): Promise<Response> {
  if (ticketFromAuthorization(request) === null) {
    return jsonError(401, "authentication_required");
  }
  if (request.headers.get("content-type") !== "application/json") {
    return jsonError(400, "invalid_request");
  }
  const body = await readBoundedBody(request, 2_304);
  if (body === null) {
    return jsonError(400, "invalid_request");
  }
  const chat = parseChatBody(body);
  if (chat === null) {
    return jsonError(400, "invalid_request");
  }
  const workerRequestId = crypto.randomUUID();
  const consumed = await consumeTicket({
    request,
    env,
    scope: "onboarding_chat",
    body,
    workerRequestId,
  });
  if (consumed === null || consumed.policy.kind !== "onboarding_chat") {
    return jsonError(403, "request_denied");
  }
  const startedAt = Date.now();
  const abortController = new AbortController();
  let response: Response;
  try {
    response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
        "x-api-key": env.ANTHROPIC_API_KEY,
      },
      body: JSON.stringify({
        model: consumed.policy.model,
        system: consumed.policy.systemPrompt,
        max_tokens: consumed.policy.maximumOutputTokens,
        stream: true,
        messages: [
          {
            role: "user",
            content: [{ type: "text", text: chat.text }],
          },
        ],
      }),
      signal: abortController.signal,
    });
  } catch {
    return completeProviderFailure({
      env,
      ctx,
      consumed,
      workerRequestId,
      startedAt,
      status: 500,
      errorCode: "PROVIDER_FETCH_ERROR",
    });
  }
  if (!response.ok) {
    await response.body?.cancel();
    return completeProviderFailure({
      env,
      ctx,
      consumed,
      workerRequestId,
      startedAt,
      status: response.status,
      errorCode: "PROVIDER_HTTP_ERROR",
    });
  }
  return streamedProviderResponse({
    response,
    abortController,
    env,
    ctx,
    consumptionId: consumed.consumptionId,
    workerRequestId,
    startedAt,
    fallbackContentType: "text/event-stream",
  });
}

export async function handleOnboardingTTS(
  request: Request,
  env: OnboardingEnvironment,
  ctx: ExecutionContext,
): Promise<Response> {
  if (ticketFromAuthorization(request) === null) {
    return jsonError(401, "authentication_required");
  }
  if (request.headers.get("content-type") !== "application/json") {
    return jsonError(400, "invalid_request");
  }
  const body = await readBoundedBody(request, 4_096);
  if (body === null) {
    return jsonError(400, "invalid_request");
  }
  const tts = parseTTSBody(body);
  if (tts === null) {
    return jsonError(400, "invalid_request");
  }
  const workerRequestId = crypto.randomUUID();
  const consumed = await consumeTicket({
    request,
    env,
    scope: "onboarding_tts",
    body,
    workerRequestId,
  });
  if (consumed === null || consumed.policy.kind !== "onboarding_tts") {
    return jsonError(403, "request_denied");
  }
  const startedAt = Date.now();
  const abortController = new AbortController();
  let response: Response;
  try {
    response = await fetch(
      `https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(consumed.policy.voiceId)}?output_format=${encodeURIComponent(consumed.policy.outputFormat)}`,
      {
        method: "POST",
        headers: {
          accept: "audio/mpeg",
          "content-type": "application/json",
          "xi-api-key": env.ELEVENLABS_API_KEY,
        },
        body: JSON.stringify({
          text: tts.text,
          model_id: consumed.policy.model,
          voice_settings: {
            stability: consumed.policy.stability,
            similarity_boost: consumed.policy.similarityBoost,
          },
        }),
        signal: abortController.signal,
      },
    );
  } catch {
    return completeProviderFailure({
      env,
      ctx,
      consumed,
      workerRequestId,
      startedAt,
      status: 500,
      errorCode: "PROVIDER_FETCH_ERROR",
    });
  }
  if (!response.ok) {
    await response.body?.cancel();
    return completeProviderFailure({
      env,
      ctx,
      consumed,
      workerRequestId,
      startedAt,
      status: response.status,
      errorCode: "PROVIDER_HTTP_ERROR",
    });
  }
  return streamedProviderResponse({
    response,
    abortController,
    env,
    ctx,
    consumptionId: consumed.consumptionId,
    workerRequestId,
    startedAt,
    fallbackContentType: "audio/mpeg",
  });
}

export async function handleOnboardingTranscribe(
  request: Request,
  env: OnboardingEnvironment,
  ctx: ExecutionContext,
): Promise<Response> {
  if (ticketFromAuthorization(request) === null) {
    return jsonError(401, "authentication_required");
  }
  const body = await readBoundedBody(request, 0);
  if (body === null || body.byteLength !== 0) {
    return jsonError(400, "invalid_request");
  }
  const workerRequestId = crypto.randomUUID();
  const consumed = await consumeTicket({
    request,
    env,
    scope: "onboarding_transcribe",
    body,
    workerRequestId,
  });
  if (
    consumed === null ||
    consumed.policy.kind !== "onboarding_transcribe"
  ) {
    return jsonError(403, "request_denied");
  }
  const startedAt = Date.now();
  const tokenUrl = new URL("https://streaming.assemblyai.com/v3/token");
  tokenUrl.searchParams.set(
    "expires_in_seconds",
    String(consumed.policy.redemptionWindowSeconds),
  );
  tokenUrl.searchParams.set(
    "max_session_duration_seconds",
    String(consumed.policy.maximumSessionSeconds),
  );
  const abortController = new AbortController();
  let response: Response;
  try {
    response = await fetch(tokenUrl, {
      method: "GET",
      headers: { authorization: env.ASSEMBLYAI_API_KEY },
      signal: abortController.signal,
    });
  } catch {
    return completeProviderFailure({
      env,
      ctx,
      consumed,
      workerRequestId,
      startedAt,
      status: 500,
      errorCode: "PROVIDER_FETCH_ERROR",
    });
  }
  if (!response.ok) {
    await response.body?.cancel();
    return completeProviderFailure({
      env,
      ctx,
      consumed,
      workerRequestId,
      startedAt,
      status: response.status,
      errorCode: "PROVIDER_HTTP_ERROR",
    });
  }
  return streamedProviderResponse({
    response,
    abortController,
    env,
    ctx,
    consumptionId: consumed.consumptionId,
    workerRequestId,
    startedAt,
    fallbackContentType: "application/json",
  });
}
