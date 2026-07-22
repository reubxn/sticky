# Convex backend

The root npm project owns Sticky's Convex schema, functions, generated types,
and backend tests. The native macOS app authenticates with Clerk and passes its
session token to Convex through `ClerkConvex`.

## Deployment safety

Before running any Convex CLI command or `convex:*` npm script, inspect
`CONVEX_DEPLOYMENT` in `.env.local` and confirm that its team, project, and
deployment are the intended target. Stop and ask if the target is unclear.

Plain `npx convex dev` and the root Convex scripts use the configured
`CONVEX_DEPLOYMENT`. That deployment may be cloud-hosted, and development,
codegen, run, environment, and deployment commands may read or mutate it.

For isolated local validation, explicitly force anonymous agent mode:

```bash
CONVEX_AGENT_MODE=anonymous npx convex dev --once
```

Never run `convex deploy` or `npm run convex:deploy` without explicit user
authorization for that production deployment operation.

## Local setup

Requirements: Node.js 20 or newer and access to the Sticky Convex project.

```bash
npm ci
npx convex login
npm run convex:dev:once
npm test
```

`convex:dev:once` pushes the schema and functions to the deployment selected by
`CONVEX_DEPLOYMENT`, validates the schema, typechecks functions, and refreshes
`convex/_generated`. Use `npm run convex:dev` for the long-running development
watcher. Verify a deployment with:

```bash
npx convex run health:check
```

Commit generated files after schema or function changes. Commit neither
`.env.local` nor deployment credentials.

## Deployments and secrets

Convex development and production deployments are separate. Confirm the
selected deployment before pushing code. Deploy production only from an
authenticated release environment:

```bash
npm run convex:deploy
```

Set backend secrets with `npx convex env set NAME value` against the intended
deployment. Store values in the team's secret manager and CI environment; do
not place them in source files, npm scripts, or committed env files.

## Clerk authentication

The development Clerk instance uses Google and email-link authentication.
`convex/auth.config.ts` reads `CLERK_JWT_ISSUER_DOMAIN` from the selected Convex
deployment and requires Clerk's `convex` JWT audience. For the linked
development instance, the exact issuer is:

```text
https://ruling-katydid-23.clerk.accounts.dev
```

In the Clerk Dashboard, activate the Convex integration before testing. Confirm
new development session JWTs contain `aud: convex` and the standard verified
`name`, `email`, and `picture` claims. Provisioning uses those non-empty claims
to refresh mutable profile fields and may repair only untouched generated
workspace and persona names. It never treats email as an identity key.

Changing Clerk session claims does not repair an already-issued token. Sign out
fully and sign in again, or otherwise force Clerk to issue and propagate a
refreshed session token, before validating claim changes in Convex.

Keep Clerk keys in ignored `.env.clerk.local` and Convex deployment values in
ignored `.env.local`. To copy only the public publishable key and deployment URL
into the app's existing Application Support `secrets.plist`, run:

```bash
python3 scripts/configure-auth-runtime.py
```

The script reads `CLERK_PUBLISHABLE_KEY` and `CONVEX_URL`, preserves unrelated
plist entries, uses an atomic mode-`0600` write, and never displays values.
`CLERK_SECRET_KEY` remains outside the app and is never copied.

The native callback is `com.reuban.sticky://callback`. Add that exact URL to
Clerk's native redirect allowlist. Associated domains are deferred until the
app has a paid Apple Developer account.

The development Clerk instance disables "Require the same device and browser"
for email links. Native Sticky starts the flow inside the app and the email
opens in an external browser, so Clerk otherwise rejects the callback as a
different browser client. This is a development-only compromise. Before
production, replace the custom-scheme flow with claimed HTTPS/Universal Links
and re-evaluate same-client protection against email-link interception.

After running the script, launch the signed app from Xcode and test both Google
and email-link sign-in. Verify the custom callback brings the dashboard forward
and the app reaches the authenticated "account connected" surface only after
Convex reports authentication. Personal workspace provisioning then runs
through `accounts:provisionCurrent`, but production data readiness intentionally
remains `awaitingWorkspaceProvisioning`: Ask, Teach, personas, floating chat,
Taste Library, and Dashboard Chat/Memory/Tastes/Team remain unavailable until
production-scoped storage and subscriptions exist.

The current Profile view mixes account fields with legacy TASTE export, and the
current Settings view controls disabled legacy companion features, so neither
is exposed in this slice. The account-connected surface shows verified Clerk
identity and sign-out without loading those views.

The local display-name, role, and profile-picture overrides are keyed by the
verified Clerk user ID. Existing taste, chat-history, and recording-history
stores remain unscoped local MVP data and are never exposed to authenticated
accounts in this slice. They must not be treated as account data and remain
temporary until their planned cloud replacement PRs.

Only exact `com.reuban.sticky://callback` URLs are accepted. Valid callbacks are
queued while Clerk loads, removed before handling, and retried a bounded number
of times without blocking later callbacks. Callback epochs are independent of
authenticated-user generations, so discovering a cached user or completing an
account switch does not cancel the callback producing that transition.

Normal Retry uses ClerkKit 1.3.2's public `refreshEnvironment()` and
`refreshClient()` APIs. ClerkKit 1.3.2 ignores a second `Clerk.configure` call,
so if Retry detects changed publishable-key or Convex URL values it shows a
restart-required failure and does not replace the active Convex client. Sign-out
has its own bounded retry state and completes only when the Convex auth
publisher reports unauthenticated; timeout is the operation failure path.

Production readiness is bound to the verified Clerk user ID, current auth
generation, and active workspace ID. Personal workspace provisioning does not
call `markCurrentAuthenticatedWorkspaceReady(workspaceID:)`; a later storage
slice may call it only after provisioning production-scoped storage for that
exact identity and workspace.

## Personal account provisioning

`accounts:provisionCurrent` accepts no identity or ownership arguments. It
derives the authenticated identity from Convex, keys the canonical profile only
by `identity.tokenIdentifier`, and transactionally creates or validates one
active personal workspace, owner membership, and persona. Valid partial prefixes
are repaired; deletion-pending accounts, duplicates, inactive records, extra
memberships or personas, and malformed relationships fail closed.

`accounts:current` returns either `needsProvisioning` for a valid missing or
partial prefix, or a validated ready snapshot. Both functions use bounded
indexed reads. Repeated provisioning preserves workspace and persona edits;
only present, non-empty verified profile claims may refresh mutable profile
fields. If a newly available verified name replaces a generic profile name,
provisioning updates the workspace only when its name still exactly matches the
old generated default, and updates the persona only while its name is unchanged
and setup remains `notStarted` at version `0`.

Manual Xcode validation must confirm Google and email-link sign-in, cold-launch
callbacks, unrelated URL rejection, restart-required after rewriting
`secrets.plist`, account switching, publisher-driven sign-out and retry, and
that every legacy product surface remains inaccessible after authentication.
Restart the app before validating newly written runtime values.

## Onboarding Worker request tickets

This work is intentionally split into three slices:

- **PR 4A (merged):** Convex ticket issuance, policy, atomic consumption,
  completion storage, quotas, retention, and cleanup.
- **PR 4B (current):** the HMAC-authenticated Convex service bridge and
  Cloudflare onboarding provider routes.
- **PR 4C (future):** Swift exact-body hashing, ticket issuance, and native
  onboarding route integration.

PR 4B does not modify Swift or claim native integration. The complete PR 4
outcome remains incomplete until PR 4C lands, and production readiness remains
locked.

`requestTickets:issueOnboarding` is the only public ticket function in PR 4A.
It authenticates through Convex, accepts only a persona ID, one of the three
onboarding scopes, the lowercase SHA-256 digest of the exact future Worker
request body, and that body's byte count. It generates 32 random bytes in the
action, returns the base64url bearer once, and persists only its digest through
an internal mutation. It never accepts a profile, workspace, membership, role,
model, system prompt, voice, output limit, or provider setting from a client.

Internal issuance and consumption revalidate the canonical active profile,
workspace, membership, persona ownership, and incomplete onboarding state.
Tickets are short-lived, single-use, scope- and body-bound, and subject to
bounded indexed outstanding, short-window, daily-request, and daily-payload
limits. Consumption returns versioned server policy for the provider request.
Consume and completion validate that the ticket's single audit row exactly
matches its denormalized actor, workspace, membership, persona, scope, policy
version, and issuance time before writing. A mismatch fails with
`DATA_INTEGRITY` and the transaction rolls back.

Three hourly cron triggers run separate bounded cleanup mutations. Issued
tickets remain until at least 24 hours after their short TTL expires, preserving
the full daily quota window with a conservative TTL margin. Consumed ticket
tombstones remain for at least 24 hours after consumption. Sanitized audits
remain for 30 days independently of ticket deletion. Each cleanup reads through
its exact retention index, deletes at most 50 rows, and schedules a zero-delay
continuation with the original cutoff only when a full batch was found. Audit
metadata contains no ticket plaintext or digest, prompt, answer, transcript,
TTS text or audio, raw IP, or user-agent.

The Worker service bridge exposes exactly two POST endpoints:

- `/internal/worker/request-tickets/consume`
- `/internal/worker/request-tickets/complete`

They accept digest-only ticket bindings and strict JSON DTOs. Every call is
authenticated with a timestamped HMAC-SHA256 signature over the canonical
method, path, timestamp, request ID, and SHA-256 digest of the raw body. The
timestamp window is 30 seconds, request IDs are cryptographically generated,
and signature verification uses Web Crypto's constant-time HMAC verification.
Convex accepts the configured current key and, during rotation, an optional
previous key. It returns generic authentication, validation, and authorization
errors without exposing ticket or tenant state.

Configure these Convex deployment variables through the team's secret manager:

```text
WORKER_HMAC_CURRENT_KEY_ID
WORKER_HMAC_CURRENT_KEY
WORKER_HMAC_PREVIOUS_KEY_ID      # optional during rotation
WORKER_HMAC_PREVIOUS_KEY         # optional during rotation
```

Use at least 32 random bytes for each HMAC key. Rotate by first moving the old
current pair to the previous pair in Convex, then setting a fresh current pair
in Convex and the `sticky-onboarding-dev` Worker. After all old Worker
instances and in-flight requests have expired, remove the previous pair.
Never expose these endpoints through a public Convex function, accept a Clerk
token as Worker service authentication, or send the opaque ticket to Convex.

Completion reporting retries network failures and only transient HTTP statuses
(`408`, `425`, `429`, and `5xx`) up to three total attempts with short backoff.
All other `4xx` responses are terminal request denials. Every retry preserves
the original consumption ID, Worker request ID, and completion DTO for Convex
idempotency while signing the HTTP attempt with a fresh service-request ID.

Worker and Convex tests consume one shared deterministic canonical HMAC vector
covering the exact body bytes, digest, canonical request, key ID, key, and
signature. `convex-test` exercises exact HTTP route/method closure and strict
malformed-request responses, but it cannot inject Convex deployment environment
variables into an HTTP action runtime. The shared vector therefore tests the
real Worker signer directly against the real Convex verifier, including
mutated-body rejection, without introducing a test-only environment bypass.
