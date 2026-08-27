import { ConvexError } from "convex/values";

import type { Doc, Id } from "./_generated/dataModel";
import type { MutationCtx, QueryCtx } from "./_generated/server";

export const maximumCurrentPersonaRecords = 64;
export const maximumOnboardingTurns = 128;
export const maximumSessionOperationReceipts = 256;
export const maximumNonterminalSessionOperationReceipts =
  maximumSessionOperationReceipts - 1;

type PersonaCtx = Pick<QueryCtx | MutationCtx, "db">;
type RecordContent = NonNullable<Doc<"personaRecords">["content"]>;
type RecordSource = Doc<"personaRecords">["source"];

export type PersonaRecordChange =
  | {
      operation: "create";
      content: RecordContent;
      evidenceExcerpt?: string;
      confidence: number;
    }
  | {
      operation: "update";
      recordKey: string;
      content: RecordContent;
      evidenceExcerpt?: string;
      confidence: number;
    }
  | {
      operation: "delete";
      recordKey: string;
      evidenceExcerpt?: string;
      confidence: number;
    };

export function failPersona(
  code:
    | "INVALID_REQUEST"
    | "RESOURCE_UNAVAILABLE"
    | "DATA_INTEGRITY"
    | "REVISION_CONFLICT"
    | "VERSION_CONFLICT"
    | "IDEMPOTENCY_CONFLICT"
    | "SETUP_COMPLETE"
    | "MINIMUM_REQUIRED",
  message: string,
): never {
  throw new ConvexError({ code, message });
}

export function assertSafeInteger(
  value: number,
  field: string,
  minimum = 0,
): void {
  if (!Number.isSafeInteger(value) || value < minimum) {
    return failPersona("INVALID_REQUEST", `${field} is invalid`);
  }
}

export function assertExternalId(value: string, field: string): void {
  if (
    value.length > 128 ||
    !/^[A-Za-z0-9._:-]{1,128}$/.test(value)
  ) {
    return failPersona("INVALID_REQUEST", `${field} is invalid`);
  }
}

export function normalizeBoundedText(
  value: string,
  field: string,
  maximumBytes: number,
): string {
  const normalized = value.trim();
  if (
    normalized.length === 0 ||
    /[\u0000-\u001f\u007f]/u.test(normalized) ||
    new TextEncoder().encode(normalized).byteLength > maximumBytes
  ) {
    return failPersona("INVALID_REQUEST", `${field} is invalid`);
  }
  return normalized;
}

function canonicalize(value: unknown): string {
  if (value === null || typeof value !== "object") {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map(canonicalize).join(",")}]`;
  }
  const objectValue = value as Record<string, unknown>;
  return `{${Object.keys(objectValue)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${canonicalize(objectValue[key])}`)
    .join(",")}}`;
}

export async function createRequestFingerprint(value: unknown): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(canonicalize(value)),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function isRequestFingerprint(value: string): boolean {
  return /^[0-9a-f]{64}$/.test(value);
}

export function assertConfidence(confidence: number): void {
  if (!Number.isFinite(confidence) || confidence < 0 || confidence > 1) {
    return failPersona("INVALID_REQUEST", "Confidence is invalid");
  }
}

export function normalizeContent(content: RecordContent): RecordContent {
  const statement = normalizeBoundedText(
    content.statement,
    "Record statement",
    500,
  );
  return content.kind === "boundary"
    ? { kind: content.kind, mode: content.mode, statement }
    : { kind: content.kind, statement };
}

export async function loadCurrentRecords(
  ctx: PersonaCtx,
  personaId: Id<"personas">,
): Promise<Doc<"personaRecords">[]> {
  const records = await ctx.db
    .query("personaRecords")
    .withIndex(
      "by_personaId_and_isCurrent_and_state_and_kind",
      (indexQuery) => indexQuery.eq("personaId", personaId).eq("isCurrent", true),
    )
    .take(maximumCurrentPersonaRecords + 1);
  if (records.length > maximumCurrentPersonaRecords) {
    return failPersona("DATA_INTEGRITY", "Persona record limit exceeded");
  }
  for (const record of records) {
    if (
      record.personaId !== personaId ||
      (record.state === "active" && record.content === undefined) ||
      (record.state === "tombstone" && record.deletedKind === undefined)
    ) {
      return failPersona("DATA_INTEGRITY", "Persona record is malformed");
    }
  }
  return records;
}

export function minimumReadiness(records: Doc<"personaRecords">[]): {
  hasWorkContext: boolean;
  hasCommunicationPreference: boolean;
  isMet: boolean;
} {
  const hasWorkContext = records.some(
    (record) => record.state === "active" && record.kind === "work_context",
  );
  const hasCommunicationPreference = records.some(
    (record) =>
      record.state === "active" &&
      record.kind === "communication_preference",
  );
  return {
    hasWorkContext,
    hasCommunicationPreference,
    isMet: hasWorkContext && hasCommunicationPreference,
  };
}

function isSafeNonnegativeInteger(value: number): boolean {
  return Number.isSafeInteger(value) && value >= 0;
}

function validStoredText(value: string, maximumBytes: number): boolean {
  return (
    value === value.trim() &&
    value.length > 0 &&
    !/[\u0000-\u001f\u007f]/u.test(value) &&
    new TextEncoder().encode(value).byteLength <= maximumBytes
  );
}

function validExternalId(value: string): boolean {
  return /^[A-Za-z0-9._:-]{1,128}$/.test(value);
}

function validateRelationship(
  child: {
    personaId: Id<"personas">;
    membershipId: Id<"workspaceMembers">;
    workspaceId: Id<"workspaces">;
    ownerUserId: Id<"profiles">;
  },
  persona: Doc<"personas">,
): void {
  if (
    child.personaId !== persona._id ||
    child.membershipId !== persona.membershipId ||
    child.workspaceId !== persona.workspaceId ||
    child.ownerUserId !== persona.ownerUserId
  ) {
    return failPersona("DATA_INTEGRITY", "Persona child relationship is invalid");
  }
}

export type ValidatedPersonaSetupGraph = {
  session: Doc<"personaOnboardingSessions"> | null;
  turns: Doc<"personaOnboardingTurns">[];
  records: Doc<"personaRecords">[];
  readiness: ReturnType<typeof minimumReadiness>;
};

export function validateBoundarySummaryDocument(
  summary: Doc<"personaBoundarySummaries">,
  persona: Doc<"personas">,
): void {
  validateRelationship(summary, persona);
  if (
    !validStoredText(summary.summaryText, 500) ||
    !isSafeNonnegativeInteger(summary.sourceVersionNumber) ||
    summary.sourceVersionNumber < 1 ||
    summary.sourceVersionNumber > persona.currentVersion ||
    !validExternalId(summary.clientMutationId) ||
    !isRequestFingerprint(summary.requestFingerprint) ||
    !isSafeNonnegativeInteger(summary.createdAt) ||
    (summary.state === "draft" &&
      (summary.approvedAt !== undefined ||
        summary.supersededAt !== undefined ||
        summary.unpublishedAt !== undefined)) ||
    (summary.state === "approved" &&
      (summary.approvedAt === undefined ||
        summary.approvalClientMutationId === undefined ||
        !validExternalId(summary.approvalClientMutationId) ||
        summary.approvalRequestFingerprint === undefined ||
        !isRequestFingerprint(summary.approvalRequestFingerprint) ||
        summary.supersededAt !== undefined ||
        summary.unpublishedAt !== undefined)) ||
    (summary.state === "superseded" && summary.supersededAt === undefined) ||
    (summary.state === "unpublished" &&
      (summary.approvedAt === undefined ||
        summary.unpublishedAt === undefined ||
        summary.unpublishClientMutationId === undefined ||
        !validExternalId(summary.unpublishClientMutationId) ||
        summary.unpublishRequestFingerprint === undefined ||
        !isRequestFingerprint(summary.unpublishRequestFingerprint)))
  ) {
    return failPersona("DATA_INTEGRITY", "Boundary summary is malformed");
  }
}

export async function validatePersonaSetupGraph(
  ctx: PersonaCtx,
  persona: Doc<"personas">,
): Promise<ValidatedPersonaSetupGraph> {
  if (
    !isSafeNonnegativeInteger(persona.currentVersion) ||
    (persona.activatedAt !== undefined &&
      !isSafeNonnegativeInteger(persona.activatedAt))
  ) {
    return failPersona("DATA_INTEGRITY", "Persona counters are invalid");
  }
  const sessions = await ctx.db
    .query("personaOnboardingSessions")
    .withIndex("by_personaId", (indexQuery) =>
      indexQuery.eq("personaId", persona._id),
    )
    .take(2);
  if (sessions.length > 1) {
    return failPersona("DATA_INTEGRITY", "Multiple onboarding sessions exist");
  }
  const session = sessions[0] ?? null;
  if (session !== null) {
    validateRelationship(session, persona);
    if (
      !isSafeNonnegativeInteger(session.revision) ||
      !isSafeNonnegativeInteger(session.turnCount) ||
      !isSafeNonnegativeInteger(session.nextSequence) ||
      session.turnCount !== session.nextSequence ||
      session.turnCount > maximumOnboardingTurns ||
      !isSafeNonnegativeInteger(session.startedAt) ||
      !isSafeNonnegativeInteger(session.updatedAt)
    ) {
      return failPersona("DATA_INTEGRITY", "Onboarding session counters are invalid");
    }
  }

  const turns =
    session === null
      ? []
      : await ctx.db
          .query("personaOnboardingTurns")
          .withIndex("by_sessionId_and_sequence", (indexQuery) =>
            indexQuery.eq("sessionId", session._id),
          )
          .take(maximumOnboardingTurns + 1);
  if (
    turns.length > maximumOnboardingTurns ||
    (session !== null && turns.length !== session.turnCount)
  ) {
    return failPersona("DATA_INTEGRITY", "Onboarding turn count is invalid");
  }
  const seenTurnIds = new Set<string>();
  const seenTurnMutationIds = new Set<string>();
  for (let index = 0; index < turns.length; index += 1) {
    const turn = turns[index];
    validateRelationship(turn, persona);
    if (
      session === null ||
      turn.sessionId !== session._id ||
      turn.sequence !== index ||
      !isSafeNonnegativeInteger(turn.createdAt) ||
      !validExternalId(turn.turnId) ||
      !validExternalId(turn.clientMutationId) ||
      !validStoredText(turn.text, turn.speaker === "owner" ? 2_000 : 4_096) ||
      seenTurnIds.has(turn.turnId) ||
      seenTurnMutationIds.has(turn.clientMutationId)
    ) {
      return failPersona("DATA_INTEGRITY", "Onboarding turn is malformed");
    }
    seenTurnIds.add(turn.turnId);
    seenTurnMutationIds.add(turn.clientMutationId);
    if (
      turn.speaker === "owner"
        ? turn.kind !== "answer" ||
          turn.inputMode === undefined ||
          turn.interpretationStatus === undefined ||
          (turn.interpretationStatus === "pending" &&
            (turn.interpretationClientMutationId !== undefined ||
              turn.interpretationRequestFingerprint !== undefined ||
              turn.interpretedVersionId !== undefined)) ||
          (turn.interpretationStatus === "applied" &&
            (turn.interpretationClientMutationId === undefined ||
              turn.interpretationRequestFingerprint === undefined ||
              !isRequestFingerprint(turn.interpretationRequestFingerprint)))
        : turn.kind === "answer" ||
          turn.inputMode !== undefined ||
          turn.interpretationStatus !== undefined ||
          turn.interpretationClientMutationId !== undefined ||
          turn.interpretationRequestFingerprint !== undefined ||
          turn.interpretedVersionId !== undefined
    ) {
      return failPersona("DATA_INTEGRITY", "Onboarding turn state is malformed");
    }
  }
  const operationReceipts =
    session === null
      ? []
      : await ctx.db
          .query("personaSessionOperationReceipts")
          .withIndex("by_sessionId_and_clientMutationId", (indexQuery) =>
            indexQuery.eq("sessionId", session._id),
          )
          .take(maximumSessionOperationReceipts + 1);
  if (operationReceipts.length > maximumSessionOperationReceipts) {
    return failPersona("DATA_INTEGRITY", "Operation receipt limit exceeded");
  }
  const receiptMutationIds = new Set<string>();
  for (const receipt of operationReceipts) {
    validateRelationship(receipt, persona);
    if (
      session === null ||
      receipt.sessionId !== session._id ||
      receiptMutationIds.has(receipt.clientMutationId) ||
      !validExternalId(receipt.clientMutationId) ||
      !isRequestFingerprint(receipt.requestFingerprint) ||
      !isSafeNonnegativeInteger(receipt.resultRevision) ||
      receipt.resultRevision > session.revision ||
      ((receipt.operation === "start" || receipt.operation === "resume") &&
        receipt.resultStatus !== "active") ||
      (receipt.operation === "pause" &&
        receipt.resultStatus !== "paused") ||
      (receipt.operation === "complete" &&
        (receipt.resultStatus !== "completed" ||
          receipt.resultSetupState !== "complete")) ||
      !isSafeNonnegativeInteger(receipt.createdAt)
    ) {
      return failPersona("DATA_INTEGRITY", "Operation receipt is malformed");
    }
    receiptMutationIds.add(receipt.clientMutationId);
  }

  const records = await loadCurrentRecords(ctx, persona._id);
  const recordKeys = new Set<string>();
  for (const record of records) {
    validateRelationship(record, persona);
    if (
      !record.isCurrent ||
      recordKeys.has(record.recordKey) ||
      !validExternalId(record.recordKey) ||
      !isSafeNonnegativeInteger(record.versionNumber) ||
      record.versionNumber < 1 ||
      record.versionNumber > persona.currentVersion ||
      !Number.isFinite(record.confidence) ||
      record.confidence < 0 ||
      record.confidence > 1 ||
      !isSafeNonnegativeInteger(record.createdAt)
    ) {
      return failPersona("DATA_INTEGRITY", "Persona record is malformed");
    }
    recordKeys.add(record.recordKey);
    if (
      (record.state === "active" &&
        (record.content === undefined ||
          record.deletedKind !== undefined ||
          record.content.kind !== record.kind)) ||
      (record.state === "tombstone" &&
        (record.content !== undefined || record.deletedKind !== record.kind)) ||
      record.state === "superseded" ||
      record.supersededAt !== undefined ||
      record.supersededByRecordId !== undefined
    ) {
      return failPersona("DATA_INTEGRITY", "Current record state is malformed");
    }
    if (
      record.content !== undefined &&
      (!validStoredText(record.content.statement, 500) ||
        (record.content.kind === "boundary" && record.content.mode === undefined))
    ) {
      return failPersona("DATA_INTEGRITY", "Record content is malformed");
    }
    const version = await ctx.db.get("personaVersions", record.versionId);
    if (version === null) {
      return failPersona("DATA_INTEGRITY", "Record version is unavailable");
    }
    validateRelationship(version, persona);
    if (
      version.versionNumber !== record.versionNumber ||
      version.previousVersionNumber !== version.versionNumber - 1 ||
      !validExternalId(version.clientMutationId) ||
      !isSafeNonnegativeInteger(version.createdAt) ||
      !isSafeNonnegativeInteger(version.changeCount) ||
      version.changeCount < 1 ||
      version.changeCount > 16 ||
      (version.source.kind === "onboarding_answer" &&
        version.changeCount > 8) ||
      !isRequestFingerprint(version.requestFingerprint)
    ) {
      return failPersona("DATA_INTEGRITY", "Persona version is malformed");
    }
    if (version.source.kind === "onboarding_answer") {
      const sourceTurn = await ctx.db.get(
        "personaOnboardingTurns",
        version.source.sourceTurnId,
      );
      if (
        session === null ||
        version.source.sessionId !== session._id ||
        sourceTurn === null ||
        sourceTurn.sessionId !== session._id ||
        sourceTurn.personaId !== persona._id ||
        sourceTurn.speaker !== "owner" ||
        sourceTurn.interpretationStatus !== "applied" ||
        sourceTurn.interpretedVersionId !== version._id ||
        sourceTurn.interpretationRequestFingerprint !==
          version.requestFingerprint ||
        record.source.kind !== "onboarding_explicit_answer" ||
        record.source.sessionId !== session._id ||
        record.source.sourceTurnId !== sourceTurn._id ||
        record.source.sourceClientTurnId !== sourceTurn.turnId ||
        !validStoredText(record.source.evidenceExcerpt, 280) ||
        !sourceTurn.text.includes(record.source.evidenceExcerpt)
      ) {
        return failPersona("DATA_INTEGRITY", "Onboarding provenance is malformed");
      }
    } else if (record.source.kind !== "manual_owner_edit") {
      return failPersona("DATA_INTEGRITY", "Manual provenance is malformed");
    }
  }

  if (persona.currentVersion > 0) {
    const currentVersions = await ctx.db
      .query("personaVersions")
      .withIndex("by_personaId_and_versionNumber", (indexQuery) =>
        indexQuery
          .eq("personaId", persona._id)
          .eq("versionNumber", persona.currentVersion),
      )
      .take(2);
    if (currentVersions.length !== 1) {
      return failPersona("DATA_INTEGRITY", "Current persona version is invalid");
    }
    validateRelationship(currentVersions[0], persona);
  }

  const readiness = minimumReadiness(records);
  const invalidSessionState =
    session !== null &&
    ((session.status === "active" &&
      (session.pauseReason !== undefined ||
        session.pausedAt !== undefined ||
        session.completedAt !== undefined)) ||
      (session.status === "paused" &&
        (session.pauseReason === undefined ||
          session.pausedAt === undefined ||
          session.completedAt !== undefined ||
          !isSafeNonnegativeInteger(session.pausedAt))) ||
      (session.status === "completed" &&
        (session.pauseReason !== undefined ||
          session.pausedAt !== undefined ||
          session.completedAt === undefined ||
          !isSafeNonnegativeInteger(session.completedAt))));
  if (
    invalidSessionState ||
    (persona.setupState === "notStarted" &&
      (session !== null ||
        records.length !== 0 ||
        persona.currentVersion !== 0 ||
        persona.activatedAt !== undefined)) ||
    (persona.setupState === "essentials" &&
      (session === null ||
        session.status === "completed" ||
        readiness.isMet ||
        persona.activatedAt !== undefined)) ||
    (persona.setupState === "interview" &&
      (session === null ||
        session.status === "completed" ||
        !readiness.isMet ||
        persona.activatedAt === undefined)) ||
    (persona.setupState === "complete" &&
      (session === null ||
        session.status !== "completed" ||
        !readiness.isMet ||
        persona.activatedAt === undefined))
  ) {
    return failPersona("DATA_INTEGRITY", "Persona setup graph is malformed");
  }
  return { session, turns, records, readiness };
}

async function invalidateApprovedBoundarySummary(
  ctx: MutationCtx,
  persona: Doc<"personas">,
  timestamp: number,
): Promise<void> {
  const approved = await ctx.db
    .query("personaBoundarySummaries")
    .withIndex("by_personaId_and_state", (indexQuery) =>
      indexQuery.eq("personaId", persona._id).eq("state", "approved"),
    )
    .take(2);
  if (approved.length > 1) {
    return failPersona("DATA_INTEGRITY", "Multiple approved summaries exist");
  }
  if (approved[0] !== undefined) {
    validateBoundarySummaryDocument(approved[0], persona);
    await ctx.db.patch("personaBoundarySummaries", approved[0]._id, {
      state: "superseded",
      supersededAt: timestamp,
    });
  }
}

export async function applyPersonaRecordChanges(
  ctx: MutationCtx,
  graph: {
    persona: Doc<"personas">;
    membership: Doc<"workspaceMembers">;
    profile: Doc<"profiles">;
  },
  expectedPersonaVersion: number,
  clientMutationId: string,
  source:
    | {
        kind: "onboarding_answer";
        sessionId: Id<"personaOnboardingSessions">;
        sourceTurn: Doc<"personaOnboardingTurns">;
      }
    | { kind: "manual_owner_edit" },
  changes: PersonaRecordChange[],
): Promise<{
  versionId: Id<"personaVersions">;
  versionNumber: number;
  activatedAt: number | null;
}> {
  assertExternalId(clientMutationId, "Client mutation ID");
  assertSafeInteger(expectedPersonaVersion, "Expected persona version");
  if (changes.length < 1 || changes.length > 16) {
    return failPersona("INVALID_REQUEST", "Change count is invalid");
  }
  const changedKeys = new Set<string>();
  const normalizedRequestChanges = changes.map((change) => {
    assertConfidence(change.confidence);
    const recordKey =
      change.operation === "create" ? undefined : change.recordKey;
    if (recordKey !== undefined) {
      assertExternalId(recordKey, "Record key");
      if (changedKeys.has(recordKey)) {
        return failPersona("INVALID_REQUEST", "Duplicate record operation");
      }
      changedKeys.add(recordKey);
    }
    const evidenceExcerpt =
      source.kind === "onboarding_answer"
        ? normalizeBoundedText(
            change.evidenceExcerpt ?? "",
            "Evidence excerpt",
            280,
          )
        : undefined;
    if (source.kind === "manual_owner_edit" && change.evidenceExcerpt !== undefined) {
      return failPersona("INVALID_REQUEST", "Manual edits cannot cite evidence");
    }
    return change.operation === "delete"
      ? { ...change, evidenceExcerpt }
      : {
          ...change,
          content: normalizeContent(change.content),
          evidenceExcerpt,
        };
  });
  const requestFingerprint = await createRequestFingerprint({
    operation:
      source.kind === "onboarding_answer"
        ? "apply_owner_turn_interpretation"
        : "apply_owned_changes",
    personaId: graph.persona._id,
    sessionId:
      source.kind === "onboarding_answer" ? source.sessionId : null,
    sourceTurnId:
      source.kind === "onboarding_answer" ? source.sourceTurn._id : null,
    expectedPersonaVersion,
    changes: normalizedRequestChanges,
  });
  const validatedGraph = await validatePersonaSetupGraph(ctx, graph.persona);
  const existingVersion = await ctx.db
    .query("personaVersions")
    .withIndex("by_personaId_and_clientMutationId", (indexQuery) =>
      indexQuery
        .eq("personaId", graph.persona._id)
        .eq("clientMutationId", clientMutationId),
    )
    .unique();
  if (existingVersion !== null) {
    if (
      existingVersion.personaId !== graph.persona._id ||
      existingVersion.membershipId !== graph.membership._id ||
      existingVersion.workspaceId !== graph.persona.workspaceId ||
      existingVersion.ownerUserId !== graph.profile._id ||
      existingVersion.requestFingerprint !== requestFingerprint ||
      existingVersion.source.kind !== source.kind ||
      (source.kind === "onboarding_answer" &&
        (existingVersion.source.kind !== "onboarding_answer" ||
          existingVersion.source.sessionId !== source.sessionId ||
          existingVersion.source.sourceTurnId !== source.sourceTurn._id))
    ) {
      return failPersona("IDEMPOTENCY_CONFLICT", "Mutation ID was reused");
    }
    return {
      versionId: existingVersion._id,
      versionNumber: existingVersion.versionNumber,
      activatedAt: graph.persona.activatedAt ?? null,
    };
  }

  if (graph.persona.currentVersion !== expectedPersonaVersion) {
    return failPersona("VERSION_CONFLICT", "Persona version changed");
  }
  const currentRecords = validatedGraph.records;
  const recordsByKey = new Map(
    currentRecords.map((record) => [record.recordKey, record]),
  );
  let currentRecordCount = currentRecords.length;
  let boundaryChanged = false;
  const normalizedChanges = normalizedRequestChanges.map((change) => {
    if (source.kind === "onboarding_answer") {
      if (!source.sourceTurn.text.includes(change.evidenceExcerpt!)) {
        return failPersona(
          "INVALID_REQUEST",
          "Evidence must be an exact owner-answer substring",
        );
      }
    }

    if (change.operation === "create") {
      currentRecordCount += 1;
      const content = change.content;
      boundaryChanged ||= content.kind === "boundary";
      return { ...change, content };
    }
    const priorRecord = recordsByKey.get(change.recordKey);
    if (priorRecord === undefined || priorRecord.state !== "active") {
      return failPersona("RESOURCE_UNAVAILABLE", "Record unavailable");
    }
    if (change.operation === "delete") {
      boundaryChanged ||= priorRecord.kind === "boundary";
      return { ...change, priorRecord };
    }
    const content = change.content;
    if (
      priorRecord.kind === content.kind &&
      JSON.stringify(priorRecord.content) === JSON.stringify(content)
    ) {
      return failPersona("INVALID_REQUEST", "Record update is a no-op");
    }
    boundaryChanged ||=
      priorRecord.kind === "boundary" || content.kind === "boundary";
    return { ...change, content, priorRecord };
  });

  if (currentRecordCount > maximumCurrentPersonaRecords) {
    return failPersona("INVALID_REQUEST", "Persona record limit exceeded");
  }

  const timestamp = Date.now();
  const versionNumber = graph.persona.currentVersion + 1;
  const versionId = await ctx.db.insert("personaVersions", {
    personaId: graph.persona._id,
    membershipId: graph.membership._id,
    workspaceId: graph.persona.workspaceId,
    ownerUserId: graph.profile._id,
    versionNumber,
    previousVersionNumber: graph.persona.currentVersion,
    clientMutationId,
    requestFingerprint,
    source:
      source.kind === "onboarding_answer"
        ? {
            kind: "onboarding_answer",
            sessionId: source.sessionId,
            sourceTurnId: source.sourceTurn._id,
          }
        : { kind: "manual_owner_edit" },
    changeCount: changes.length,
    createdAt: timestamp,
  });

  for (let index = 0; index < normalizedChanges.length; index += 1) {
    const change = normalizedChanges[index];
    const priorRecord =
      "priorRecord" in change ? change.priorRecord : undefined;
    const kind =
      change.operation === "delete"
        ? priorRecord!.kind
        : change.content.kind;
    const recordKey =
      change.operation === "create"
        ? `r${versionNumber}:${index}`
        : change.recordKey;
    const recordSource: RecordSource =
      source.kind === "onboarding_answer"
        ? {
            kind: "onboarding_explicit_answer",
            sessionId: source.sessionId,
            sourceTurnId: source.sourceTurn._id,
            sourceClientTurnId: source.sourceTurn.turnId,
            evidenceExcerpt: change.evidenceExcerpt!,
          }
        : { kind: "manual_owner_edit" };
    const newRecordId = await ctx.db.insert("personaRecords", {
      personaId: graph.persona._id,
      membershipId: graph.membership._id,
      workspaceId: graph.persona.workspaceId,
      ownerUserId: graph.profile._id,
      recordKey,
      versionId,
      versionNumber,
      kind,
      state: change.operation === "delete" ? "tombstone" : "active",
      isCurrent: true,
      content: change.operation === "delete" ? undefined : change.content,
      deletedKind: change.operation === "delete" ? kind : undefined,
      source: recordSource,
      confidence: change.confidence,
      createdAt: timestamp,
    });
    if (priorRecord !== undefined) {
      await ctx.db.patch("personaRecords", priorRecord._id, {
        state: "superseded",
        isCurrent: false,
        supersededAt: timestamp,
        supersededByRecordId: newRecordId,
      });
      recordsByKey.set(recordKey, (await ctx.db.get("personaRecords", newRecordId))!);
    }
  }

  const resultingRecords = await loadCurrentRecords(ctx, graph.persona._id);
  const readiness = minimumReadiness(resultingRecords);
  if (graph.persona.activatedAt !== undefined && !readiness.isMet) {
    return failPersona(
      "MINIMUM_REQUIRED",
      "Activated personas must preserve minimum records",
    );
  }
  const activatedAt =
    graph.persona.activatedAt ?? (readiness.isMet ? timestamp : undefined);
  await ctx.db.patch("personas", graph.persona._id, {
    currentVersion: versionNumber,
    setupState:
      graph.persona.setupState === "essentials" && readiness.isMet
        ? "interview"
        : graph.persona.setupState,
    activatedAt,
    updatedAt: timestamp,
  });
  if (boundaryChanged) {
    await invalidateApprovedBoundarySummary(ctx, graph.persona, timestamp);
  }
  return {
    versionId,
    versionNumber,
    activatedAt: activatedAt ?? null,
  };
}
