# PRODUCT_SCORECARD.md

Score each area from 0-5. Update this file after each convergence pass.

## 1. Core Model Integrity

- WeightedObjects exist and persist.
- Spheres exist and persist.
- Associations are explicit.
- Draft/approved/deprecated lifecycle is enforced.
- Rejected alternatives are first-class.

Current score: 4/5

Notes: Core primitives exist and persist. Capture records now persist as first-class local memory and can produce draft objects/spheres. Draft/approved is enforced for recommendation inputs. Validation/evals still need hardening.

Decision Package QA: Contract clarified on 2026-05-02. Capture ingestion now creates persisted Design Decision Packages with transcript/conversation turns, screenshot metadata, source context, linked Sphere, linked WeightedObjects, associations, status, and provenance. Implementation still needs a completeness eval and UI status, so the score remains 4/5.

## 2. Observation Mode Capability

- Taste owner can capture a decision quickly.
- System asks what was overweighted, underweighted, rejected, and invented.
- New conceptual notions become draft objects.
- Observation becomes a Sphere.

Current score: 3/5

Notes: Observation route and macOS mode exist, and macOS push-to-talk observations now package transcript, conversation text, screenshot data URL, and screenshot metadata into capture ingestion. The capture UI is still form-heavy and not yet a full guided sphere assembly sequence.

Decision Package QA: Observation capture must not be considered complete unless the transcript and screenshot evidence status are packaged with the resulting Sphere and object associations.

## 3. Deployment Mode Capability

- User can invoke Sphere on weak design.
- System retrieves relevant approved Spheres.
- System explains concrete weighted guidance.
- New inferred associations remain draft.
- Accepted/rejected guidance is saved.

Current score: 3/5

Notes: Recommendation route ranks approved signal and now returns visible overweight/underweight/reject guidance with source counts in the UI. It now accepts and echoes taste profile selection/fusion metadata, but `applied_to_ranking` remains false and no profile authority is applied. It does not yet inspect screenshot regions.

Decision Package QA: Accepted/rejected deployment guidance should persist as a Design Decision Package too, including the user's transcript/prompt, screenshot evidence, source context, matched approved Sphere, any draft inferred Sphere, weighted guidance objects, and approval/feedback status.

## 4. Local Engine Reliability

- API routes exist.
- JSON persistence works.
- Invalid requests are handled.
- Data survives restart.
- Local health state is visible.

Current score: 4/5

Notes: Routes and persistence work, including `/api/captures/ingest`, `/api/captures`, and capture records in JSON persistence. Creator/collaborator profile metadata can now pass through capture, package, sphere, object, and guidance records, and recommendation responses echo normalized taste fusion metadata. Design Decision Packages now generate `summary_markdown` and newly captured Spheres link back to that summary. Validation and concurrent-write safety are still weak.

Decision Package QA: Persistence now records package-level evidence and graph links in `data/decision-packages.json`, with screenshot payloads omitted by policy and replaced by MIME/byte/hash metadata. Add package completeness validation before raising this score.
Decision Package QA Update (2026-05-02): Added `/api/captures/ingest/orchestrated` with one focused Claude agent, `transcription_decision_summarizer`. Valid summary-agent JSON now replaces the heuristic package `decision_summary`; campaign-compression image generation uses a canonical fixed prompt plus the source screenshot and can flow into a Worker-backed or local `/image` path. Strict completeness gating, deeper schema validation, and durable generated-asset persistence are still needed.

## 5. macOS Integration

- Existing assistant mode still works.
- SphereMode.observation exists.
- SphereMode.deployment exists.
- TasteEngineAPIClient exists.
- Floating Sphere overlay works.

Current score: 4/5

Notes: Swift parsing passes and mode routing is present. Observation Mode now posts capture packages to `/api/captures/ingest`, and Deployment Mode sends conversation transcript plus screenshot evidence metadata with recommendations. macOS Codable models now mirror the taste profile selection and fusion metadata payload, but no profile selection UI or runtime selection logic has been added. The Worker proxy URL is bundle-configurable via `WorkerBaseURL`. TTS now has two local fallbacks: OpenAI speech through the local Worker and macOS system speech inside the app when ElevenLabs is unavailable. Manual Xcode run is still required; terminal `xcodebuild` must not be used.

## 6. Product Intuitiveness

- New user can understand what a Sphere is.
- First screen communicates the outcome: capture the best designer's taste and deploy it across the company.
- UI distinguishes draft vs approved.
- UI shows provenance.
- UI avoids generic dashboard feel.
- Main flows require minimal ceremony.

Current score: 4/5

Notes: The web surface is now a calmer Sphere Library with visual sphere anchors, lifecycle status, decision summaries, and a focused trace panel. Creator/collaborator metadata appears as small founder/profile orb avatars when present, and missing creator metadata is explicit. Semantic objects now orbit the main Sphere as small role-colored spheres instead of pill badges. The old count tiles, explanatory header copy, boxed trace-choice tiles, graph view, and floating question/form workflow were removed. Creation still needs a better guided capture path outside direct API/macOS ingestion.

Decision Package QA: UI should expose whether each decision has transcript evidence, screenshot evidence, source context, graph output, and approval status. This is now a product contract, not optional polish.

## 7. Product Polish

- Loading states.
- Empty states.
- Error states.
- Seed demo data.
- Manual QA path.

Current score: 4/5

Notes: Visual polish, loading affordances, seed presentation, and library focus are stronger. The current Taste Engine on port 3000 responds to graph API smoke checks, lint and TypeScript checks pass, and the orchestrated route degrades cleanly when agent/image secrets are missing. The Sphere Library now shows founder orb attribution, an open summary evidence panel in the trace, and a sticky top-right full summary panel launched from the Summary control. Seed data now has 12 approved WeightedObjects and 5-6 role-explicit associations per Sphere. `npm run build` was previously blocked by Google font fetch failures in `next/font`; rerun build when network access to fonts is stable. Manual QA scripting and deeper trust details still need work.

Decision Package QA: Backend package persistence is in place. Trust details are incomplete until decision package status is visible in the UI and package completeness can be verified by an eval.

## 8. Capability Density

- Each interaction creates reusable taste data.
- Recommendations improve from prior observations.
- System captures what was rejected, not only what was chosen.
- There is an obvious path to future ranking/training.

Current score: 4/5

Notes: Interactions persist reusable objects/spheres, every Teach capture can now be stamped with a teaching persona, and Apply recommendations can use persona/lens payloads that actually affect ranking. Guidance feedback learning still needs explicit acceptance/rejection loops.

Decision Package QA: Capture ingestion now creates the complete Design Decision Package as a reusable unit instead of only storing loose transcript text, screenshots, Spheres, or objects separately.
Decision Package QA Update (2026-05-02): Orchestrated capture ingestion now enriches each package with a strict Claude decision summary and optional campaign-compression sphere image generation through a Worker proxy or local server-side `OPENAI_API_KEY`, increasing inspectable judgment density without changing assistant mode. The image prompt is now fixed and canonical rather than generated by a second agent. A campaign screenshot dry-run verified screenshot routing into the canonical image path. The generated image still needs durable local asset storage and graph linkage.

## 9. Launch Demo Readiness

- First viewport states the launch promise in outcome language.
- Demo shows observe -> approve -> deploy as one tight loop.
- Approved taste is visibly different from draft inference.
- Deployment guidance cites provenance from the best designer's decisions.
- Seed data and QA script make the wedge repeatable.

Current score: 4/5

Notes: The first-screen promise has been simplified into a visual Sphere Library, deploy guidance memory is linked to decision summaries, and Clicky now has a narrow persona-attributed Teach path plus persona/lens-aware Apply payloads. The remaining work is real image-provider/asset persistence, a repeatable capture/approve/deploy walkthrough, screenshot-region critique, and eval coverage.

Decision Package QA: Add package completeness to the launch demo acceptance criteria: transcript present, screenshot evidence present or explicitly unavailable, source context present, Sphere/object graph linked, and approval state visible.