import {
  createExecutionContext,
  waitOnExecutionContext,
} from "cloudflare:test";
import { afterEach, describe, expect, test, vi } from "vitest";

import worker from "../src/index";

const ticket = "A".repeat(43);
const authorization = `StickyTicket ${ticket}`;
const testEnv: Env = {
  CONVEX_SITE_URL: "https://kindred-ostrich-447.convex.site",
  ELEVENLABS_VOICE_ID: "kPzsL2i3teMYv0FxEYQ6",
  ONBOARDING_ROUTES_ENABLED: "true",
  ANTHROPIC_API_KEY: "anthropic-secret",
  ASSEMBLYAI_API_KEY: "assembly-secret",
  ELEVENLABS_API_KEY: "eleven-secret",
  WORKER_HMAC_CURRENT_KEY_ID: "development-2026-07",
  WORKER_HMAC_CURRENT_KEY: "h".repeat(32),
};

function chatRequest(body: string, authorizationValue = authorization) {
  return new Request("https://worker.test/v1/onboarding/chat", {
    method: "POST",
    headers: {
      authorization: authorizationValue,
      "content-type": "application/json",
    },
    body,
  });
}

function consumedPolicy(
  policy:
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
      },
) {
  return Response.json({
    consumptionId: "consumption_1234",
    policyVersion: 1,
    policy,
  });
}

async function runChatWithCompletionAttempts(
  completionAttempts: readonly ("network_error" | number)[],
) {
  const requests: Request[] = [];
  let providerCallCount = 0;
  let completionAttemptIndex = 0;
  const fetchMock = vi.fn(
    async (input: RequestInfo | URL, init?: RequestInit) => {
      const request = new Request(input, init);
      requests.push(request.clone());
      const url = new URL(request.url);
      if (url.pathname.endsWith("/consume")) {
        return consumedPolicy({
          kind: "onboarding_chat",
          model: "trusted-model",
          systemPrompt: "trusted-system",
          maximumOutputTokens: 128,
        });
      }
      if (url.hostname === "api.anthropic.com") {
        providerCallCount += 1;
        return new Response("data: complete\n\n", {
          headers: { "content-type": "text/event-stream" },
        });
      }
      if (url.pathname.endsWith("/complete")) {
        const attempt =
          completionAttempts[completionAttemptIndex] ?? 200;
        completionAttemptIndex += 1;
        if (attempt === "network_error") {
          throw new TypeError("Simulated completion network failure");
        }
        return Response.json(
          attempt >= 200 && attempt <= 299
            ? { ok: true }
            : { error: "request_denied" },
          { status: attempt },
        );
      }
      throw new Error(`Unexpected fetch target: ${url.origin}`);
    },
  );
  vi.stubGlobal("fetch", fetchMock);
  const ctx = createExecutionContext();
  const response = await worker.fetch(
    chatRequest('{"text":"hello","clientTurnId":"turn-retry"}'),
    testEnv,
    ctx,
  );
  await response.text();
  await waitOnExecutionContext(ctx);
  return {
    completionRequests: requests.filter((request) =>
      new URL(request.url).pathname.endsWith("/complete"),
    ),
    providerCallCount,
  };
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("onboarding route authorization and validation", () => {
  test("rejects missing and malformed ticket authorization without upstream calls", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    for (const authorizationValue of [
      undefined,
      "Bearer token",
      "StickyTicket short",
      `stickyticket ${ticket}`,
      `StickyTicket ${ticket} extra`,
    ]) {
      const headers = new Headers({ "content-type": "application/json" });
      if (authorizationValue !== undefined) {
        headers.set("authorization", authorizationValue);
      }
      const response = await worker.fetch(
        new Request("https://worker.test/v1/onboarding/chat", {
          method: "POST",
          headers,
          body: '{"text":"hello","clientTurnId":"turn-1"}',
        }),
        testEnv,
        createExecutionContext(),
      );
      expect(response.status).toBe(401);
    }
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("rejects unknown keys, invalid UTF-8, and oversized bodies before consume", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    const invalidBodies: BodyInit[] = [
      '{"text":"hello","clientTurnId":"turn-1","model":"client-model"}',
      '{"text":"","clientTurnId":"turn-1"}',
      '{"text":"hello","clientTurnId":"bad id"}',
      new Uint8Array([0xff, 0xfe]),
      JSON.stringify({
        text: "x".repeat(2_250),
        clientTurnId: "turn-1",
      }),
    ];
    for (const body of invalidBodies) {
      const response = await worker.fetch(
        new Request("https://worker.test/v1/onboarding/chat", {
          method: "POST",
          headers: {
            authorization,
            "content-type": "application/json",
          },
          body,
        }),
        testEnv,
        createExecutionContext(),
      );
      expect(response.status).toBe(400);
    }
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("returns a generic denial when consume rejects replay", async () => {
    const fetchMock = vi.fn(async () =>
      Response.json({ error: "request_denied" }, { status: 403 }),
    );
    vi.stubGlobal("fetch", fetchMock);
    const response = await worker.fetch(
      chatRequest('{"text":"hello","clientTurnId":"turn-1"}'),
      testEnv,
      createExecutionContext(),
    );
    expect(response.status).toBe(403);
    await expect(response.json()).resolves.toEqual({
      error: "request_denied",
    });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  test("requires an exactly empty transcription body", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    const response = await worker.fetch(
      new Request(
        "https://worker.test/v1/onboarding/transcribe-token",
        {
          method: "POST",
          headers: { authorization },
          body: " ",
        },
      ),
      testEnv,
      createExecutionContext(),
    );
    expect(response.status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe("onboarding provider requests and streaming", () => {
  test("uses only trusted chat policy and reports completion after SSE streaming", async () => {
    const requests: Request[] = [];
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const request = new Request(input, init);
      requests.push(request.clone());
      const url = new URL(request.url);
      if (url.pathname.endsWith("/consume")) {
        return consumedPolicy({
          kind: "onboarding_chat",
          model: "trusted-model",
          systemPrompt: "trusted-system",
          maximumOutputTokens: 321,
        });
      }
      if (url.hostname === "api.anthropic.com") {
        return new Response(
          new ReadableStream({
            start(controller) {
              controller.enqueue(
                new TextEncoder().encode("event: message_start\n\n"),
              );
              controller.enqueue(
                new TextEncoder().encode("data: trusted-stream\n\n"),
              );
              controller.close();
            },
          }),
          {
            headers: {
              "content-type": "text/event-stream",
              "request-id": "anthropic-request-1",
            },
          },
        );
      }
      if (url.pathname.endsWith("/complete")) {
        return Response.json({ ok: true });
      }
      throw new Error(`Unexpected fetch target: ${url.origin}`);
    });
    vi.stubGlobal("fetch", fetchMock);
    const ctx = createExecutionContext();
    const response = await worker.fetch(
      chatRequest('{"text":"user text","clientTurnId":"turn-1"}'),
      testEnv,
      ctx,
    );
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("text/event-stream");
    await expect(response.text()).resolves.toContain("trusted-stream");
    await waitOnExecutionContext(ctx);
    expect(new URL(requests[0].url).pathname).toBe(
      "/internal/worker/request-tickets/consume",
    );
    expect(new URL(requests[1].url).hostname).toBe("api.anthropic.com");
    expect(new URL(requests[2].url).pathname).toBe(
      "/internal/worker/request-tickets/complete",
    );

    const providerRequest = requests.find(
      (request) => new URL(request.url).hostname === "api.anthropic.com",
    );
    expect(providerRequest).toBeDefined();
    const providerBody = (await providerRequest?.json()) as Record<
      string,
      unknown
    >;
    expect(providerBody).toMatchObject({
      model: "trusted-model",
      system: "trusted-system",
      max_tokens: 321,
      stream: true,
      messages: [
        {
          role: "user",
          content: [{ type: "text", text: "user text" }],
        },
      ],
    });
    expect(JSON.stringify(providerBody)).not.toContain("clientTurnId");

    const consumeRequest = requests.find((request) =>
      new URL(request.url).pathname.endsWith("/consume"),
    );
    const consumeBody = (await consumeRequest?.json()) as Record<
      string,
      unknown
    >;
    expect(consumeBody.ticketDigest).toMatch(/^[0-9a-f]{64}$/);
    expect(consumeBody).not.toHaveProperty("ticket");
    expect(consumeRequest?.headers.get("x-sticky-signature")).toMatch(
      /^[0-9a-f]{64}$/,
    );

    const completionRequest = requests.find((request) =>
      new URL(request.url).pathname.endsWith("/complete"),
    );
    expect(completionRequest).toBeDefined();
    await expect(completionRequest?.json()).resolves.toMatchObject({
      consumptionId: "consumption_1234",
      completion: {
        outcome: "succeeded",
        providerRequestId: "anthropic-request-1",
        httpStatusClass: 2,
        usage: {},
      },
    });
  });

  test("streams trusted-policy TTS audio and reports completion", async () => {
    const requests: Request[] = [];
    const audioBytes = new Uint8Array([1, 2, 3, 4]);
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
        const request = new Request(input, init);
        requests.push(request.clone());
        const url = new URL(request.url);
        if (url.pathname.endsWith("/consume")) {
          return consumedPolicy({
            kind: "onboarding_tts",
            voiceId: "trusted-voice",
            model: "trusted-tts-model",
            outputFormat: "mp3_44100_128",
            stability: 0.2,
            similarityBoost: 0.9,
          });
        }
        if (url.hostname === "api.elevenlabs.io") {
          return new Response(audioBytes, {
            headers: { "content-type": "audio/mpeg" },
          });
        }
        return Response.json({ ok: true });
      }),
    );
    const ctx = createExecutionContext();
    const response = await worker.fetch(
      new Request("https://worker.test/v1/onboarding/tts", {
        method: "POST",
        headers: {
          authorization,
          "content-type": "application/json",
        },
        body: '{"text":"speak this"}',
      }),
      testEnv,
      ctx,
    );
    expect(new Uint8Array(await response.arrayBuffer())).toEqual(audioBytes);
    await waitOnExecutionContext(ctx);
    const providerRequest = requests.find(
      (request) => new URL(request.url).hostname === "api.elevenlabs.io",
    );
    expect(providerRequest?.url).toContain("/trusted-voice");
    await expect(providerRequest?.json()).resolves.toMatchObject({
      text: "speak this",
      model_id: "trusted-tts-model",
      voice_settings: {
        stability: 0.2,
        similarity_boost: 0.9,
      },
    });
    expect(
      requests.some((request) =>
        new URL(request.url).pathname.endsWith("/complete"),
      ),
    ).toBe(true);
  });

  test("reports client cancellation and cancels the provider stream", async () => {
    const requests: Request[] = [];
    let providerWasCancelled = false;
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
        const request = new Request(input, init);
        requests.push(request.clone());
        const url = new URL(request.url);
        if (url.pathname.endsWith("/consume")) {
          return consumedPolicy({
            kind: "onboarding_chat",
            model: "trusted-model",
            systemPrompt: "trusted-system",
            maximumOutputTokens: 128,
          });
        }
        if (url.hostname === "api.anthropic.com") {
          return new Response(
            new ReadableStream({
              pull(controller) {
                controller.enqueue(new TextEncoder().encode("data: chunk\n\n"));
              },
              cancel() {
                providerWasCancelled = true;
              },
            }),
            { headers: { "content-type": "text/event-stream" } },
          );
        }
        return Response.json({ ok: true });
      }),
    );
    const ctx = createExecutionContext();
    const response = await worker.fetch(
      chatRequest('{"text":"hello","clientTurnId":"turn-1"}'),
      testEnv,
      ctx,
    );
    await response.body?.cancel();
    await waitOnExecutionContext(ctx);
    expect(providerWasCancelled).toBe(true);
    const completionRequest = requests.find((request) =>
      new URL(request.url).pathname.endsWith("/complete"),
    );
    await expect(completionRequest?.json()).resolves.toMatchObject({
      completion: { outcome: "client_disconnected" },
    });
  });

  test("uses trusted transcription windows", async () => {
    const requests: Request[] = [];
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
        const request = new Request(input, init);
        requests.push(request.clone());
        const url = new URL(request.url);
        if (url.pathname.endsWith("/consume")) {
          return consumedPolicy({
            kind: "onboarding_transcribe",
            redemptionWindowSeconds: 30,
            maximumSessionSeconds: 900,
          });
        }
        if (url.hostname === "streaming.assemblyai.com") {
          return Response.json({ token: "temporary" });
        }
        return Response.json({ ok: true });
      }),
    );
    const ctx = createExecutionContext();
    const response = await worker.fetch(
      new Request(
        "https://worker.test/v1/onboarding/transcribe-token",
        {
          method: "POST",
          headers: { authorization },
        },
      ),
      testEnv,
      ctx,
    );
    await expect(response.json()).resolves.toEqual({ token: "temporary" });
    await waitOnExecutionContext(ctx);
    const providerRequest = requests.find(
      (request) =>
        new URL(request.url).hostname === "streaming.assemblyai.com",
    );
    const providerUrl = new URL(providerRequest?.url ?? "");
    expect(providerUrl.searchParams.get("expires_in_seconds")).toBe("30");
    expect(
      providerUrl.searchParams.get("max_session_duration_seconds"),
    ).toBe("900");
  });
});

describe("completion reporting retries", () => {
  test("retries a network failure with stable body and no duplicate provider call", async () => {
    const result = await runChatWithCompletionAttempts([
      "network_error",
      200,
    ]);
    expect(result.providerCallCount).toBe(1);
    expect(result.completionRequests).toHaveLength(2);
    const completionBodies = await Promise.all(
      result.completionRequests.map(
        async (request) => await request.clone().text(),
      ),
    );
    expect(completionBodies[1]).toBe(completionBodies[0]);
    const serviceRequestIds = result.completionRequests.map((request) =>
      request.headers.get("x-sticky-request-id"),
    );
    expect(new Set(serviceRequestIds).size).toBe(2);
    const signatures = result.completionRequests.map((request) =>
      request.headers.get("x-sticky-signature"),
    );
    expect(new Set(signatures).size).toBe(2);
  });

  test("bounds repeated network failures to three attempts", async () => {
    const result = await runChatWithCompletionAttempts([
      "network_error",
      "network_error",
      "network_error",
      200,
    ]);
    expect(result.providerCallCount).toBe(1);
    expect(result.completionRequests).toHaveLength(3);
  });

  test("retries a transient Convex response and then succeeds", async () => {
    const result = await runChatWithCompletionAttempts([503, 200]);
    expect(result.providerCallCount).toBe(1);
    expect(result.completionRequests).toHaveLength(2);
  });

  test("does not retry a terminal Convex request denial", async () => {
    const result = await runChatWithCompletionAttempts([403, 200]);
    expect(result.providerCallCount).toBe(1);
    expect(result.completionRequests).toHaveLength(1);
  });
});

describe("legacy deployment behavior", () => {
  test("keeps the legacy chat route and closes onboarding routes", async () => {
    const legacyEnv = {
      ...testEnv,
      ONBOARDING_ROUTES_ENABLED: "false" as const,
    };
    const originalBody = '{"model":"legacy-model","stream":true}';
    const fetchMock = vi.fn(
      async (_input: RequestInfo | URL, _init?: RequestInit) =>
        new Response("legacy-stream", {
          headers: { "content-type": "text/event-stream" },
        }),
    );
    vi.stubGlobal("fetch", fetchMock);
    const legacyResponse = await worker.fetch(
      new Request("https://worker.test/chat", {
        method: "POST",
        body: originalBody,
      }),
      legacyEnv,
      createExecutionContext(),
    );
    expect(legacyResponse.status).toBe(200);
    await expect(legacyResponse.text()).resolves.toBe("legacy-stream");
    const forwardedRequest = fetchMock.mock.calls[0]?.[1] as
      | RequestInit
      | undefined;
    expect(forwardedRequest?.body).toBe(originalBody);

    const onboardingResponse = await worker.fetch(
      chatRequest('{"text":"hello","clientTurnId":"turn-1"}'),
      legacyEnv,
      createExecutionContext(),
    );
    expect(onboardingResponse.status).toBe(404);
  });
});
