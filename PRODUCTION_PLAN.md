# Sticky Production Plan

This document is the source of truth for turning Sticky from a local hackathon
prototype into a multi-user product. Product rules in this document are
confirmed. Technical choices marked **recommended** remain implementation
decisions and may be revised through an architecture PR.

## Launch boundaries

- Free private beta.
- One managed data region.
- Google and email magic-link authentication.
- Enterprise SSO, SCIM, regional residency selection, and billing are deferred.
- Production accounts start clean. Existing local `TASTE.md`, JSON profiles,
  conversations, and recordings are not migrated.
- Convex is the application backend.
- The existing Cloudflare Worker remains the streaming gateway for Anthropic,
  ElevenLabs, and AssemblyAI.
- R2 is the recommended store for private or large workspace files.

## Product model

### Accounts and workspaces

1. Signup creates exactly one personal workspace.
2. A personal workspace is permanently private and single-user.
3. A personal workspace cannot invite members, be transferred, or be converted
   into a team workspace.
4. Users may create or join multiple team workspaces.
5. Team workspaces are invite-only.
6. Workspace roles are `owner`, `admin`, and `member`.
7. Owners and admins may invite and remove members. Admins cannot remove owners.
8. Workspace owners and admins may edit shared workspace context and files.

### Membership personas

1. Every active workspace membership has exactly one persona.
2. The persona belongs to the membership's user and is unique to that
   workspace.
3. A persona is never copied automatically between workspaces.
4. Joining a workspace starts one seamless, voice-first conversation with
   Sticky. Text remains available as a fallback.
5. A persona represents:
   - communication style;
   - decision-making taste;
   - professional expertise;
   - explicit boundaries.
6. Every active member of a team workspace may use every other active member's
   persona.
7. Only the persona owner may edit it, train it, review its suggestions, or
   approve changes.
8. Workspace owners and admins have no special editing authority over another
   member's persona.
9. Removing a member immediately makes their persona unavailable in that
   workspace.
10. Rejoining creates a new membership and a fresh persona. Removed persona data
    is not restored.
11. Removing a member purges the original persona records and approved evidence.
    Historical conversations retain only their independent frozen snapshots.

### Conversational persona onboarding

1. Sticky introduces itself, explains what the persona can do, and begins with
   an open question such as what kind of work the member does.
2. Follow-up questions adapt to the member's answers rather than following a
   visible questionnaire.
3. Voice is the primary input. Text is always available as a fallback.
4. Answers are converted continuously into structured communication,
   decision-making, expertise, and boundary records.
5. Explicit onboarding answers save automatically. They do not enter the later
   learning-suggestion approval queue.
6. Once Sticky knows the member's work and at least one communication
   preference, the persona becomes usable. The member may continue the deeper
   interview later.
7. Sticky shows an informational summary of what it learned, but activation
   does not require approving that summary.
8. Full persona records and evidence remain owner-private.
9. A short boundary summary may be visible to teammates only after the persona
   owner explicitly approves that summary.
10. AI-generated interpretations must remain traceable to the owner's
    onboarding answers and must never be treated as evidence from another
    member.

### Workspace context

Workspace context is shared business knowledge, not a shared persona.

Personal workspaces receive a default name derived from the user's profile.
Business context is optional.

Team workspace creation requires:

- workspace name;
- business type.

Owners and admins may later add:

- business description;
- products or services;
- target audience;
- current goals;
- a free-form brief;
- supporting files.

All active workspace members may use this context through personas in that
workspace. Context from one workspace must never enter another workspace.

### Conversations

1. Every conversation belongs to exactly one asking user.
2. Conversations are private by default.
3. Workspace owners and admins cannot read members' private conversations.
4. Selecting another member's persona does not add the asking user's own persona
   memories or preferences to the response.
5. Request context is assembled from:
   - the selected membership persona;
   - the active workspace's relevant shared context;
   - the current private conversation;
   - relevant messages from the asking user's earlier private conversations
     with that same selected persona, weighted below the current conversation;
   - relevant active persona records and supporting sources. Active records are
     either explicit onboarding records or records created from owner-approved
     learning suggestions.
6. When a selected persona becomes unavailable, historical conversations retain
   an immutable persona snapshot.
7. Those historical conversations become read-only and cannot generate new
   replies.
8. A removed member retains private, read-only access to their own historical
   workspace conversations. They cannot read workspace context or continue
   those conversations.
9. Screenshots are ephemeral and are discarded after the current request or
   analysis finishes.

### Controlled persona learning

This section applies after initial onboarding. Explicit onboarding answers use
the automatic-save rules above.

1. Only the persona owner's own interactions and Teach sessions may generate
   suggestions for that persona.
2. The source interaction must have been owned by that user and must have
   targeted that same persona. An owner using somebody else's persona trains
   neither persona.
3. Another member using the persona can never train it or create suggestions.
4. Suggestions are private to the persona owner.
5. Suggestions do not affect the persona until the owner approves them.
6. Approval creates versioned persona records with immutable provenance.
7. Approved records retain short supporting evidence excerpts for the lifetime
   of the persona.
8. Rejecting a suggestion deletes its evidence and derived artifacts.
9. Full screenshots are never retained as persona evidence.

### Deletion

1. Account deletion starts a seven-day recovery window.
2. The account is signed out and locked immediately. Cancellation is available
   through a verified email recovery flow.
3. A user who is the last owner of a team workspace must transfer ownership or
   explicitly delete that workspace before starting account deletion.
4. After the recovery window, the account, personal workspace, memberships, personas,
   approved evidence, and private conversations are permanently purged.
5. Membership removal is not account deletion. It revokes live workspace access,
   purges that membership's persona data, and preserves only frozen snapshots
   inside private read-only conversations.
6. Internal jobs must re-check membership and ownership before committing work
   so delayed jobs cannot write after removal.
7. Explicit team-workspace deletion revokes every membership and permanently
   purges workspace context, files, personas, evidence, suggestions, private
   conversations associated with that workspace, indexes, and pending jobs.
8. Only an active workspace owner may execute team-workspace deletion.

## Production data model

The exact Convex schema will be introduced in a dedicated implementation PR.
These relationships are contractual.

### `profiles`

- Canonical authenticated user.
- Display name, avatar, account settings, deletion state.
- Exactly one profile per verified auth identity.

### `workspaces`

- `kind`: `personal` or `team`.
- Name, business type, creation metadata, lifecycle state.
- Personal workspace kind is immutable.

### `workspaceMembers`

- User, workspace, role, lifecycle status, joined and removed timestamps.
- Unique active membership per `(workspaceId, userId)`.
- Personal workspaces must have exactly one membership.

### `workspaceInvites`

- Team workspace, intended verified identity, role, token digest, expiry,
  inviter, and terminal state.
- Invitations are expiring, identity-bound, and single-use.

### `personas`

- Exactly one persona per membership.
- Immutable `membershipId`, `workspaceId`, and `ownerUserId`.
- Display identity, role, voice, avatar, setup state, current version.

### `personaRecords`

- Structured active records for communication, judgment, expertise, and
  boundaries.
- Explicit onboarding answers create active, versioned records immediately.
  Later passive learning creates inactive suggestions that become records only
  after owner approval.
- Evidence reference, provenance, confidence, and version metadata.

### `personaBoundarySummaries`

- A separate, bounded teammate-readable projection of owner-private boundary
  records.
- Persona, workspace, owner, summary text, source version, publication state,
  approved timestamp, and superseded timestamp.
- Only the persona owner may draft, approve, replace, or unpublish it.
- Active workspace members may read only the currently approved summary while
  both memberships and the persona remain active. They never receive the
  underlying boundary records or evidence.

### `personaSuggestions`

- Pending owner-only suggestion. Rejection hard-deletes the suggestion evidence
  and all derived artifacts; only a redacted audit event may remain.
- Source type, source owner, source interaction or Teach session, evidence
  excerpt, and approval state.

### `personaVersions`

- Immutable version metadata for onboarding records and approved later changes.
- Supports audit history and frozen conversation snapshots.

### `workspaceContext`

- One shared business profile per workspace.
- Description, products or services, audience, goals, and free-form brief.

### `contextSources`

- Workspace-scoped files and ingestion metadata.
- Private object reference, checksum, lifecycle state, and provenance.

### `contextChunks`

- Extracted text, embedding, source reference, and retrieval metadata.
- Vector searches must filter by the authorized workspace before loading source
  documents.

### `conversations`

- Owner user, workspace, selected persona, immutable persona snapshot, model,
  medium, title, and lifecycle state.

### `messages`

- Conversation, role, text, source references, usage, and timestamps.
- Screenshot bytes are not stored.

### `auditEvents`

- Actor, scope, operation, target, timestamp, and safe metadata for sensitive
  membership, persona, context, and deletion operations.

## Authorization contract

Authorization is deny-by-default. Public Convex functions derive the user from
verified authentication. They never trust a client-supplied user, role,
membership, workspace ownership, or persona ownership claim.

Authorization helpers return validated records rather than booleans:

- `requireIdentity()`
- `requireCanonicalUser(identity)`
- `requireWorkspace(workspaceId)`
- `requireActiveMembership(workspaceId)`
- `requireWorkspaceRole(workspaceId, allowedRoles)`
- `requireWorkspaceOwner(workspaceId)`
- `requirePersonalWorkspaceOwner(workspaceId)`
- `requireValidWorkspaceInvite(inviteToken)`
- `acceptWorkspaceInvite(inviteToken)`
- `requirePersonaOwner(personaId)`
- `requireUsablePersona(personaId)`
- `requireReadableBoundarySummary(personaId)`
- `requireConversationOwner(conversationId)`
- `requireSuggestionOwner(suggestionId)`
- `validateSuggestionProvenance(personaId, sourceId)`
- `requireWorkspaceContextEditor(workspaceId)`
- `requireAuthorizedFileRead(fileId)`
- `requireAuthorizedFileMutation(fileId)`
- `createFrozenPersonaSnapshot(personaId)`
- `revalidateInternalTask(taskId)`

### Persona use

`requireUsablePersona` succeeds only when:

- the asking user has an active membership in the persona's workspace;
- the persona owner's membership is active in the same workspace;
- the persona is active;
- the request is not attempting to read private configuration, evidence,
  suggestions, or another user's conversations.

### Persona mutation

Persona edits, training, approval, rejection, and evidence access require
`requirePersonaOwner`. Workspace roles do not bypass this check.

### Boundary-summary access

Drafting, approving, replacing, and unpublishing a boundary summary require
`requirePersonaOwner`. `requireReadableBoundarySummary` returns only the
currently approved projection after validating active asker membership, active
owner membership, the same workspace, and an active persona. It never returns
private boundary records, evidence, superseded summaries, or draft text.

### Conversation access

Listing, reading, appending, exporting, and deleting a conversation require
`requireConversationOwner`. Direct IDs, pagination, search, and attachment
access must enforce the same rule without revealing whether unauthorized
records exist. New replies additionally require an active workspace membership
and `requireUsablePersona`. Removed members and unavailable personas leave the
conversation read-only: its owner may read, export, or delete it, but may not
append messages or request another reply.

### Workspace administration

- Owners and admins may edit workspace context and files.
- Owners and admins may invite and remove members.
- Team workspace creation atomically creates the creator's owner membership and
  fresh persona without requiring an invitation. This is the only membership
  creation path that does not consume an invite.
- Admins may invite `member` or `admin` roles but cannot invite an `owner`.
- Only owners may grant ownership.
- Admins cannot remove owners or grant themselves ownership.
- Only an owner may transfer or demote an owner.
- Every active team workspace must retain at least one owner.
- The last owner must transfer ownership or explicitly delete the workspace
  before leaving or deleting their account.
- Team membership creation is possible only through atomic consumption of a
  valid, identity-bound invitation.
- Personal workspaces reject all invite and additional-membership operations.

### Internal jobs

Scheduled functions and actions have no ambient superuser permission. Each job
stores its source identity and scope, then revalidates membership, ownership,
and source lifecycle immediately before every write.

## Context assembly

The client does not author a trusted system prompt.

For each Ask request:

1. Convex verifies the asking user's active membership.
2. Convex verifies that the selected persona is usable in the active workspace.
3. Convex loads compact active persona records.
4. Convex retrieves only relevant context chunks from the active workspace.
5. Convex loads the current private conversation first.
6. Convex may retrieve relevant messages from earlier private conversations
   between the same asking user and selected persona, with lower weight than the
   current conversation.
7. Convex excludes the asking user's own persona records and conversations with
   other personas when a different persona is selected.
8. Convex creates a short-lived, single-use request ticket containing or
   referencing the trusted context payload.
9. The Cloudflare Worker validates that ticket and streams the provider
   response.
10. The response records source IDs and usage without retaining screenshots.

Long files, complete conversation archives, and all available evidence must not
be injected wholesale. Retrieval uses authorization, relevance, recency, source
type, and a strict context budget.

## Technical architecture

### macOS client

- SwiftUI and existing AppKit surfaces.
- Official Convex Swift client for reactive application data.
- Authentication credentials stored in Keychain.
- Explicit active workspace and selected persona.
- Local cache for responsiveness, never the authorization source of truth.
- Screen and microphone capture remain on-device.

### Convex control plane

- Profiles, workspaces, memberships, invitations, personas, suggestions,
  context metadata, conversations, and audit events.
- Transactional mutations and centralized authorization helpers.
- Vector indexes and ingestion jobs.
- Short-lived request-ticket issuance.

### Cloudflare streaming plane

- Anthropic SSE.
- ElevenLabs audio.
- AssemblyAI temporary tokens.
- Ticket validation, quotas, rate limits, model policy, provider credentials,
  and usage logging.

### Files

R2 is recommended for private or large workspace files because access can use
short-lived signed URLs. File metadata and authorization remain in Convex.

## Greenfield cutover

The production path does not migrate existing local data.

The following local systems are replaced rather than synchronized:

- `DashboardMockAuthState`
- `PersonaTasteFileStore` runtime reads and writes
- `TasteProfileStore`
- `TeamTasteProfileStore`
- `TeamContextStore`
- `DashboardChatHistoryStore`
- `DashboardRecordingHistoryStore`

`TASTE.md` and Soul text are not production runtime models. A human-readable
export format may be designed later, but it must be generated from structured
records.

Legacy code is removed only after its cloud replacement is operational and
verified.

## Required tests

### Invariants and concurrency

- Concurrent signup creates one profile, one personal workspace, one
  membership, and one persona.
- Personal workspace provisioning supplies a default name and leaves business
  context optional.
- Personal workspace invitation and second-membership attempts fail.
- Team workspace creation atomically creates its context profile, creator owner
  membership, and fresh persona without an invite.
- Concurrent invite acceptance creates one membership and one persona.
- Direct team-membership creation without atomically consuming a valid invite
  fails.
- A second persona for one membership fails.
- Cross-workspace persona and membership relationships fail.
- Client-supplied ownership and role fields cannot override derived values.
- Concurrent ownership transfer, demotion, removal, and deletion attempts
  cannot leave a team workspace without an owner.

### Authorization matrix

Every public operation is tested as:

- unauthenticated;
- unrelated authenticated user;
- active member;
- persona owner;
- workspace admin;
- workspace owner;
- removed member.

### Personas and learning

- Onboarding cannot activate a persona until work context and at least one
  communication preference are stored.
- Explicit owner onboarding answers create active, versioned records
  automatically with immutable answer provenance.
- The informational onboarding summary does not block activation.
- Skipping the deeper interview preserves active essentials and permits the
  owner to resume later.
- Another member cannot submit onboarding answers or alter setup progress.
- Only the owner may draft, approve, replace, or unpublish the teammate boundary
  summary.
- Teammates receive only the current approved summary while both memberships
  and the persona remain active; drafts, superseded summaries, private boundary
  records, and evidence remain inaccessible.
- Active members may use another active member's persona.
- Members, admins, and workspace owners cannot edit another member's persona.
- Non-owner use creates no suggestion or evidence.
- Owner use and owner Teach sessions may create suggestions.
- An owner using another member's persona trains neither persona.
- Suggestion sources with a different owner, persona, or workspace fail.
- Only the owner may approve or reject.
- Approval preserves immutable evidence provenance.
- Rejection removes evidence, embeddings, previews, queued artifacts, and
  storage objects.
- Delayed jobs cannot write after membership removal.

### Conversations

- Workspace roles cannot list or fetch another user's conversations.
- Direct-ID access does not reveal record existence.
- Removed personas make historical conversations read-only.
- Removed members retain only their own private read-only conversation history.
- Read-only history permits read, export, and delete but rejects message append
  and reply generation.
- Persona edits and removal do not change frozen snapshots.
- Rejoining creates new membership and persona IDs with no prior records,
  evidence, or suggestions.
- Retrieval may use lower-weight history only from conversations between the
  same asking user and selected persona; it excludes the asker's persona records
  and conversations with other personas.

### Workspace context and files

- Only active owners and admins may mutate context or files.
- Active members may consume context only within the workspace.
- Removed members cannot reuse cached file references.
- Cross-workspace file and vector-search access fails.

### Authentication and invitations

- Magic links expire, are single-use, and resist replay.
- Invitation acceptance requires the intended verified identity.
- Forwarded, expired, replayed, and already-consumed invitations fail.
- Admins may invite members and admins but cannot invite or grant owners.
- Google and magic-link identities resolve safely to one canonical user.
- Account-link collisions do not create duplicate personal workspaces.
- Admins cannot demote or remove owners.
- The last owner cannot leave or start deletion without transfer or explicit
  workspace deletion.

### Ephemeral screenshots

- Screenshot bytes are removed after successful requests and Teach analysis.
- Screenshot bytes are removed after failures, cancellation, retries, and
  process recovery.
- Screenshot content does not enter database rows, object storage, queues,
  vector indexes, previews, analytics, or logs.

### Deletion

- Account deletion signs the user out and locks access immediately.
- Verified email cancellation during the seven-day window restores access
  safely.
- Expired deletion purges account-owned data and private conversations.
- Removed members have no workspace access during or after account deletion.
- Membership removal purges the persona, records, evidence, suggestions,
  indexes, storage objects, and queued jobs while preserving independent frozen
  snapshots.
- Team-workspace deletion revokes all memberships and purges all workspace data,
  private workspace conversations, files, indexes, and pending jobs.
- Only an active owner may delete a team workspace; admins, members, removed
  users, and unrelated users are denied.
- Purged evidence is absent from storage, indexes, queues, and logs.

## Agent delivery model

One integrator owns the production contract and merges work. Implementation
agents receive one PR-sized outcome, explicit invariants, allowed files,
out-of-scope rules, required tests, and a definition of done.

Backend and macOS agents may work concurrently only after their shared contract
is frozen. No two agents edit `CompanionManager.swift` in parallel.

Each implementation slice follows:

1. read-only code exploration;
2. written API and acceptance contract;
3. isolated implementation branch or worktree;
4. targeted tests;
5. integrator review;
6. security review for auth, tenancy, file, or deletion changes;
7. final code review;
8. human macOS UX validation.

Best-of-N agents are reserved for uncertain spikes such as Swift
authentication integration or request-ticket streaming, not routine feature
implementation.

## Dependency-ordered PR roadmap

### PR 0 — Production foundation

- This contract.
- No backend or application behavior changes.

### PR 1 — Convex bootstrap

- Convex project and environments.
- Initial schema and authorization helper test harness.
- Deployment and secret-handling documentation.

### PR 2 — Authentication

- Google and email magic-link identity provider.
- Keychain-backed Swift session.
- Replace mock sign-in surfaces.

### PR 3 — Personal workspace provisioning

- Idempotent profile creation.
- Permanent personal workspace with a default name and optional business
  context, plus its owner membership and persona.
- Initial guided persona setup state.

### PR 4A — Convex request-ticket foundation (merged)

- Purpose-bound, short-lived, single-use tickets limited to onboarding chat,
  TTS, and transcription.
- Opaque 256-bit bearer returned once; only its digest and exact request-body
  binding are persisted.
- Owner-only authenticated issuance, atomic internal consumption, lifecycle
  revalidation, bounded quotas, and sanitized idempotent completion metadata.
- Hourly bounded cleanup that preserves issued quota rows through ticket expiry
  plus 24 hours, consumed tombstones for 24 hours, and audits for 30 days.
- Trusted provider policy is server-derived. No general Ask access or
  client-authored model, system prompt, voice, or output policy.
- No public Worker consume endpoint existed before service authentication.

### PR 4B — Worker routes and HMAC service bridge (merged)

- Timestamped HMAC service authentication from the Worker to Convex.
- Authenticated onboarding chat, TTS, and transcription Worker routes.
- Public HTTP consume and completion handlers that wrap the PR 4A internals.
- Exact Worker request-body binding, trusted provider policy, streaming, and
  sanitized completion reporting.

PR 4B does not change the native app or make it issue or redeem tickets.

### PR 4C — Native ticket client (current)

- Exact-body hashing in Swift, streaming integration, route closure, and
  removal of onboarding direct-provider paths.
- Native issuance and `Authorization: StickyTicket <opaque>` integration for
  onboarding chat, TTS, and transcription.
- Tests proving the native body bytes exactly match the issued ticket binding.
- No onboarding UI or production-data readiness unlock. Native transport remains
  unavailable until the separate development Worker is deployed and its HTTPS
  origin is supplied through ignored runtime configuration.

Production readiness stays locked throughout these slices.

### PR 5 — Voice-first conversational persona onboarding

- One adaptive voice-first conversation with text fallback.
- Automatic structured communication, judgment, expertise, and boundary
  records from the owner's explicit answers.
- Minimum activation threshold: work context plus one communication preference.
- Optional deeper interview, informational summary, and owner-approved teammate
  boundary summary.
- Owner-only edit, immutable provenance, and version APIs.
- Production data readiness remains locked until the remaining cloud data paths
  exist.

### PR 6 — Team workspaces and invitations

- Workspace creation atomically records the required name, business type, and
  initial context profile, creator owner membership, and fresh persona.
- Invite, accept, roles, member list, and removal.
- Fresh persona setup for every new membership.

### PR 7 — Workspace persona roster

- Reactive workspace member/persona list.
- Persona wheel and picker integration.
- Removed personas disappear immediately.

### PR 8 — Workspace context and files

- Business profile and brief.
- Owner/admin editing.
- R2 uploads, ingestion metadata, and authorized reads.

### PR 9 — Private cloud conversations

- Convex conversations and messages.
- User-only history.
- Frozen persona snapshots.
- Removed-member and unavailable-persona conversations become read-only.

### PR 10 — Context retrieval

- Extraction, chunking, embeddings, vector indexes, and provenance.
- Workspace-filtered retrieval and strict prompt budgets.

### PR 11 — Controlled persona learning

- Owner-interaction and Teach suggestion generation.
- Private review queue.
- Approval, rejection, evidence lifecycle, and persona versions.

### PR 12 — Production hardening

- Account deletion recovery and purge.
- Explicit team-workspace deletion and full data purge.
- Audit events, monitoring, backups, quotas, and abuse controls.
- Full tenant-isolation and lifecycle test suite.

### PR 13 — Legacy removal

- Remove mock auth and obsolete local stores.
- Remove `TASTE.md`, Soul, synthetic team persona, and dual-write runtime paths.
- Unify voice and chat prompt composition.

## Definition of done

The production conversion is complete when:

- every user has one permanent personal workspace;
- invite-only team membership works across devices;
- every membership has one user-owned persona;
- persona onboarding is a seamless voice-first conversation with text fallback
  and a skippable deeper interview;
- active members can use, but never train, one another's personas;
- only owners can edit and approve their own persona;
- workspace context is admin-managed and tenant-isolated;
- conversations are private and removed personas produce read-only history;
- persona learning is suggestion-based, owner-approved, and versioned;
- screenshots are ephemeral;
- all provider routes require authorized request tickets;
- local hackathon stores are absent from production hot paths;
- authorization and lifecycle tests pass for every public operation.
