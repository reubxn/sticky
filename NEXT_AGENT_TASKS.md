# NEXT_AGENT_TASKS.md

Agents should append new tasks here after every run.

Each task must include:

- title
- product problem
- files likely involved
- expected capability gain
- verification steps
- risk level

## Active Queue

### Agent 018 - Persona Lens Runtime QA

Problem:
Clicky now stamps Teach captures with a selected teaching persona and routes Apply payloads through the Taste Engine with profile/lens metadata that affects ranking. The next risk is runtime confidence: Reuban needs to verify the local Taste Engine is running, the macOS panel state persists, and Apply responses cite the intended lens without changing Worker deployment configuration.

Files likely involved:

- `leanring-buddy/CompanionManager.swift`
- `leanring-buddy/CompanionPanelView.swift`
- `leanring-buddy/TasteEngineModels.swift`
- `taste-fingerprint-studio/app/api/spheres/recommend/route.ts`
- `taste-fingerprint-studio/data/`

Expected capability gain:
Confirm the demo loop works end-to-end on Reuban's machine: Teach attribution stamps the right creator, Apply uses the selected lens payload, and different persona lenses produce visibly different guidance while Ask mode remains normal.

Verification:
Run the Taste Engine locally, use the macOS panel to select Magda/Leo/Reuban as Teach attribution, perform one Teach session, then run Apply against the same screen with different wheel/profile selections. Confirm `creator_profile_id`, `recommendation_lens`, `taste_fusion.applied_to_ranking`, and `clicky_guidance` in the payloads/responses. Do not edit Worker config or run `xcodebuild`.

Risk:
Medium.

## Completed Recently

### Agent 017 - Profile Selection Consumer

Problem:
The Taste Engine now has a payload-only contract for creator/collaborator metadata and recommendation taste fusion echoes, but no runtime surface chooses or explains which profile should be deployed. The next pass should consume the contract deliberately without changing ranking until there is a visible product decision for profile authority.

Files likely involved:

- `leanring-buddy/CompanionPanelView.swift`
- `leanring-buddy/CompanionManager.swift`
- `leanring-buddy/TasteEngineModels.swift`
- `taste-fingerprint-studio/components/sphere/SphereApp.tsx`
- `taste-fingerprint-studio/lib/spheres/engine.ts`

Expected capability gain:
Users can see and choose whose taste context is being sent while the product still makes clear whether that context is metadata-only or actually affects guidance.

Verification:
Add UI/runtime selection only after the authority model is explicit. Run `npm run lint -- --max-warnings=0`, `npx tsc --noEmit`, Swift parse/type checks without `xcodebuild`, and recommendation smoke checks that verify `applied_to_ranking` remains false until ranking behavior is intentionally changed.

Risk:
Medium.

### Agent 016 - Sphere Visual Asset Persistence

Problem:
The orchestrated capture flow can now derive a campaign-compression sphere prompt and call a Worker-backed image route, but generated visuals are still transient response data. The product needs durable local asset files plus metadata references linked to the Design Decision Package and Sphere.

Files likely involved:

- `taste-fingerprint-studio/types/sphere.ts`
- `taste-fingerprint-studio/lib/orchestration/image-client.ts`
- `taste-fingerprint-studio/lib/orchestration/decision-package-orchestrator.ts`
- `taste-fingerprint-studio/lib/spheres/store.ts`
- `taste-fingerprint-studio/public/` or a local data asset directory
- `worker/src/index.ts`

Expected capability gain:
Campaign Compression Spheres become reusable product memory instead of decorative or transient outputs: every generated central sphere and later mini-sphere can be inspected, cited, cached, and displayed from a stable local reference.

Verification:
Configure `CLAUDE_WORKER_BASE_URL`/`IMAGE_WORKER_BASE_URL` and `OPENAI_API_KEY` in the Worker, run an orchestrated capture with a screenshot, assert the response includes image generation status and a persisted local asset reference, then run `npm run lint -- --max-warnings=0` and `npm run build`.

Risk:
Medium.

### Agent 015 - Multi-Agent Orchestrator Hardening

Problem:
`/api/captures/ingest/orchestrated` now wraps capture ingestion with a transcription summarizer agent and a campaign-compression sphere generator agent. Valid summary-agent JSON is parsed back into `decision_package.decision_summary`, but completeness gating, lifecycle readiness enforcement, and schema/eval coverage are still not hard enough.

Files likely involved:

- `taste-fingerprint-studio/app/api/captures/ingest/orchestrated/route.ts`
- `taste-fingerprint-studio/lib/orchestration/decision-package-orchestrator.ts`
- `taste-fingerprint-studio/lib/orchestration/claude-client.ts`
- `taste-fingerprint-studio/lib/decision-packages/package-builder.ts`
- `taste-fingerprint-studio/types/sphere.ts`

Expected capability gain:
Orchestrated package creation becomes deterministic and enforceable: transcript and screenshot evidence completeness can be hard-gated, role outputs are validated against a real schema, and approval readiness can be audited without brittle prompt text parsing.

Verification:
Run `npm run lint -- --max-warnings=0` and `npm run build`. Add a smoke script that posts one complete and one incomplete request to `/api/captures/ingest/orchestrated`, then asserts `orchestration.agent_audits`, provenance note writes, and expected persistence/no-persistence behavior for `dry_run`.

Risk:
Medium.

### Agent 014 - Decision Package Completeness UI and Eval

Problem:
Capture ingestion now persists Design Decision Packages, but the product still lacks a visible package completeness state and an automated check that transcript, screenshot evidence status, source context, graph links, and lifecycle status are present.

Files likely involved:

- `taste-fingerprint-studio/types/sphere.ts`
- `taste-fingerprint-studio/app/api/decision-packages/route.ts`
- `taste-fingerprint-studio/components/sphere/SphereApp.tsx`
- `taste-fingerprint-studio/scripts/`
- `PRODUCT_SCORECARD.md`

Expected capability gain:
Every captured decision can be audited from the UI and from a repeatable smoke/eval: what was said, what screen was seen or explicitly missing, where it came from, which Sphere and WeightedObjects resulted, and whether the package is draft/processed/approved/archived.

Verification:
Add or update a smoke/eval that ingests a transcript plus screenshot data URL and asserts the response and persisted record include transcript evidence, screenshot metadata/status, source context, resulting Sphere ID, WeightedObject IDs, associations, provenance, and package status. Run `npm run lint`, `npm run build`, and the new package completeness check.

Risk:
Medium.

### Agent 011 - Capture Collector Integration

Problem:
The local Taste Engine now has `/api/captures/ingest`, but the macOS observation flow and browser-orb prototype are not yet wired to send every raw capture into that endpoint. The WhatsApp prototype files show useful capture triggers, but they also include a hardcoded model key and should be treated only as untrusted reference material.

Files likely involved:

- `leanring-buddy/TasteEngineAPIClient.swift`
- `leanring-buddy/CompanionManager.swift`
- `leanring-buddy/TasteEngineModels.swift`
- browser extension/content-script files if they are moved into the repo
- `taste-fingerprint-studio/app/api/captures/ingest/route.ts`

Expected capability gain:
Every screenshot, voice observation, page selection, and orb dwell event can become a persisted draft Sphere association without exposing API keys client-side.

Verification:
Run `npm run lint`, `npm run build`, Swift parse checks only, and a local capture smoke check. Do not run `xcodebuild`.

Risk:
Medium.

### Agent 010 - Local Voice Smoke Test

Problem:
The macOS app can now read a local Worker URL from `WorkerBaseURL`, and the Taste Engine is responding on port 3000, but the full Clicky assistant loop still needs a manual run with real Worker secrets and macOS permissions.

Files likely involved:

- `worker/.dev.vars`
- `leanring-buddy/Info.plist`
- `leanring-buddy/CompanionManager.swift`
- `leanring-buddy/AssemblyAIStreamingTranscriptionProvider.swift`

Expected capability gain:
Confirm push-to-talk can capture audio, fetch an AssemblyAI token through the local Worker, send transcript + screenshot to Claude, play ElevenLabs TTS, and preserve Sphere mode routing.

Verification:
Create `worker/.dev.vars` from `worker/.dev.vars.example`, run `cd worker && npm run dev`, confirm `/transcribe-token` returns a token through the Worker, open `leanring-buddy.xcodeproj` in Xcode, run the app, grant permissions, and perform one assistant-mode push-to-talk interaction. Do not run `xcodebuild`.

Risk:
Medium.

### Agent 007 - Launch Demo Seed and Walkthrough

Problem:
The launch wedge now has first-screen promise copy, a deploy guidance seed, and capture-to-sphere infrastructure, but it still needs a repeatable story: capture a strong designer's decision, approve the learned Sphere, deploy it against weaker work, then persist accepted/rejected guidance. Without a precise script, agents may improve parts of the system without increasing launch readiness.

Files likely involved:

- `taste-fingerprint-studio/data/`
- `taste-fingerprint-studio/scripts/`
- `taste-fingerprint-studio/components/sphere/SphereApp.tsx`
- `PRODUCT_STATE.md`
- `PRODUCT_SCORECARD.md`
- `NEXT_AGENT_TASKS.md`

Expected capability gain:
The demo becomes reproducible and can prove the product promise without relying on improvised local state.

Verification:
Create one script or doc-backed walkthrough for the existing premium product hero seed: capture, translate to sphere, promote, guide, accept/reject. Run `npm run lint`, `npm run build`, and the walkthrough script if added. Document the exact manual walkthrough in product memory.

Risk:
Medium.

### Agent 008 - Approval and Provenance Moment

Problem:
Draft inferred taste must not look like approved truth. The launch demo needs a clear promotion moment where an observed Sphere becomes approved deployment signal with visible provenance.

Files likely involved:

- `taste-fingerprint-studio/components/sphere/SphereApp.tsx`
- `taste-fingerprint-studio/lib/spheres/engine.ts`
- `taste-fingerprint-studio/app/api/spheres/promote/route.ts`
- `taste-fingerprint-studio/types/sphere.ts`
- `PRODUCT_SCORECARD.md`

Expected capability gain:
The viewer can see why a recommendation is trusted and who/what decision it came from.

Verification:
Manual flow creates a draft Sphere from observation, promotes it, and then shows the approved Sphere as deployable with provenance. Run `npm run lint` and `npm run build`.

Risk:
Medium.

### Agent 009 - Deployment Critique Wedge

Problem:
Deployment recommendations now name what to overweight, underweight, and reject from approved designer decisions. The remaining wedge is screenshot-region critique: point at the weak area and tie the guidance to that visual region.

Files likely involved:

- `taste-fingerprint-studio/lib/spheres/engine.ts`
- `taste-fingerprint-studio/app/api/spheres/recommend/route.ts`
- `taste-fingerprint-studio/components/sphere/SphereApp.tsx`
- `leanring-buddy/TasteEngineModels.swift`
- `PRODUCT_SCORECARD.md`

Expected capability gain:
Non-taste users can invoke approved taste, see a pointed critique on the weak screen, and understand which approved designer decision it came from.

Verification:
Recommendation response includes concrete rationale, approved Sphere/source citations, draft status for any new inference, and a point target/screenshot-region explanation. Run `npm run lint`, `npm run build`, and a local API smoke check for `/api/spheres/recommend`.

Risk:
High.

### Agent 001 - Repo Cartographer and State Verifier

Problem:
The product now has macOS, worker, and local Taste Engine surfaces. Future agents need an accurate map and must not confuse root repo state with nested service state.

Files likely involved:

- `PRODUCT_STATE.md`
- `PRODUCT_SCORECARD.md`
- `NEXT_AGENT_TASKS.md`

Expected capability gain:
Sharper orchestration and fewer blind edits.

Verification:
Docs reflect actual files, commands, routes, and limitations.

Risk:
Low.

### Agent 002 - Rejected Relation and Lifecycle Hardening

Problem:
Rejected alternatives are visible in the UI but are not yet a first-class backend relation. Draft/approved behavior exists but needs tests and stricter validation.

Files likely involved:

- `taste-fingerprint-studio/types/sphere.ts`
- `taste-fingerprint-studio/lib/spheres/engine.ts`
- `taste-fingerprint-studio/app/api/spheres/*/route.ts`
- `taste-fingerprint-studio/components/sphere/SphereApp.tsx`

Expected capability gain:
Recommendations can explain suppress/reject behavior without lifecycle leaks.

Verification:
`npm run lint`, `npm run build`, and an eval showing draft objects do not power deployment recommendations.

Risk:
Medium.

### Agent 003 - Observation Sphere Assembly UX

Problem:
Observation capture is too form-heavy. A taste owner should be guided through overweighted, underweighted, rejected, and invented choices quickly.

Files likely involved:

- `taste-fingerprint-studio/components/sphere/SphereApp.tsx`
- possibly small helpers under `taste-fingerprint-studio/lib/`

Expected capability gain:
Observation Mode feels like building a sphere association, not filling a generic form.

Verification:
Manual flow creates a draft Sphere with clear object categories and visible provenance.

Risk:
Medium.

### Agent 004 - Deployment Guidance Quality

Problem:
Deployment recommendations now expose concrete weighting guidance in the web UI. The remaining quality work is to persist accept/reject feedback cleanly, improve ranking from repeated decisions, and keep draft inference visibly separate in every consuming surface.

Files likely involved:

- `taste-fingerprint-studio/lib/spheres/engine.ts`
- `taste-fingerprint-studio/app/api/spheres/recommend/route.ts`
- `taste-fingerprint-studio/components/sphere/SphereApp.tsx`
- `leanring-buddy/TasteEngineModels.swift`

Expected capability gain:
The user sees guidance improve from prior accepted/rejected decisions without draft inference leaking into approved taste.

Verification:
Recommendation response includes rationale, matched approved sources, optional draft sphere status, and a saved guidance decision path. Run `npm run lint`, `npm run build`, and a decision API smoke check.

Risk:
High.

### Agent 005 - Eval Builder

Problem:
The product can regress easily because the lifecycle rules are not measured.

Files likely involved:

- `taste-fingerprint-studio/scripts/`
- `taste-fingerprint-studio/package.json`
- `PRODUCT_SCORECARD.md`

Expected capability gain:
Future agents have a lightweight automated gate for core product promises.

Verification:
Script verifies ingest, observe, recommend, promote, decision logging, and draft-object exclusion.

Risk:
Low.

### Agent 006 - Product Taste Reviewer

Problem:
The product now has a strong floating-sphere shell, but capture still needs a more direct Apple-like interaction.

Files likely involved:

- `taste-fingerprint-studio/components/sphere/SphereApp.tsx`
- `taste-fingerprint-studio/app/page.tsx`
- `PRODUCT_SCORECARD.md`

Expected capability gain:
Replace typed capture fields with progressive sphere assembly: pick overweighted/underweighted/rejected/invented objects visually, then save.

Verification:
Manual walkthrough is coherent without explaining the architecture out loud.

Risk:
Low.

## Completed This Pass

### Founder Attribution Orbs and Summary Markdown Link

Result:
Removed the all/draft/rejected stat tiles, explanatory header copy, boxed trace-choice tiles, and the sticky blue refresh/check button from the Sphere Library. Replaced text-only creator chips with small founder/profile orb avatars, made missing creator metadata explicit, and changed semantic tokens into small role-colored orbit spheres around the central Sphere. The selected trace opens the linked summary as an ambient evidence panel, and the sticky top `Summary` control opens a full top-right decision-summary panel for the selected Sphere. Design Decision Packages now generate `summary_markdown`; newly captured Spheres link back to that markdown, recommendation citations can carry it, and the summary-agent prompt now asks for precise `central_decision` and `reusable_rule` formats. Seed Spheres now include founder attribution plus structured decision summaries so the current UI does not fall back to generic rules.

Verification:
`npm run lint -- --max-warnings=0` and `npx tsc --noEmit` pass. A `/api/captures/ingest` dry-run with `creator_profile_id: founder` returned the creator on the generated Sphere and Design Decision Package and returned a `# Decision Summary` markdown string linked to the generated Sphere. JSON validation and a graph smoke check verify all current seed Spheres return `creator_profile_id: "founder"`, precise reusable rules, `summary_markdown`, 12 approved WeightedObjects, and 5-6 role-explicit associations per Sphere.

### Taste Payload Contract

Result:
Added minimal taste profile payload types and metadata fields across WeightedObjects, Spheres, capture records, Design Decision Packages, guidance decisions, recommendation requests, recommendation responses, and macOS Codable models. `/api/spheres/recommend` now normalizes absent payloads to `company` + `single_profile` and echoes `taste_fusion` with `applied_to_ranking: false`; creator/collaborator metadata is preserved through capture/package creation and shown as chips in existing Sphere cards/traces when present.

Verification:
`npm run lint -- --max-warnings=0`, `npx tsc --noEmit`, `swiftc -parse leanring-buddy/TasteEngineModels.swift leanring-buddy/TasteEngineAPIClient.swift`, and `swiftc -typecheck leanring-buddy/TasteEngineModels.swift leanring-buddy/TasteEngineAPIClient.swift` pass. Direct `tsx` route smoke checks verify request-supplied and default recommendation `taste_fusion` echoes, and a capture-ingest dry run verifies `creator_profile_id` returns on the capture, Sphere, and Design Decision Package.

### Worker A - Design Decision Package Backend Persistence

Result:
Added Design Decision Package domain types, a package builder, JSON persistence in `data/decision-packages.json`, automatic package creation from `/api/captures/ingest`, package inclusion in `/api/palette/graph`, and `GET/POST /api/decision-packages`. Screenshot data URLs remain out of JSON storage; packages keep metadata-only evidence with MIME type, byte length, SHA-256, optional dimensions/screen index, timestamp, and provenance.

Verification:
`npm run lint -- --max-warnings=0`, `npm run build`, and a `tsx` package-builder smoke check for transcript retention plus metadata-only screenshot evidence.

### Agent 012 - Capture Ingestion Agent Infrastructure

Result:
Added capture domain types, capture JSON persistence, `/api/captures`, `/api/captures/ingest`, and a local heuristic capture agent that turns raw page/element/selection/screenshot/voice/manual captures into draft WeightedObjects, a draft Sphere, associations, a capture record, and a follow-up question. The Evidence workflow now posts to capture ingestion instead of stopping at loose palette ingest.

Verification:
`npm run lint -- --max-warnings=0`, `npm run build`, and `/api/captures/ingest` dry-run smoke check.

### Worker C - Design Decision Package QA Contract

Result:
Defined the Design Decision Package product contract in product memory and agent instructions. Future captures and decisions must preserve conversation transcript, screenshot evidence, source context, resulting Sphere, WeightedObjects, and approval status together. Documented the current persistence gap: screenshot data is sanitized from capture records without a durable evidence asset reference/status.

Verification:
Docs-only pass. No lint/build run because no TypeScript, Swift, or runtime files were changed.

### Agent 000 - First Screen Launch Promise

Result:
The first screen now leads with "Capture your best designer's taste. Let the whole company design with it." It shows Observe -> Approve -> Guide, lifecycle counts, a prefilled weak-design prompt, and a concrete guidance preview. The local deploy recommendation can now surface overweight, underweight, reject, and approved source count.

Verification:
`npm run lint -- --max-warnings=0`, `npm run build`, local `/api/spheres/recommend` smoke check, and in-app browser verification at `http://localhost:3000/`.

### Agent 014 - Decision Package Contract Smoke Test

Problem:
The macOS app now sends observation capture packages with transcript, conversation transcript, screenshot data URL, and screenshot metadata, but the backend still needs an end-to-end contract check that every persisted Design Decision Package exposes durable evidence status after screenshot sanitization.

Files likely involved:

- `taste-fingerprint-studio/app/api/captures/ingest/route.ts`
- `taste-fingerprint-studio/lib/captures/agent.ts`
- `taste-fingerprint-studio/types/sphere.ts`
- `taste-fingerprint-studio/lib/spheres/store.ts`
- `leanring-buddy/TasteEngineModels.swift`

Expected capability gain:
A macOS observation can be verified as a complete decision package with transcript, screenshot evidence metadata/reference, resulting Sphere, WeightedObjects, and approval status.

Verification:
Run the local Taste Engine, POST a representative macOS capture package with `dry_run`, then a persisted request, and verify `/api/captures` exposes package completeness without retaining raw screenshot data unexpectedly. Run `npm run lint`, `npm run build`, and `swiftc -parse leanring-buddy/*.swift`. Do not run `xcodebuild`.

Risk:
Medium.