# Sticky Cloudflare Worker

PR 4A's Convex ticket control plane is already merged. This directory and the
two authenticated Convex HTTP handlers are PR 4B. The future PR 4C will add
Swift ticket issuance, exact-body hashing, and native route integration. PR 4B
does not modify the native app, and the complete PR 4 outcome remains
incomplete until PR 4C lands.

The default `clicky-proxy` configuration preserves the legacy `/chat`, `/tts`,
and `/transcribe-token` routes. The named `sticky-onboarding-dev` environment
closes those routes and exposes only:

- `POST /v1/onboarding/chat`
- `POST /v1/onboarding/tts`
- `POST /v1/onboarding/transcribe-token`

Onboarding calls require `Authorization: StickyTicket <opaque>`. The Worker
hashes the opaque ticket and exact raw request body, then consumes the
single-use binding through Convex before any provider request. Provider policy
comes only from the consumed ticket. Chat SSE and TTS audio remain streamed,
and completion metadata is sanitized and reported after success, provider
failure, or client disconnect.

Completion delivery uses at most three attempts with short backoff. Network
errors, `408`, `425`, `429`, and `5xx` responses are retried because they may
be transient; other `4xx` denials are terminal. Retries preserve the exact
completion body for Convex idempotency and generate a fresh signed HMAC
service-request ID for each HTTP attempt. Provider requests are never repeated
by completion retry.

## Local validation

Use Node.js 22 or newer and an environment-specific ignored
`.dev.vars.sticky-onboarding-dev` containing:

```text
ANTHROPIC_API_KEY
ASSEMBLYAI_API_KEY
ELEVENLABS_API_KEY
WORKER_HMAC_CURRENT_KEY_ID
WORKER_HMAC_CURRENT_KEY
```

The HMAC key must contain at least 32 random bytes. Its ID is a non-secret
rotation label. The matching current pair must be configured in the intended
Convex development deployment. Never commit `.dev.vars*`, print secret values,
or reuse a bare static authorization header between the Worker and Convex.

```bash
npm ci
npm test
npm run typecheck
npm run types:check
npm run check:startup
npm run dry-run:development
```

All development and test commands explicitly select
`sticky-onboarding-dev`. The dry run validates a bundle but does not deploy it.

## Human secret and deployment steps

1. Generate a fresh HMAC key with at least 32 random bytes and a unique key ID.
2. Set `WORKER_HMAC_CURRENT_KEY_ID` and `WORKER_HMAC_CURRENT_KEY` on the
   intended Convex development deployment.
3. Set the same pair, plus the three provider API keys, on the
   `sticky-onboarding-dev` Worker environment using interactive
   `wrangler secret put --env sticky-onboarding-dev`.
4. Confirm `CONVEX_SITE_URL` in `wrangler.jsonc` points to the intended
   development deployment.
5. Run the validation commands above.
6. Deploy only with explicit human authorization:
   `wrangler deploy --env sticky-onboarding-dev`.

For rotation, configure the old current pair as
`WORKER_HMAC_PREVIOUS_KEY_ID` and `WORKER_HMAC_PREVIOUS_KEY` in Convex before
changing the current pair on both sides. Remove the previous pair after old
Worker instances and in-flight requests have expired. The Worker signs only
with its current key; Convex accepts current and previous keys during overlap.

Do not deploy the default `clicky-proxy` configuration as part of onboarding
testing.
