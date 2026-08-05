import { v } from "convex/values";

import type { Doc, Id } from "./_generated/dataModel";
import { mutation, query } from "./_generated/server";
import type { MutationCtx } from "./_generated/server";
import {
  requireIdentity,
  requirePersonaOwner,
  requireReadableBoundarySummary,
} from "./authorization";
import {
  assertExternalId,
  assertSafeInteger,
  createRequestFingerprint,
  failPersona,
  normalizeBoundedText,
  validateBoundarySummaryDocument,
  validatePersonaSetupGraph,
} from "./personaFoundation";

const ownedSummaryProjectionValidator = v.object({
  summaryId: v.id("personaBoundarySummaries"),
  personaId: v.id("personas"),
  summaryText: v.string(),
  sourceVersionNumber: v.number(),
  state: v.union(
    v.literal("draft"),
    v.literal("approved"),
    v.literal("superseded"),
    v.literal("unpublished"),
  ),
  approvedAt: v.union(v.number(), v.null()),
});

function projectOwned(summary: Doc<"personaBoundarySummaries">) {
  return {
    summaryId: summary._id,
    personaId: summary.personaId,
    summaryText: summary.summaryText,
    sourceVersionNumber: summary.sourceVersionNumber,
    state: summary.state,
    approvedAt: summary.approvedAt ?? null,
  };
}

async function loadOwnedSummary(
  ctx: MutationCtx,
  summaryId: Id<"personaBoundarySummaries">,
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
  const summary = await ctx.db.get("personaBoundarySummaries", summaryId);
  if (summary === null) {
    return failPersona("RESOURCE_UNAVAILABLE", "Resource unavailable");
  }
  const persona = await ctx.db.get("personas", summary.personaId);
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
    workspace.lifecycleStatus !== "active"
  ) {
    return failPersona("RESOURCE_UNAVAILABLE", "Resource unavailable");
  }
  const graph = { profile, membership, persona };
  validateBoundarySummaryDocument(summary, persona);
  await validatePersonaSetupGraph(ctx, persona);
  return { summary, graph };
}

export const getReadable = query({
  args: { personaId: v.id("personas") },
  returns: v.union(
    v.object({
      personaId: v.id("personas"),
      summaryText: v.string(),
      approvedAt: v.number(),
    }),
    v.null(),
  ),
  handler: async (ctx, args) => {
    const readable = await requireReadableBoundarySummary(ctx, args.personaId);
    if (readable.summary === null) {
      return null;
    }
    return {
      personaId: readable.persona._id,
      summaryText: readable.summary.summaryText,
      approvedAt: readable.summary.approvedAt!,
    };
  },
});

export const saveOwnedDraft = mutation({
  args: {
    personaId: v.id("personas"),
    expectedPersonaVersion: v.number(),
    clientMutationId: v.string(),
    summaryText: v.string(),
  },
  returns: ownedSummaryProjectionValidator,
  handler: async (ctx, args) => {
    assertExternalId(args.clientMutationId, "Client mutation ID");
    assertSafeInteger(args.expectedPersonaVersion, "Expected persona version");
    const summaryText = normalizeBoundedText(
      args.summaryText,
      "Boundary summary",
      500,
    );
    const graph = await requirePersonaOwner(ctx, args.personaId);
    await validatePersonaSetupGraph(ctx, graph.persona);
    const requestFingerprint = await createRequestFingerprint({
      operation: "save_boundary_draft",
      personaId: graph.persona._id,
      expectedPersonaVersion: args.expectedPersonaVersion,
      summaryText,
    });
    const existing = await ctx.db
      .query("personaBoundarySummaries")
      .withIndex("by_personaId_and_clientMutationId", (indexQuery) =>
        indexQuery
          .eq("personaId", args.personaId)
          .eq("clientMutationId", args.clientMutationId),
      )
      .unique();
    if (existing !== null) {
      validateBoundarySummaryDocument(existing, graph.persona);
      if (
        existing.summaryText !== summaryText ||
        existing.sourceVersionNumber !== args.expectedPersonaVersion ||
        existing.requestFingerprint !== requestFingerprint
      ) {
        return failPersona("IDEMPOTENCY_CONFLICT", "Mutation ID was reused");
      }
      return projectOwned(existing);
    }
    if (graph.persona.currentVersion !== args.expectedPersonaVersion) {
      return failPersona("VERSION_CONFLICT", "Persona version changed");
    }
    const boundary = await ctx.db
      .query("personaRecords")
      .withIndex(
        "by_personaId_and_isCurrent_and_state_and_kind",
        (indexQuery) =>
          indexQuery
            .eq("personaId", graph.persona._id)
            .eq("isCurrent", true)
            .eq("state", "active")
            .eq("kind", "boundary"),
      )
      .take(1);
    if (boundary.length !== 1) {
      return failPersona("INVALID_REQUEST", "An active boundary is required");
    }
    const drafts = await ctx.db
      .query("personaBoundarySummaries")
      .withIndex("by_personaId_and_state", (indexQuery) =>
        indexQuery.eq("personaId", args.personaId).eq("state", "draft"),
      )
      .take(2);
    if (drafts.length > 1) {
      return failPersona("DATA_INTEGRITY", "Multiple boundary drafts exist");
    }
    if (drafts[0] !== undefined) {
      validateBoundarySummaryDocument(drafts[0], graph.persona);
    }
    const timestamp = Date.now();
    if (drafts[0] !== undefined) {
      await ctx.db.patch("personaBoundarySummaries", drafts[0]._id, {
        state: "superseded",
        supersededAt: timestamp,
      });
    }
    const summaryId = await ctx.db.insert("personaBoundarySummaries", {
      personaId: graph.persona._id,
      membershipId: graph.membership._id,
      workspaceId: graph.persona.workspaceId,
      ownerUserId: graph.profile._id,
      summaryText,
      sourceVersionNumber: graph.persona.currentVersion,
      state: "draft",
      clientMutationId: args.clientMutationId,
      requestFingerprint,
      createdAt: timestamp,
    });
    const summary = await ctx.db.get("personaBoundarySummaries", summaryId);
    if (summary === null) {
      return failPersona("DATA_INTEGRITY", "Created summary is unavailable");
    }
    return projectOwned(summary);
  },
});

async function approve(
  ctx: MutationCtx,
  args: {
    summaryId: Id<"personaBoundarySummaries">;
    expectedPersonaVersion: number;
    expectedApprovedSummaryId: Id<"personaBoundarySummaries"> | null;
    clientMutationId: string;
    operation: "approve_boundary_draft" | "replace_boundary_summary";
  },
) {
  assertExternalId(args.clientMutationId, "Client mutation ID");
  assertSafeInteger(args.expectedPersonaVersion, "Expected persona version");
  const { summary, graph } = await loadOwnedSummary(ctx, args.summaryId);
  const requestFingerprint = await createRequestFingerprint({
    operation: args.operation,
    personaId: graph.persona._id,
    summaryId: summary._id,
    expectedPersonaVersion: args.expectedPersonaVersion,
    expectedApprovedSummaryId: args.expectedApprovedSummaryId,
  });
  const priorAttempt = await ctx.db
    .query("personaBoundarySummaries")
    .withIndex("by_personaId_and_approvalClientMutationId", (indexQuery) =>
      indexQuery
        .eq("personaId", summary.personaId)
        .eq("approvalClientMutationId", args.clientMutationId),
    )
    .unique();
  if (priorAttempt !== null) {
    validateBoundarySummaryDocument(priorAttempt, graph.persona);
    if (
      priorAttempt._id !== summary._id ||
      priorAttempt.approvalRequestFingerprint !== requestFingerprint
    ) {
      return failPersona("IDEMPOTENCY_CONFLICT", "Mutation ID was reused");
    }
    return projectOwned(priorAttempt);
  }
  if (
    summary.state !== "draft" ||
    summary.sourceVersionNumber !== graph.persona.currentVersion ||
    graph.persona.currentVersion !== args.expectedPersonaVersion
  ) {
    return failPersona("VERSION_CONFLICT", "Boundary draft is stale");
  }
  const approved = await ctx.db
    .query("personaBoundarySummaries")
    .withIndex("by_personaId_and_state", (indexQuery) =>
      indexQuery.eq("personaId", summary.personaId).eq("state", "approved"),
    )
    .take(2);
  if (approved.length > 1) {
    return failPersona("DATA_INTEGRITY", "Multiple approved summaries exist");
  }
  const currentApproved = approved[0] ?? null;
  if (currentApproved !== null) {
    validateBoundarySummaryDocument(currentApproved, graph.persona);
  }
  if ((currentApproved?._id ?? null) !== args.expectedApprovedSummaryId) {
    return failPersona("REVISION_CONFLICT", "Approved summary changed");
  }
  const timestamp = Date.now();
  if (currentApproved !== null) {
    await ctx.db.patch("personaBoundarySummaries", currentApproved._id, {
      state: "superseded",
      supersededAt: timestamp,
    });
  }
  await ctx.db.patch("personaBoundarySummaries", summary._id, {
    state: "approved",
    approvalClientMutationId: args.clientMutationId,
    approvalRequestFingerprint: requestFingerprint,
    approvedAt: timestamp,
  });
  return projectOwned({
    ...summary,
    state: "approved",
    approvalClientMutationId: args.clientMutationId,
    approvalRequestFingerprint: requestFingerprint,
    approvedAt: timestamp,
  });
}

const approvalArgs = {
  summaryId: v.id("personaBoundarySummaries"),
  expectedPersonaVersion: v.number(),
  expectedApprovedSummaryId: v.union(
    v.id("personaBoundarySummaries"),
    v.null(),
  ),
  clientMutationId: v.string(),
};

export const approveOwnedDraft = mutation({
  args: approvalArgs,
  returns: ownedSummaryProjectionValidator,
  handler: async (ctx, args) =>
    await approve(ctx, { ...args, operation: "approve_boundary_draft" }),
});

export const replaceOwned = mutation({
  args: approvalArgs,
  returns: ownedSummaryProjectionValidator,
  handler: async (ctx, args) =>
    await approve(ctx, { ...args, operation: "replace_boundary_summary" }),
});

export const unpublishOwned = mutation({
  args: {
    personaId: v.id("personas"),
    expectedApprovedSummaryId: v.id("personaBoundarySummaries"),
    clientMutationId: v.string(),
  },
  returns: v.object({ didUnpublish: v.boolean() }),
  handler: async (ctx, args) => {
    assertExternalId(args.clientMutationId, "Client mutation ID");
    const { summary, graph } = await loadOwnedSummary(
      ctx,
      args.expectedApprovedSummaryId,
    );
    if (summary.personaId !== args.personaId) {
      return failPersona("RESOURCE_UNAVAILABLE", "Resource unavailable");
    }
    const requestFingerprint = await createRequestFingerprint({
      operation: "unpublish_boundary_summary",
      personaId: graph.persona._id,
      expectedApprovedSummaryId: summary._id,
    });
    const previous = await ctx.db
      .query("personaBoundarySummaries")
      .withIndex("by_personaId_and_unpublishClientMutationId", (indexQuery) =>
        indexQuery
          .eq("personaId", args.personaId)
          .eq("unpublishClientMutationId", args.clientMutationId),
      )
      .unique();
    if (previous !== null) {
      validateBoundarySummaryDocument(previous, graph.persona);
      if (previous._id !== args.expectedApprovedSummaryId) {
        return failPersona("IDEMPOTENCY_CONFLICT", "Mutation ID was reused");
      }
      if (previous.unpublishRequestFingerprint !== requestFingerprint) {
        return failPersona("IDEMPOTENCY_CONFLICT", "Mutation ID was reused");
      }
      return { didUnpublish: false };
    }
    if (summary.state !== "approved") {
      return failPersona("REVISION_CONFLICT", "Approved summary changed");
    }
    await ctx.db.patch("personaBoundarySummaries", summary._id, {
      state: "unpublished",
      unpublishClientMutationId: args.clientMutationId,
      unpublishRequestFingerprint: requestFingerprint,
      unpublishedAt: Date.now(),
    });
    return { didUnpublish: true };
  },
});

export const discardOwnedDraft = mutation({
  args: { summaryId: v.id("personaBoundarySummaries") },
  returns: v.object({ didDiscard: v.boolean() }),
  handler: async (ctx, args) => {
    const { summary } = await loadOwnedSummary(ctx, args.summaryId);
    if (summary.state !== "draft") {
      return failPersona("INVALID_REQUEST", "Only drafts may be discarded");
    }
    await ctx.db.delete("personaBoundarySummaries", summary._id);
    return { didDiscard: true };
  },
});
