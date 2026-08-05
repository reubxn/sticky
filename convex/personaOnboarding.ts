import {
  paginationOptsValidator,
  paginationResultValidator,
} from "convex/server";
import { v } from "convex/values";

import type { Doc } from "./_generated/dataModel";
import { mutation, query } from "./_generated/server";
import type { MutationCtx, QueryCtx } from "./_generated/server";
import { requireIdentity, requirePersonaOwner } from "./authorization";
import {
  applyPersonaRecordChanges,
  assertConfidence,
  assertExternalId,
  assertSafeInteger,
  createRequestFingerprint,
  failPersona,
  loadCurrentRecords,
  maximumOnboardingTurns,
  maximumNonterminalSessionOperationReceipts,
  maximumSessionOperationReceipts,
  minimumReadiness,
  normalizeBoundedText,
  normalizeContent,
  validatePersonaSetupGraph,
} from "./personaFoundation";
import {
  personaOnboardingInputModeValidator,
  personaOnboardingPauseReasonValidator,
  personaOnboardingSessionStatusValidator,
  personaOnboardingTurnKindValidator,
  personaRecordContentValidator,
  personaRecordKindValidator,
  personaRecordSourceValidator,
  personaRecordStateValidator,
  personaSetupStateValidator,
} from "./validators";

const relationshipFields = {
  membershipId: v.id("workspaceMembers"),
  workspaceId: v.id("workspaces"),
  ownerUserId: v.id("profiles"),
};

const sessionProjectionValidator = v.object({
  sessionId: v.id("personaOnboardingSessions"),
  status: personaOnboardingSessionStatusValidator,
  pauseReason: v.union(personaOnboardingPauseReasonValidator, v.null()),
  revision: v.number(),
  turnCount: v.number(),
  startedAt: v.number(),
  updatedAt: v.number(),
  completedAt: v.union(v.number(), v.null()),
});

const recordProjectionValidator = v.object({
  recordId: v.id("personaRecords"),
  recordKey: v.string(),
  versionNumber: v.number(),
  kind: personaRecordKindValidator,
  state: personaRecordStateValidator,
  content: v.union(personaRecordContentValidator, v.null()),
  source: personaRecordSourceValidator,
  confidence: v.number(),
  createdAt: v.number(),
});

const ownedStateValidator = v.object({
  personaId: v.id("personas"),
  setupState: personaSetupStateValidator,
  currentVersion: v.number(),
  activatedAt: v.union(v.number(), v.null()),
  minimumReadiness: v.object({
    hasWorkContext: v.boolean(),
    hasCommunicationPreference: v.boolean(),
    isMet: v.boolean(),
  }),
  session: v.union(sessionProjectionValidator, v.null()),
  currentRecords: v.array(recordProjectionValidator),
});

const turnDocumentValidator = v.object({
  _id: v.id("personaOnboardingTurns"),
  _creationTime: v.number(),
  sessionId: v.id("personaOnboardingSessions"),
  personaId: v.id("personas"),
  ...relationshipFields,
  turnId: v.string(),
  clientMutationId: v.string(),
  sequence: v.number(),
  speaker: v.union(v.literal("owner"), v.literal("sticky")),
  kind: personaOnboardingTurnKindValidator,
  text: v.string(),
  inputMode: v.optional(personaOnboardingInputModeValidator),
  interpretationStatus: v.optional(
    v.union(v.literal("pending"), v.literal("applied")),
  ),
  interpretationClientMutationId: v.optional(v.string()),
  interpretationRequestFingerprint: v.optional(v.string()),
  interpretedVersionId: v.optional(v.id("personaVersions")),
  createdAt: v.number(),
});

const sessionMutationResultValidator = v.object({
  sessionId: v.id("personaOnboardingSessions"),
  status: personaOnboardingSessionStatusValidator,
  revision: v.number(),
  setupState: personaSetupStateValidator,
});

async function loadOwnedSession(
  ctx: QueryCtx | MutationCtx,
  sessionId: Doc<"personaOnboardingSessions">["_id"],
) {
  const identity = await requireIdentity(ctx);
  const profiles = await ctx.db
    .query("profiles")
    .withIndex("by_tokenIdentifier", (indexQuery) =>
      indexQuery.eq("tokenIdentifier", identity.tokenIdentifier),
    )
    .take(2);
  if (profiles.length !== 1 || profiles[0].lifecycleStatus !== "active") {
    return failPersona("RESOURCE_UNAVAILABLE", "Resource unavailable");
  }
  const profile = profiles[0];
  const session = await ctx.db.get("personaOnboardingSessions", sessionId);
  if (session === null) {
    return failPersona("RESOURCE_UNAVAILABLE", "Resource unavailable");
  }
  const persona = await ctx.db.get("personas", session.personaId);
  const membership =
    persona === null
      ? null
      : await ctx.db.get("workspaceMembers", persona.membershipId);
  const workspace =
    persona === null ? null : await ctx.db.get("workspaces", persona.workspaceId);
  if (
    persona === null ||
    persona.status !== "active" ||
    persona.ownerUserId !== profile._id ||
    membership === null ||
    membership.status !== "active" ||
    membership.userId !== profile._id ||
    membership.workspaceId !== persona.workspaceId ||
    workspace === null ||
    workspace.lifecycleStatus !== "active" ||
    session.membershipId !== membership._id ||
    session.workspaceId !== persona.workspaceId ||
    session.ownerUserId !== profile._id
  ) {
    return failPersona("RESOURCE_UNAVAILABLE", "Resource unavailable");
  }
  const validated = await validatePersonaSetupGraph(ctx, persona);
  if (validated.session?._id !== session._id) {
    return failPersona("RESOURCE_UNAVAILABLE", "Resource unavailable");
  }
  const graph = { profile, membership, persona };
  return { session, graph };
}

async function loadOnlySessionForPersona(
  ctx: QueryCtx | MutationCtx,
  personaId: Doc<"personas">["_id"],
) {
  const sessions = await ctx.db
    .query("personaOnboardingSessions")
    .withIndex("by_personaId", (indexQuery) =>
      indexQuery.eq("personaId", personaId),
    )
    .take(2);
  if (sessions.length > 1) {
    return failPersona("DATA_INTEGRITY", "Multiple onboarding sessions exist");
  }
  return sessions[0] ?? null;
}

async function loadSessionOperationReceipt(
  ctx: QueryCtx | MutationCtx,
  personaId: Doc<"personas">["_id"],
  clientMutationId: string,
  requestFingerprint: string,
) {
  const receipts = await ctx.db
    .query("personaSessionOperationReceipts")
    .withIndex("by_personaId_and_clientMutationId", (indexQuery) =>
      indexQuery
        .eq("personaId", personaId)
        .eq("clientMutationId", clientMutationId),
    )
    .take(2);
  if (receipts.length > 1) {
    return failPersona("DATA_INTEGRITY", "Duplicate operation receipts exist");
  }
  const receipt = receipts[0] ?? null;
  if (receipt !== null && receipt.requestFingerprint !== requestFingerprint) {
    return failPersona("IDEMPOTENCY_CONFLICT", "Mutation ID was reused");
  }
  return receipt;
}

async function insertSessionOperationReceipt(
  ctx: MutationCtx,
  graph: {
    profile: Doc<"profiles">;
    membership: Doc<"workspaceMembers">;
    persona: Doc<"personas">;
  },
  args: {
    sessionId: Doc<"personaOnboardingSessions">["_id"];
    clientMutationId: string;
    operation: "start" | "resume" | "pause" | "complete";
    requestFingerprint: string;
    resultStatus: "active" | "paused" | "completed";
    resultRevision: number;
    resultSetupState: Doc<"personas">["setupState"];
  },
): Promise<void> {
  const existingReceipts = await ctx.db
    .query("personaSessionOperationReceipts")
    .withIndex("by_sessionId_and_clientMutationId", (indexQuery) =>
      indexQuery.eq("sessionId", args.sessionId),
    )
    .take(maximumSessionOperationReceipts);
  if (existingReceipts.length >= maximumSessionOperationReceipts) {
    return failPersona("INVALID_REQUEST", "Operation receipt limit exceeded");
  }
  if (
    args.operation !== "complete" &&
    existingReceipts.length >= maximumNonterminalSessionOperationReceipts
  ) {
    return failPersona(
      "INVALID_REQUEST",
      "Nonterminal operation receipt limit exceeded",
    );
  }
  await ctx.db.insert("personaSessionOperationReceipts", {
    personaId: graph.persona._id,
    sessionId: args.sessionId,
    membershipId: graph.membership._id,
    workspaceId: graph.persona.workspaceId,
    ownerUserId: graph.profile._id,
    clientMutationId: args.clientMutationId,
    operation: args.operation,
    requestFingerprint: args.requestFingerprint,
    resultStatus: args.resultStatus,
    resultRevision: args.resultRevision,
    resultSetupState: args.resultSetupState,
    createdAt: Date.now(),
  });
}

function projectSessionReceipt(
  receipt: Doc<"personaSessionOperationReceipts">,
) {
  return {
    sessionId: receipt.sessionId,
    status: receipt.resultStatus,
    revision: receipt.resultRevision,
    setupState: receipt.resultSetupState,
  };
}

export const getOwnedState = query({
  args: { personaId: v.id("personas") },
  returns: ownedStateValidator,
  handler: async (ctx, args) => {
    const graph = await requirePersonaOwner(ctx, args.personaId);
    const validated = await validatePersonaSetupGraph(ctx, graph.persona);
    const { session, records, readiness } = validated;
    return {
      personaId: graph.persona._id,
      setupState: graph.persona.setupState,
      currentVersion: graph.persona.currentVersion,
      activatedAt: graph.persona.activatedAt ?? null,
      minimumReadiness: readiness,
      session:
        session === null
          ? null
          : {
              sessionId: session._id,
              status: session.status,
              pauseReason: session.pauseReason ?? null,
              revision: session.revision,
              turnCount: session.turnCount,
              startedAt: session.startedAt,
              updatedAt: session.updatedAt,
              completedAt: session.completedAt ?? null,
            },
      currentRecords: records.map((record) => ({
        recordId: record._id,
        recordKey: record.recordKey,
        versionNumber: record.versionNumber,
        kind: record.kind,
        state: record.state,
        content: record.content ?? null,
        source: record.source,
        confidence: record.confidence,
        createdAt: record.createdAt,
      })),
    };
  },
});

export const listOwnedTurns = query({
  args: {
    sessionId: v.id("personaOnboardingSessions"),
    paginationOpts: paginationOptsValidator,
  },
  returns: paginationResultValidator(turnDocumentValidator),
  handler: async (ctx, args) => {
    await loadOwnedSession(ctx, args.sessionId);
    return await ctx.db
      .query("personaOnboardingTurns")
      .withIndex("by_sessionId_and_sequence", (indexQuery) =>
        indexQuery.eq("sessionId", args.sessionId),
      )
      .paginate(args.paginationOpts);
  },
});

export const startOrResume = mutation({
  args: {
    personaId: v.id("personas"),
    clientMutationId: v.string(),
    expectedSessionRevision: v.number(),
  },
  returns: sessionMutationResultValidator,
  handler: async (ctx, args) => {
    assertExternalId(args.clientMutationId, "Client mutation ID");
    assertSafeInteger(args.expectedSessionRevision, "Expected session revision");
    const graph = await requirePersonaOwner(ctx, args.personaId);
    await validatePersonaSetupGraph(ctx, graph.persona);
    const existing = await loadOnlySessionForPersona(ctx, args.personaId);
    const operation = existing === null ? "start" as const : "resume" as const;
    const requestFingerprint = await createRequestFingerprint({
      operation: "start_or_resume",
      personaId: graph.persona._id,
      expectedSessionRevision: args.expectedSessionRevision,
    });
    const priorReceipt = await loadSessionOperationReceipt(
      ctx,
      graph.persona._id,
      args.clientMutationId,
      requestFingerprint,
    );
    if (priorReceipt !== null) {
      return projectSessionReceipt(priorReceipt);
    }
    if (graph.persona.setupState === "complete") {
      return failPersona("SETUP_COMPLETE", "Onboarding is complete");
    }
    const timestamp = Date.now();
    if (existing === null) {
      if (
        graph.persona.setupState !== "notStarted" ||
        graph.persona.activatedAt !== undefined ||
        graph.persona.currentVersion !== 0
      ) {
        return failPersona("DATA_INTEGRITY", "Persona setup state is malformed");
      }
      if (args.expectedSessionRevision !== 0) {
        return failPersona("REVISION_CONFLICT", "Session revision changed");
      }
      const sessionId = await ctx.db.insert("personaOnboardingSessions", {
        personaId: graph.persona._id,
        membershipId: graph.membership._id,
        workspaceId: graph.persona.workspaceId,
        ownerUserId: graph.profile._id,
        status: "active",
        revision: 0,
        turnCount: 0,
        nextSequence: 0,
        startedAt: timestamp,
        updatedAt: timestamp,
      });
      await ctx.db.patch("personas", graph.persona._id, {
        setupState: "essentials",
        updatedAt: timestamp,
      });
      await insertSessionOperationReceipt(ctx, graph, {
        sessionId,
        clientMutationId: args.clientMutationId,
        operation,
        requestFingerprint,
        resultStatus: "active",
        resultRevision: 0,
        resultSetupState: "essentials",
      });
      return {
        sessionId,
        status: "active" as const,
        revision: 0,
        setupState: "essentials" as const,
      };
    }
    if (
      existing.membershipId !== graph.membership._id ||
      existing.workspaceId !== graph.persona.workspaceId ||
      existing.ownerUserId !== graph.profile._id ||
      existing.status === "completed"
    ) {
      return failPersona("RESOURCE_UNAVAILABLE", "Resource unavailable");
    }
    if (args.expectedSessionRevision !== existing.revision) {
      return failPersona("REVISION_CONFLICT", "Session revision changed");
    }
    const revision = existing.status === "paused"
      ? existing.revision + 1
      : existing.revision;
    if (existing.status === "paused") {
      await ctx.db.patch("personaOnboardingSessions", existing._id, {
        status: "active",
        pauseReason: undefined,
        pausedAt: undefined,
        revision,
        updatedAt: timestamp,
      });
    }
    await insertSessionOperationReceipt(ctx, graph, {
      sessionId: existing._id,
      clientMutationId: args.clientMutationId,
      operation,
      requestFingerprint,
      resultStatus: "active",
      resultRevision: revision,
      resultSetupState: graph.persona.setupState,
    });
    return {
      sessionId: existing._id,
      status: "active" as const,
      revision,
      setupState: graph.persona.setupState,
    };
  },
});

async function appendTurn(
  ctx: MutationCtx,
  args: {
    sessionId: Doc<"personaOnboardingSessions">["_id"];
    expectedSessionRevision: number;
    turnId: string;
    clientMutationId: string;
    speaker: "owner" | "sticky";
    kind: Doc<"personaOnboardingTurns">["kind"];
    text: string;
    inputMode?: "voice" | "text";
  },
) {
  assertExternalId(args.turnId, "Turn ID");
  assertExternalId(args.clientMutationId, "Client mutation ID");
  assertSafeInteger(args.expectedSessionRevision, "Expected session revision");
  const text = normalizeBoundedText(
    args.text,
    "Turn text",
    args.speaker === "owner" ? 2_000 : 4_096,
  );
  const { session, graph } = await loadOwnedSession(ctx, args.sessionId);
  const byTurnId = await ctx.db
    .query("personaOnboardingTurns")
    .withIndex("by_sessionId_and_turnId", (indexQuery) =>
      indexQuery.eq("sessionId", session._id).eq("turnId", args.turnId),
    )
    .unique();
  const byMutationId = await ctx.db
    .query("personaOnboardingTurns")
    .withIndex("by_sessionId_and_clientMutationId", (indexQuery) =>
      indexQuery
        .eq("sessionId", session._id)
        .eq("clientMutationId", args.clientMutationId),
    )
    .unique();
  const existing = byTurnId ?? byMutationId;
  if (existing !== null) {
    if (
      byTurnId?._id !== byMutationId?._id ||
      existing.speaker !== args.speaker ||
      existing.kind !== args.kind ||
      existing.text !== text ||
      existing.inputMode !== args.inputMode
    ) {
      return failPersona("IDEMPOTENCY_CONFLICT", "Turn ID was reused");
    }
    return existing;
  }
  if (
    session.status !== "active" ||
    graph.persona.setupState === "complete"
  ) {
    return failPersona("RESOURCE_UNAVAILABLE", "Resource unavailable");
  }
  if (session.revision !== args.expectedSessionRevision) {
    return failPersona("REVISION_CONFLICT", "Session revision changed");
  }
  if (
    session.turnCount >= maximumOnboardingTurns ||
    session.nextSequence !== session.turnCount
  ) {
    return failPersona(
      session.turnCount >= maximumOnboardingTurns
        ? "INVALID_REQUEST"
        : "DATA_INTEGRITY",
      "Onboarding turn limit or sequence is invalid",
    );
  }
  const createdAt = Date.now();
  const turnId = await ctx.db.insert("personaOnboardingTurns", {
    sessionId: session._id,
    personaId: graph.persona._id,
    membershipId: graph.membership._id,
    workspaceId: graph.persona.workspaceId,
    ownerUserId: graph.profile._id,
    turnId: args.turnId,
    clientMutationId: args.clientMutationId,
    sequence: session.nextSequence,
    speaker: args.speaker,
    kind: args.kind,
    text,
    inputMode: args.inputMode,
    interpretationStatus: args.speaker === "owner" ? "pending" : undefined,
    createdAt,
  });
  await ctx.db.patch("personaOnboardingSessions", session._id, {
    revision: session.revision + 1,
    turnCount: session.turnCount + 1,
    nextSequence: session.nextSequence + 1,
    updatedAt: createdAt,
  });
  const createdTurn = await ctx.db.get("personaOnboardingTurns", turnId);
  if (createdTurn === null) {
    return failPersona("DATA_INTEGRITY", "Created turn is unavailable");
  }
  return createdTurn;
}

export const appendOwnerTurn = mutation({
  args: {
    sessionId: v.id("personaOnboardingSessions"),
    expectedSessionRevision: v.number(),
    turnId: v.string(),
    clientMutationId: v.string(),
    inputMode: personaOnboardingInputModeValidator,
    text: v.string(),
  },
  returns: turnDocumentValidator,
  handler: async (ctx, args) =>
    await appendTurn(ctx, {
      ...args,
      speaker: "owner",
      kind: "answer",
    }),
});

export const appendStickyTurn = mutation({
  args: {
    sessionId: v.id("personaOnboardingSessions"),
    expectedSessionRevision: v.number(),
    turnId: v.string(),
    clientMutationId: v.string(),
    kind: v.union(
      v.literal("introduction"),
      v.literal("question"),
      v.literal("acknowledgement"),
      v.literal("informational_summary"),
    ),
    text: v.string(),
  },
  returns: turnDocumentValidator,
  handler: async (ctx, args) =>
    await appendTurn(ctx, { ...args, speaker: "sticky" }),
});

const interpretationChangeValidator = v.union(
  v.object({
    operation: v.literal("create"),
    content: personaRecordContentValidator,
    evidenceExcerpt: v.string(),
    confidence: v.number(),
  }),
  v.object({
    operation: v.literal("update"),
    recordKey: v.string(),
    content: personaRecordContentValidator,
    evidenceExcerpt: v.string(),
    confidence: v.number(),
  }),
  v.object({
    operation: v.literal("delete"),
    recordKey: v.string(),
    evidenceExcerpt: v.string(),
    confidence: v.number(),
  }),
);

export const applyOwnerTurnInterpretation = mutation({
  args: {
    sessionId: v.id("personaOnboardingSessions"),
    sourceTurnId: v.id("personaOnboardingTurns"),
    expectedSessionRevision: v.number(),
    expectedPersonaVersion: v.number(),
    clientMutationId: v.string(),
    changes: v.array(interpretationChangeValidator),
  },
  returns: v.object({
    didCreateVersion: v.boolean(),
    versionId: v.union(v.id("personaVersions"), v.null()),
    versionNumber: v.number(),
    sessionRevision: v.number(),
    setupState: personaSetupStateValidator,
    activatedAt: v.union(v.number(), v.null()),
  }),
  handler: async (ctx, args) => {
    assertExternalId(args.clientMutationId, "Client mutation ID");
    assertSafeInteger(args.expectedSessionRevision, "Expected session revision");
    assertSafeInteger(args.expectedPersonaVersion, "Expected persona version");
    if (args.changes.length > 8) {
      return failPersona("INVALID_REQUEST", "Interpretation change limit exceeded");
    }
    const { session, graph } = await loadOwnedSession(ctx, args.sessionId);
    const normalizedChanges = args.changes.map((change) => {
      assertConfidence(change.confidence);
      const evidenceExcerpt = normalizeBoundedText(
        change.evidenceExcerpt,
        "Evidence excerpt",
        280,
      );
      if (change.operation !== "create") {
        assertExternalId(change.recordKey, "Record key");
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
      operation: "apply_owner_turn_interpretation",
      personaId: graph.persona._id,
      sessionId: session._id,
      sourceTurnId: args.sourceTurnId,
      expectedPersonaVersion: args.expectedPersonaVersion,
      changes: normalizedChanges,
    });
    const sourceTurn = await ctx.db.get(
      "personaOnboardingTurns",
      args.sourceTurnId,
    );
    if (
      sourceTurn === null ||
      sourceTurn.sessionId !== session._id ||
      sourceTurn.personaId !== graph.persona._id ||
      sourceTurn.membershipId !== graph.membership._id ||
      sourceTurn.workspaceId !== graph.persona.workspaceId ||
      sourceTurn.ownerUserId !== graph.profile._id ||
      sourceTurn.speaker !== "owner" ||
      sourceTurn.kind !== "answer"
    ) {
      return failPersona("RESOURCE_UNAVAILABLE", "Resource unavailable");
    }
    if (sourceTurn.interpretationStatus === "applied") {
      if (
        sourceTurn.interpretationClientMutationId !== args.clientMutationId ||
        sourceTurn.interpretationRequestFingerprint !== requestFingerprint
      ) {
        return failPersona("IDEMPOTENCY_CONFLICT", "Turn is already interpreted");
      }
      return {
        didCreateVersion: sourceTurn.interpretedVersionId !== undefined,
        versionId: sourceTurn.interpretedVersionId ?? null,
        versionNumber: graph.persona.currentVersion,
        sessionRevision: session.revision,
        setupState: graph.persona.setupState,
        activatedAt: graph.persona.activatedAt ?? null,
      };
    }
    if (
      session.status !== "active" ||
      graph.persona.setupState === "complete"
    ) {
      return failPersona("RESOURCE_UNAVAILABLE", "Resource unavailable");
    }
    if (session.revision !== args.expectedSessionRevision) {
      return failPersona("REVISION_CONFLICT", "Session revision changed");
    }
    if (graph.persona.currentVersion !== args.expectedPersonaVersion) {
      return failPersona("VERSION_CONFLICT", "Persona version changed");
    }
    if (args.changes.length === 0) {
      const updatedAt = Date.now();
      await ctx.db.patch("personaOnboardingTurns", sourceTurn._id, {
        interpretationStatus: "applied",
        interpretationClientMutationId: args.clientMutationId,
        interpretationRequestFingerprint: requestFingerprint,
      });
      await ctx.db.patch("personaOnboardingSessions", session._id, {
        revision: session.revision + 1,
        updatedAt,
      });
      return {
        didCreateVersion: false,
        versionId: null,
        versionNumber: graph.persona.currentVersion,
        sessionRevision: session.revision + 1,
        setupState: graph.persona.setupState,
        activatedAt: graph.persona.activatedAt ?? null,
      };
    }
    const result = await applyPersonaRecordChanges(
      ctx,
      graph,
      args.expectedPersonaVersion,
      args.clientMutationId,
      {
        kind: "onboarding_answer",
        sessionId: session._id,
        sourceTurn,
      },
      normalizedChanges,
    );
    const updatedPersona = await ctx.db.get("personas", graph.persona._id);
    if (updatedPersona === null) {
      return failPersona("DATA_INTEGRITY", "Updated persona is unavailable");
    }
    await ctx.db.patch("personaOnboardingTurns", sourceTurn._id, {
      interpretationStatus: "applied",
      interpretationClientMutationId: args.clientMutationId,
      interpretationRequestFingerprint: requestFingerprint,
      interpretedVersionId: result.versionId,
    });
    await ctx.db.patch("personaOnboardingSessions", session._id, {
      revision: session.revision + 1,
      updatedAt: Date.now(),
    });
    return {
      didCreateVersion: true,
      versionId: result.versionId,
      versionNumber: result.versionNumber,
      sessionRevision: session.revision + 1,
      setupState: updatedPersona.setupState,
      activatedAt: result.activatedAt,
    };
  },
});

async function transitionSession(
  ctx: MutationCtx,
  args: {
    sessionId: Doc<"personaOnboardingSessions">["_id"];
    expectedSessionRevision: number;
    clientMutationId: string;
    operation: "pause" | "complete";
    reason?: "userPaused" | "skippedForNow";
  },
) {
  assertExternalId(args.clientMutationId, "Client mutation ID");
  assertSafeInteger(args.expectedSessionRevision, "Expected session revision");
  const { session, graph } = await loadOwnedSession(ctx, args.sessionId);
  const requestFingerprint = await createRequestFingerprint({
    operation: args.operation,
    personaId: graph.persona._id,
    sessionId: session._id,
    expectedSessionRevision: args.expectedSessionRevision,
    reason: args.reason ?? null,
  });
  const priorReceipt = await loadSessionOperationReceipt(
    ctx,
    graph.persona._id,
    args.clientMutationId,
    requestFingerprint,
  );
  if (priorReceipt !== null) {
    if (priorReceipt.sessionId !== session._id) {
      return failPersona("DATA_INTEGRITY", "Operation receipt is malformed");
    }
    return projectSessionReceipt(priorReceipt);
  }
  if (session.revision !== args.expectedSessionRevision) {
    return failPersona("REVISION_CONFLICT", "Session revision changed");
  }
  if (args.operation === "pause") {
    if (
      session.status !== "active" ||
      (args.reason === "skippedForNow" &&
        graph.persona.setupState !== "interview")
    ) {
      return failPersona("INVALID_REQUEST", "Session cannot be paused");
    }
    const timestamp = Date.now();
    await ctx.db.patch("personaOnboardingSessions", session._id, {
      status: "paused",
      pauseReason: args.reason,
      revision: session.revision + 1,
      pausedAt: timestamp,
      updatedAt: timestamp,
    });
    await insertSessionOperationReceipt(ctx, graph, {
      sessionId: session._id,
      clientMutationId: args.clientMutationId,
      operation: "pause",
      requestFingerprint,
      resultStatus: "paused",
      resultRevision: session.revision + 1,
      resultSetupState: graph.persona.setupState,
    });
    return {
      sessionId: session._id,
      status: "paused" as const,
      revision: session.revision + 1,
      setupState: graph.persona.setupState,
    };
  }
  const records = await loadCurrentRecords(ctx, graph.persona._id);
  if (
    graph.persona.setupState !== "interview" ||
    graph.persona.activatedAt === undefined ||
    !minimumReadiness(records).isMet ||
    session.status === "completed"
  ) {
    return failPersona("MINIMUM_REQUIRED", "Onboarding cannot be completed");
  }
  const timestamp = Date.now();
  await ctx.db.patch("personaOnboardingSessions", session._id, {
    status: "completed",
    pauseReason: undefined,
    pausedAt: undefined,
    revision: session.revision + 1,
    completedAt: timestamp,
    updatedAt: timestamp,
  });
  await ctx.db.patch("personas", graph.persona._id, {
    setupState: "complete",
    updatedAt: timestamp,
  });
  await insertSessionOperationReceipt(ctx, graph, {
    sessionId: session._id,
    clientMutationId: args.clientMutationId,
    operation: "complete",
    requestFingerprint,
    resultStatus: "completed",
    resultRevision: session.revision + 1,
    resultSetupState: "complete",
  });
  return {
    sessionId: session._id,
    status: "completed" as const,
    revision: session.revision + 1,
    setupState: "complete" as const,
  };
}

export const pause = mutation({
  args: {
    sessionId: v.id("personaOnboardingSessions"),
    expectedSessionRevision: v.number(),
    reason: personaOnboardingPauseReasonValidator,
    clientMutationId: v.string(),
  },
  returns: sessionMutationResultValidator,
  handler: async (ctx, args) =>
    await transitionSession(ctx, { ...args, operation: "pause" }),
});

export const complete = mutation({
  args: {
    sessionId: v.id("personaOnboardingSessions"),
    expectedSessionRevision: v.number(),
    clientMutationId: v.string(),
  },
  returns: sessionMutationResultValidator,
  handler: async (ctx, args) =>
    await transitionSession(ctx, { ...args, operation: "complete" }),
});
