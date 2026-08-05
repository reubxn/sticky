import {
  paginationOptsValidator,
  paginationResultValidator,
} from "convex/server";
import { v } from "convex/values";

import { mutation, query } from "./_generated/server";
import { requirePersonaOwner } from "./authorization";
import {
  applyPersonaRecordChanges,
  assertExternalId,
  failPersona,
  isRequestFingerprint,
  validatePersonaSetupGraph,
} from "./personaFoundation";
import {
  personaRecordContentValidator,
  personaVersionSourceValidator,
} from "./validators";

const versionDocumentValidator = v.object({
  _id: v.id("personaVersions"),
  _creationTime: v.number(),
  personaId: v.id("personas"),
  membershipId: v.id("workspaceMembers"),
  workspaceId: v.id("workspaces"),
  ownerUserId: v.id("profiles"),
  versionNumber: v.number(),
  previousVersionNumber: v.number(),
  clientMutationId: v.string(),
  requestFingerprint: v.string(),
  source: personaVersionSourceValidator,
  changeCount: v.number(),
  createdAt: v.number(),
});

const manualChangeValidator = v.union(
  v.object({
    operation: v.literal("create"),
    content: personaRecordContentValidator,
    confidence: v.number(),
  }),
  v.object({
    operation: v.literal("update"),
    recordKey: v.string(),
    content: personaRecordContentValidator,
    confidence: v.number(),
  }),
  v.object({
    operation: v.literal("delete"),
    recordKey: v.string(),
    confidence: v.number(),
  }),
);

export const listOwnedVersions = query({
  args: {
    personaId: v.id("personas"),
    paginationOpts: paginationOptsValidator,
  },
  returns: paginationResultValidator(versionDocumentValidator),
  handler: async (ctx, args) => {
    const graph = await requirePersonaOwner(ctx, args.personaId);
    const validated = await validatePersonaSetupGraph(ctx, graph.persona);
    const result = await ctx.db
      .query("personaVersions")
      .withIndex("by_personaId_and_versionNumber", (indexQuery) =>
        indexQuery.eq("personaId", args.personaId),
      )
      .order("desc")
      .paginate(args.paginationOpts);
    for (const version of result.page) {
      if (
        version.personaId !== graph.persona._id ||
        version.membershipId !== graph.membership._id ||
        version.workspaceId !== graph.persona.workspaceId ||
        version.ownerUserId !== graph.profile._id ||
        !Number.isSafeInteger(version.versionNumber) ||
        version.versionNumber < 1 ||
        version.versionNumber > graph.persona.currentVersion ||
        version.previousVersionNumber !== version.versionNumber - 1 ||
        !isRequestFingerprint(version.requestFingerprint)
      ) {
        return failPersona("DATA_INTEGRITY", "Persona version is malformed");
      }
      if (version.source.kind === "onboarding_answer") {
        const sourceTurnId = version.source.sourceTurnId;
        const sourceTurn = validated.turns.find(
          (turn) => turn._id === sourceTurnId,
        );
        if (
          validated.session?._id !== version.source.sessionId ||
          sourceTurn === undefined ||
          sourceTurn.interpretedVersionId !== version._id
        ) {
          return failPersona("DATA_INTEGRITY", "Version provenance is malformed");
        }
      }
    }
    return result;
  },
});

export const applyOwnedChanges = mutation({
  args: {
    personaId: v.id("personas"),
    expectedPersonaVersion: v.number(),
    clientMutationId: v.string(),
    changes: v.array(manualChangeValidator),
  },
  returns: v.object({
    versionId: v.id("personaVersions"),
    versionNumber: v.number(),
    activatedAt: v.union(v.number(), v.null()),
  }),
  handler: async (ctx, args) => {
    assertExternalId(args.clientMutationId, "Client mutation ID");
    const graph = await requirePersonaOwner(ctx, args.personaId);
    if (graph.persona.setupState === "notStarted") {
      return failPersona(
        "INVALID_REQUEST",
        "Start onboarding before editing persona records",
      );
    }
    return await applyPersonaRecordChanges(
      ctx,
      graph,
      args.expectedPersonaVersion,
      args.clientMutationId,
      { kind: "manual_owner_edit" },
      args.changes,
    );
  },
});
