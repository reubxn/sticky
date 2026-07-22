import {
  handleOnboardingChat,
  handleOnboardingTranscribe,
  handleOnboardingTTS,
} from "./onboarding";

export type WorkerEnvironment = Omit<
  Env,
  "ONBOARDING_ROUTES_ENABLED"
> & {
  ONBOARDING_ROUTES_ENABLED: "true" | "false";
};

export default {
  async fetch(
    request: Request,
    env: WorkerEnvironment,
    ctx: ExecutionContext,
  ): Promise<Response> {
    const url = new URL(request.url);

    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    try {
      if (env.ONBOARDING_ROUTES_ENABLED === "true") {
        if (url.pathname === "/v1/onboarding/chat") {
          return await handleOnboardingChat(request, env, ctx);
        }
        if (url.pathname === "/v1/onboarding/tts") {
          return await handleOnboardingTTS(request, env, ctx);
        }
        if (url.pathname === "/v1/onboarding/transcribe-token") {
          return await handleOnboardingTranscribe(request, env, ctx);
        }
        return new Response("Not found", { status: 404 });
      }

      if (url.pathname === "/chat") {
        return await handleChat(request, env);
      }

      if (url.pathname === "/tts") {
        return await handleTTS(request, env);
      }

      if (url.pathname === "/transcribe-token") {
        return await handleTranscribeToken(env);
      }
    } catch (error) {
      console.error(
        JSON.stringify({
          event: "worker_request_failed",
          route: url.pathname,
          errorType:
            error instanceof Error ? error.name : "UnknownError",
        }),
      );
      return new Response(
        JSON.stringify({ error: "request_failed" }),
        { status: 500, headers: { "content-type": "application/json" } }
      );
    }

    return new Response("Not found", { status: 404 });
  },
};

async function handleChat(
  request: Request,
  env: WorkerEnvironment,
): Promise<Response> {
  const body = await request.text();

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body,
  });

  if (!response.ok) {
    const errorBody = await response.text();
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": response.headers.get("content-type") || "text/event-stream",
      "cache-control": "no-cache",
    },
  });
}

async function handleTranscribeToken(
  env: WorkerEnvironment,
): Promise<Response> {
  const response = await fetch(
    "https://streaming.assemblyai.com/v3/token?expires_in_seconds=480",
    {
      method: "GET",
      headers: {
        authorization: env.ASSEMBLYAI_API_KEY,
      },
    }
  );

  if (!response.ok) {
    const errorBody = await response.text();
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  const data = await response.text();
  return new Response(data, {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

async function handleTTS(
  request: Request,
  env: WorkerEnvironment,
): Promise<Response> {
  const body = await request.text();
  const voiceId = env.ELEVENLABS_VOICE_ID;

  const response = await fetch(
    `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`,
    {
      method: "POST",
      headers: {
        "xi-api-key": env.ELEVENLABS_API_KEY,
        "content-type": "application/json",
        accept: "audio/mpeg",
      },
      body,
    }
  );

  if (!response.ok) {
    const errorBody = await response.text();
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": response.headers.get("content-type") || "audio/mpeg",
    },
  });
}
