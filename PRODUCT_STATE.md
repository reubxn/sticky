# PRODUCT_STATE.md

Last updated: 2026-05-02

## Product

Sphere OS: Inspectable Taste Infrastructure.

The product captures how a tasteful designer makes decisions and turns those decisions into a local weighted object graph. A Sphere is an association bundle over WeightedObjects: it records which objects were overweighted, underweighted, rejected, combined, or newly invented in a design decision.

## Design Decision Package Contract

Every captured design decision must become a Design Decision Package. A package is the inspectable unit of product memory that links raw evidence to the resulting Sphere graph.

Required package contents:

- Conversation transcript: the exact voice/manual transcript that explains the decision, including follow-up answers when present.
- Screenshot evidence: the relevant screen/image evidence for the decision. If storage later deduplicates or externalizes images, the package must keep a durable local reference, checksum, thumbnail, dimensions, and capture timestamp rather than dropping the evidence.
- Source context: capture kind, trigger, page title, URL/domain when available, selected/nearby text, element metadata, surface, intent, audience, and constraints.
- Resulting Sphere: the draft or approved Sphere created from the decision, with central decision, rationale, confidence, provenance, and association IDs.
- WeightedObjects: all objects created or linked by the decision, including overweighted, underweighted, rejected, combined, and invented roles.
- Approval status: package-level lifecycle state and the lifecycle state of the resulting Sphere and WeightedObjects. Draft inferred taste must never appear as approved truth.

This contract applies to observation captures, manual evidence captures, screenshot captures, deployment guidance decisions, and accepted/rejected recommendation feedback. Future storage/API/UI work should treat a decision package as incomplete if transcript, screenshot evidence status, source context, Sphere, WeightedObjects, or approval status is missing.

## Launch Promise

The first screen must communicate the outcome before it explains the machinery:

Capture the best designer's taste, turn it into approved inspectable Spheres, and deploy that taste across the company so non-taste users can make better design decisions.

This promise must be visible immediately in the first viewport of the local Taste Engine launch/demo experience. It should not be buried in architecture terms, generic dashboard labels, or abstract graph language. Spheres and WeightedObjects are the infrastructure behind the promise, not the first thing a new buyer or teammate should have to decode.

## Launch Promise Gap #1

Status: fixed in the local Taste Engine UI on 2026-05-02.

The first screen now leads with:

Capture your best designer's taste. Let the whole company design with it.

The first viewport also shows the Observe -> Approve -> Guide loop, approved/draft/rejected counts, provenance, and a prefilled deployment prompt. The Guide flow can return a concrete recommendation that overweights, underweights, and rejects named objects with approved source counts.

Non-negotiable first-screen behavior:

- Lead with the outcome: capture the best designer's taste and deploy it across the company.
- Show the two modes as the core loop: Observe taste owner decisions, then Deploy approved taste guidance.
- Make approval status and provenance visible from the start so inferred draft taste is never presented as truth.
- Keep the interface calm and operational; avoid generic SaaS dashboard copy or decorative marketing sections.

## Current Architecture

- Root macOS app: `leanring-buddy/`
  - Menu-bar-only SwiftUI/AppKit app.
  - Existing Claude assistant mode remains the default path.
  - `SphereMode.assistant`, `SphereMode.observation`, and `SphereMode.deployment` are present.
  - Observation and deployment modes call a local Taste Engine at `TasteEngineBaseURL`, defaulting to `http://localhost:3000`.
  - Taste modes render the overlay cursor as a soft sphere while preserving the existing waveform, spinner, TTS, and pointing behavior.
- Cloudflare Worker proxy: `worker/`
  - Still owns Anthropic, AssemblyAI, and ElevenLabs secrets for assistant mode.
  - `POST /tts` can now use ElevenLabs or OpenAI speech (`TTS_PROVIDER=openai`) so local Worker dev can bypass ElevenLabs account/proxy issues.
  - Exposes a configured-but-optional `POST /image` route for sphere visual generation through an image provider secret (`OPENAI_API_KEY`, optional `IMAGE_MODEL`). If the secret is missing, the route returns a clear not-configured response instead of failing silently.
- Local Taste Engine service: `taste-fingerprint-studio/`
  - Next.js app with a sphere-focused API and graph UI.
  - JSON persistence lives under `taste-fingerprint-studio/data/`.
  - Design Decision Packages now persist in `data/decision-packages.json` as the durable evidence-to-graph record for capture ingestion.
  - Local orchestration now exists for capture ingestion: the transcript-to-decision summarizer calls Claude through the Worker proxy, while campaign-compression image generation uses one canonical fixed prompt plus the source screenshot. The prompt can be sent to local OpenAI image generation or a Worker image route through `lib/orchestration/image-client.ts`.
  - Taste profile payloads now affect recommendation ranking: creator/collaborator metadata persists on objects, Spheres, captures, packages, and guidance decisions; recommendation requests can carry `taste_profile_selection`, `fusion_mode`, `deployment_intent`, and `recommendation_lens`; recommendation responses echo normalized `taste_fusion` metadata with truthful `applied_to_ranking`.
  - Design Decision Packages now include a generated `summary_markdown` view linked to the resulting Sphere. Capture and orchestrated ingest persist that markdown back onto newly created Spheres so the UI and recommendation citations can verify the summary link without changing ranking behavior.
  - Existing fingerprint code remains available as ingestion support, but the product model is now WeightedObjects and Spheres.

## Implemented Local Taste Engine Routes

- `POST /api/palette/ingest`
  - Creates draft or approved WeightedObjects from manual/text/screenshot-shaped payloads.
- `GET /api/palette/graph`
  - Returns `weighted_objects`, `spheres`, persisted capture records, and persisted Design Decision Packages.
- `GET /api/captures`
  - Lists persisted raw capture records for local inspection/debugging.
- `POST /api/captures/ingest`
  - Capture ingestion agent endpoint.
  - Accepts raw page, element, selection, screenshot, voice, or manual captures.
  - Translates each capture into draft WeightedObjects, a draft Sphere, associations, a capture record, and a follow-up question.
  - Creates a Design Decision Package with sanitized raw capture, transcript/conversation turns, screenshot metadata, linked WeightedObjects, linked Sphere, associations, package status, and provenance.
  - macOS Observation Mode now posts push-to-talk voice captures here with the current transcript, conversation transcript text, cursor-screen screenshot data URL, and screenshot metadata.
  - Accepts optional creator/collaborator profile IDs and preserves them on the capture record, draft WeightedObjects, draft Sphere, and Design Decision Package.
  - Supports `dry_run` for safe smoke checks without mutating local taste memory.
- `POST /api/captures/ingest/orchestrated`
  - Local orchestrator endpoint that wraps capture ingestion in a multi-agent Claude audit pass.
  - Uses one transcript-to-decision summarizer agent, then applies the canonical Campaign Compression Sphere image prompt without a second prompt-writing agent.
  - Attempts sphere image generation when a sphere prompt is available and returns image-generation configured/error status in `orchestration.campaign_compression_sphere`.
  - Returns `orchestration.agent_audits` alongside normal capture-ingest output and supports `dry_run`.
- `GET /api/decision-packages`
  - Lists persisted Design Decision Packages for audit/debugging.
- `POST /api/decision-packages`
  - Creates a standalone Design Decision Package when a caller already has graph links and evidence metadata.
- `POST /api/spheres/observe`
  - Saves observation sessions and creates/updates draft Spheres from observed associations.
- `POST /api/spheres/recommend`
  - Ranks Spheres from approved WeightedObjects and design context.
  - Can return draft inferred Spheres, but draft weighted objects are not used as deployable signal.
  - Accepts taste profile selection/fusion and `recommendation_lens` payloads, boosts matching creator/collaborator evidence and lens tags, returns compact Clicky guidance, and still falls back instead of hard-filtering when persona evidence is sparse.
- `POST /api/spheres/decision`
  - Persists accepted/rejected guidance decisions.
- `POST /api/spheres/promote`
  - Promotes draft WeightedObjects or Spheres to approved.

## Implemented UI

- `taste-fingerprint-studio/components/sphere/SphereApp.tsx`
  - Minimal dark Sphere Library with grid cards, central visual anchors, decision summaries, semantic orbit tokens, lifecycle status, confidence, and a focused decision trace panel.
  - Legacy graph view, floating workflow form, and question-centric controls have been removed from the rendered component rather than hidden behind dead branches.
  - Seed spheres use `public/examples/spheres/textile-compression-sphere.png` and `public/examples/spheres/campaign-compression-sphere.png` as premium visual anchors.
  - Existing Sphere cards and the decision trace panel show founder/profile attribution as small orb avatars. Missing creator metadata is shown explicitly as uncaptured rather than silently hidden. The old all/draft/rejected count tiles and boxed trace-choice tiles have been removed.
  - Semantic WeightedObjects now render as small role-colored orbit spheres around the central Sphere instead of pill badges over the image.
  - The library header no longer uses explanatory dashboard copy or a blue refresh/check button. The sticky top `Summary` control opens a full top-right decision-summary panel for the currently selected Sphere.
  - The selected trace opens the linked summary as an ambient evidence panel rather than a generic action button.

## Verified

- `npm run lint` passes in `taste-fingerprint-studio`.
- `npm run build` passes in `taste-fingerprint-studio`.
- `swiftc -parse leanring-buddy/*.swift` passes.
- `plutil -lint leanring-buddy/Info.plist` passes.
- Local API smoke checks for graph and recommendations pass when the dev server is running.
- `http://localhost:3000/api/palette/graph` responds from the currently running local Taste Engine process.
- `/api/captures/ingest` dry-run smoke check returns a draft `capture_ingestion` Sphere, draft WeightedObjects, associations, and a follow-up question without persisting test data.
- `npm run lint -- --max-warnings=0` and `npm run build` pass after adding Design Decision Package persistence and `/api/decision-packages`.
- `npm run lint -- --max-warnings=0` and `npm run build` pass after adding `/api/captures/ingest/orchestrated` and local Claude orchestration helpers.
- `npm run lint -- --max-warnings=0` and `npm run build` pass after removing the legacy graph/workflow UI and adding the Worker `/image` route plus Taste Engine image client.
- `npm run lint -- --max-warnings=0` and `npx tsc --noEmit` pass after replacing the summary agent prompt and wiring valid Claude `decision_summary` output back into the package. `npm run build` was retried but blocked by Google font fetch failures in `next/font`, not by TypeScript errors.
- A direct orchestrator dry-run with the provided campaign screenshot and the deployed Claude Worker succeeded: the Claude summary agent returned `ok`, screenshot evidence was attached, and the deterministic campaign-compression prompt was routed with `source_image_attached: true`.
- `npm run lint -- --max-warnings=0`, `npx tsc --noEmit`, `swiftc -parse leanring-buddy/ElevenLabsTTSClient.swift leanring-buddy/AppBundleConfiguration.swift`, and `wrangler deploy --dry-run` pass after adding deterministic image prompting plus local TTS/image fallbacks.
- `/api/captures/ingest` dry-run still returns a Design Decision Package and decision summary after the cleanup.
- `/api/captures/ingest/orchestrated` dry-run degrades cleanly when `CLAUDE_WORKER_BASE_URL` is not configured, returning agent error statuses and the heuristic fallback summary instead of crashing.
- `wrangler deploy --dry-run` compiles the Worker after adding `/image`; the npm wrapper was manually stopped after Wrangler printed `--dry-run: exiting now`.
- A `tsx` package-builder smoke check verifies transcript retention, screenshot data URL omission, and screenshot metadata hash/byte/dimension capture.
- `npm run lint -- --max-warnings=0`, `npx tsc --noEmit`, `swiftc -parse leanring-buddy/TasteEngineModels.swift leanring-buddy/TasteEngineAPIClient.swift`, and `swiftc -typecheck leanring-buddy/TasteEngineModels.swift leanring-buddy/TasteEngineAPIClient.swift` pass after adding the taste profile payload contract.
- Direct route smoke checks against `/api/spheres/recommend` verify request-supplied profile selections echo as `taste_fusion.source = "request_payload"` with `applied_to_ranking: false`, and absent selections default to `company` + `single_profile`.
- A `/api/captures/ingest` dry-run smoke check verifies `creator_profile_id` is returned on the capture record, generated Sphere, and Design Decision Package without persisting test data.
- `npm run lint -- --max-warnings=0`, `npx tsc --noEmit`, and a `/api/captures/ingest` dry-run smoke check pass after adding founder mini-spheres, removing the count/trace tiles, linking package `summary_markdown` back to generated Spheres, and tightening the summary-agent decision/reusable-rule format.
- A graph smoke check verifies all current seed Spheres return `creator_profile_id: "founder"`, precise `decision_summary.reusable_rule`, and `summary_markdown`.
- JSON validation, `npm run lint -- --max-warnings=0`, `npx tsc --noEmit`, and a live graph smoke check pass after seeding 12 approved WeightedObjects and 5-6 role-explicit associations per Sphere. The graph no longer returns the generic "When this context appears again" fallback rules.
- `npm run lint -- --max-warnings=0` and `npx tsc --noEmit` pass after removing the sticky blue refresh/check control and adding the top-right full summary panel.
- `npm run lint -- --max-warnings=0`, `npx tsc --noEmit`, Swift parse checks for touched Clicky files, JSON validation, and a persona-ranking smoke check pass after wiring Teach persona attribution, Apply recommendation payloads, compact Clicky guidance, and Magda/Leo/Reuban persona seeds. The smoke check verifies Magda, Leo, and Reuban each win their seeded Sphere under their own lens.

## Current Known Limitations

- Assistant voice mode can use ElevenLabs when local secrets are configured, and now falls back to the macOS system voice when ElevenLabs credentials/calls fail. The local Worker also supports OpenAI speech as a `/tts` fallback via `TTS_PROVIDER=openai`.
- Observation Mode is still transcript-parsed rather than conversationally asking precise follow-up questions, but its macOS package now includes screenshot evidence and conversation text for backend ingestion.
- Deployment Mode ranks from context and approved objects, but it does not yet analyze screenshot regions semantically.
- Taste profile fusion now affects ranking through profile and lens boosts, but authority/conflict resolution is still simple and local; it is not yet a full governance or permissions model.
- Creator attribution is captured only when the caller sends `creator_profile_id` or the record is seeded with one. Older persisted Spheres without that field are displayed as missing creator metadata until migrated or recaptured.
- The Sphere Library is now intentionally read-first and minimal; web capture/guide form controls were removed, so new sphere creation currently comes from macOS Observation Mode or direct API calls rather than the library UI.
- Base capture ingestion is still heuristic. Orchestrated capture can now let Claude replace the heuristic decision summary when `CLAUDE_WORKER_BASE_URL` is configured, but new sphere creation still feels mechanical until the system asks taste-shaping follow-up questions and uses the screenshot to name real visual tensions.
- Design Decision Package persistence now stores screenshot metadata-only evidence with MIME type, byte length, SHA-256, optional dimensions/screen index, and provenance. It still does not persist thumbnails or externalized image asset references.
- Multi-agent orchestration now parses a valid Claude `decision_summary` into the package, but completeness gating, stricter schema validation, and lifecycle transitions still need hard enforcement.
- Sphere image generation is configured through either a Worker image route or local server-side `OPENAI_API_KEY`. Generated image assets are not yet persisted to durable local files or linked back onto Sphere/package records as stable asset references.
- Rejected alternatives are represented in association kinds and surfaced in guidance, but validation/evals should lock down that lifecycle behavior.
- Draft and approved lifecycle exists, but permission/role enforcement is local-only and not hardened.
- API validation is minimal and should be strengthened before company-wide use.
- The local engine uses JSON files; concurrent writes and migrations are not yet robust.
- The root repo tracks `taste-fingerprint-studio` as nested content, so product work must be careful about root-vs-service git state.

## Highest-Leverage Seams

- Backend model validation and relation semantics in `taste-fingerprint-studio/types/sphere.ts`, `lib/spheres/engine.ts`, and routes under `app/api/spheres/`.
- Capture ingestion in `taste-fingerprint-studio/lib/captures/agent.ts` and `app/api/captures/ingest/route.ts`.
- Decision package persistence in `taste-fingerprint-studio/lib/decision-packages/package-builder.ts`, `lib/spheres/store.ts`, and `app/api/decision-packages/route.ts`.
- Manual/eval coverage in `taste-fingerprint-studio/scripts/` or a lightweight Node test script.
- Product UX in `taste-fingerprint-studio/components/sphere/SphereApp.tsx`.
- macOS mode routing in `leanring-buddy/CompanionManager.swift`, `TasteEngineModels.swift`, and `CompanionPanelView.swift`.

## Product Direction

The next work should prioritize vertical capability:

1. Add durable sphere visual asset persistence so generated images become stable package and Sphere references, not transient API payloads.
2. Make observation capture feel like a guided sphere assembly, not a form.
3. Verify the macOS observation package against the backend decision/capture contract and connect any browser-orb collector to `/api/captures/ingest`.
4. Add a repeatable launch demo seed/walkthrough for capture -> sphere -> approve -> deploy.
5. Add evals that prevent draft objects from leaking into approved recommendations.
6. Add screenshot-region critique so deployment guidance points at specific weak areas.
7. Harden validation and local persistence.
8. Surface Design Decision Packages in the UI so every decision visibly preserves transcript, screenshot evidence status, source context, resulting Sphere, WeightedObjects, and approval status.

## Exact Launch Blockers Remaining

1. Guided observation demo: a taste owner still needs a faster flow to capture overweighted, underweighted, rejected, and invented associations into one draft Sphere.
2. Collector integration: macOS observation now posts push-to-talk capture packages into `/api/captures/ingest`; browser-orb capture surfaces still need to post raw captures there.
3. Approval handoff: the demo needs a visible promote-to-approved moment with provenance, so draft inferred taste never looks deployable by default.
4. Screenshot critique: deployment guidance should point at specific weak regions, not only the typed context.
5. Rejection semantics hardening: rejected alternatives are now visible in the launch seed and recommendation guidance, but backend validation/evals should lock this down.
6. Demo QA script: the launch wedge needs seeded data and a repeatable walkthrough covering capture, sphere assembly, approve, deploy, accept/reject guidance, and persisted memory.
7. Decision package completeness UI/eval: every capture/decision must visibly prove transcript + screenshot evidence status alongside source context, resulting Sphere, WeightedObjects, and approval status.