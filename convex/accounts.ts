import type { UserIdentity } from "convex/server";
import { ConvexError, v } from "convex/values";

import type { Doc, Id } from "./_generated/dataModel";
import { mutation, query } from "./_generated/server";
import type { MutationCtx, QueryCtx } from "./_generated/server";
import { requireIdentity } from "./authorization";
import {
  accountBootstrapSnapshotValidator,
  currentAccountResultValidator,
} from "./validators";

type AccountCtx = Pick<QueryCtx | MutationCtx, "db">;

type AccountGraph = {
  profile: Doc<"profiles">;
  workspace: Doc<"workspaces"> | null;
  membership: Doc<"workspaceMembers"> | null;
  persona: Doc<"personas"> | null;
};

function failDataIntegrity(message: string): never {
  throw new ConvexError({ code: "DATA_INTEGRITY", message });
}

function failAccountDeletionPending(): never {
  throw new ConvexError({
    code: "ACCOUNT_DELETION_PENDING",
    message: "Account deletion is pending",
  });
}

function nonEmptyClaim(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }
  const trimmedValue = value.trim();
  return trimmedValue.length > 0 ? trimmedValue : undefined;
}

function profileDisplayName(identity: UserIdentity): string {
  return nonEmptyClaim(identity.name) ?? "Sticky user";
}

function defaultWorkspaceName(displayName: string): string {
  const suffix = "'s Workspace";
  const maximumDisplayNameLength = 80 - suffix.length;
  const safeDisplayName = displayName
    .replace(/[\u0000-\u001f\u007f]/g, "")
    .trim()
    .slice(0, maximumDisplayNameLength);
  return safeDisplayName.length > 0
    ? `${safeDisplayName}${suffix}`
    : "My Workspace";
}

async function loadCanonicalProfile(
  ctx: AccountCtx,
  tokenIdentifier: string,
): Promise<Doc<"profiles"> | null> {
  const profiles = await ctx.db
    .query("profiles")
    .withIndex("by_tokenIdentifier", (indexQuery) =>
      indexQuery.eq("tokenIdentifier", tokenIdentifier),
    )
    .take(2);

  if (profiles.length > 1) {
    return failDataIntegrity("Multiple profiles exist for this identity");
  }
  const profile = profiles[0] ?? null;
  if (profile?.lifecycleStatus === "deletionPending") {
    return failAccountDeletionPending();
  }
  if (
    profile !== null &&
    (profile.deletionRequestedAt !== undefined ||
      profile.deletionScheduledFor !== undefined)
  ) {
    return failDataIntegrity("Active profile has deletion metadata");
  }
  return profile;
}

async function loadAccountGraph(
  ctx: AccountCtx,
  profile: Doc<"profiles">,
): Promise<AccountGraph> {
  const workspaces = await ctx.db
    .query("workspaces")
    .withIndex("by_createdByProfileId_and_kind", (indexQuery) =>
      indexQuery
        .eq("createdByProfileId", profile._id)
        .eq("kind", "personal"),
    )
    .take(2);

  if (workspaces.length > 1) {
    return failDataIntegrity("Multiple personal workspaces exist for this profile");
  }
  const workspace = workspaces[0] ?? null;
  if (workspace === null) {
    return { profile, workspace: null, membership: null, persona: null };
  }
  if (
    workspace.kind !== "personal" ||
    workspace.createdByProfileId !== profile._id ||
    workspace.lifecycleStatus !== "active"
  ) {
    return failDataIntegrity("Personal workspace relationship is invalid");
  }

  const memberships = await ctx.db
    .query("workspaceMembers")
    .withIndex("by_workspaceId_and_status", (indexQuery) =>
      indexQuery.eq("workspaceId", workspace._id),
    )
    .take(2);

  const personas = await ctx.db
    .query("personas")
    .withIndex("by_workspaceId_and_status", (indexQuery) =>
      indexQuery.eq("workspaceId", workspace._id),
    )
    .take(2);

  if (memberships.length > 1) {
    return failDataIntegrity("Personal workspace has multiple memberships");
  }
  if (personas.length > 1) {
    return failDataIntegrity("Personal workspace has multiple personas");
  }
  const membership = memberships[0] ?? null;
  if (membership === null) {
    if (personas.length > 0) {
      return failDataIntegrity("Personal workspace persona has no membership");
    }
    return { profile, workspace, membership: null, persona: null };
  }
  if (
    membership.workspaceId !== workspace._id ||
    membership.userId !== profile._id ||
    membership.role !== "owner" ||
    membership.status !== "active" ||
    membership.removedAt !== undefined
  ) {
    return failDataIntegrity("Personal workspace membership is invalid");
  }

  const persona = personas[0] ?? null;
  if (persona === null) {
    return { profile, workspace, membership, persona: null };
  }
  if (
    persona.membershipId !== membership._id ||
    persona.workspaceId !== workspace._id ||
    persona.ownerUserId !== profile._id ||
    persona.status !== "active" ||
    !Number.isSafeInteger(persona.currentVersion) ||
    persona.currentVersion < 0 ||
    ((persona.setupState === "notStarted" ||
      persona.setupState === "essentials") &&
      persona.activatedAt !== undefined) ||
    ((persona.setupState === "interview" ||
      persona.setupState === "complete") &&
      persona.activatedAt === undefined)
  ) {
    return failDataIntegrity("Personal workspace persona is invalid");
  }

  return { profile, workspace, membership, persona };
}

function readySnapshot(graph: {
  profile: Doc<"profiles">;
  workspace: Doc<"workspaces">;
  membership: Doc<"workspaceMembers">;
  persona: Doc<"personas">;
}) {
  return {
    profileId: graph.profile._id,
    profileDisplayName: graph.profile.displayName,
    workspaceId: graph.workspace._id,
    workspaceName: graph.workspace.name,
    businessType:
      graph.workspace.kind === "personal"
        ? graph.workspace.businessType ?? null
        : null,
    membershipId: graph.membership._id,
    personaId: graph.persona._id,
    personaDisplayName: graph.persona.displayName,
    personaSetupState: graph.persona.setupState,
    personaCurrentVersion: graph.persona.currentVersion,
  };
}

export const current = query({
  args: {},
  returns: currentAccountResultValidator,
  handler: async (ctx) => {
    const identity = await requireIdentity(ctx);
    const profile = await loadCanonicalProfile(ctx, identity.tokenIdentifier);
    if (profile === null) {
      return { status: "needsProvisioning" as const };
    }

    const graph = await loadAccountGraph(ctx, profile);
    if (
      graph.workspace === null ||
      graph.membership === null ||
      graph.persona === null
    ) {
      return { status: "needsProvisioning" as const };
    }

    return {
      status: "ready" as const,
      snapshot: readySnapshot({
        profile: graph.profile,
        workspace: graph.workspace,
        membership: graph.membership,
        persona: graph.persona,
      }),
    };
  },
});

export const provisionCurrent = mutation({
  args: {},
  returns: v.object({
    didCreate: v.boolean(),
    snapshot: accountBootstrapSnapshotValidator,
  }),
  handler: async (ctx) => {
    const identity = await requireIdentity(ctx);
    const timestamp = Date.now();
    let didCreate = false;

    let profile = await loadCanonicalProfile(ctx, identity.tokenIdentifier);
    const priorProfileDisplayName = profile?.displayName ?? null;
    const verifiedDisplayName = nonEmptyClaim(identity.name);
    let shouldRepairDefaultNames = false;
    if (profile === null) {
      const displayName = profileDisplayName(identity);
      const profileId = await ctx.db.insert("profiles", {
        tokenIdentifier: identity.tokenIdentifier,
        displayName,
        email: nonEmptyClaim(identity.email),
        avatarUrl: nonEmptyClaim(identity.pictureUrl),
        accountSettings: {},
        lifecycleStatus: "active",
        createdAt: timestamp,
        updatedAt: timestamp,
      });
      const createdProfile = await ctx.db.get("profiles", profileId);
      if (createdProfile === null) {
        return failDataIntegrity("Created profile could not be loaded");
      }
      profile = createdProfile;
      didCreate = true;
    } else {
      const profilePatch: Partial<
        Pick<Doc<"profiles">, "displayName" | "email" | "avatarUrl" | "updatedAt">
      > = {};
      const email = nonEmptyClaim(identity.email);
      const avatarUrl = nonEmptyClaim(identity.pictureUrl);

      if (
        verifiedDisplayName !== undefined &&
        verifiedDisplayName !== profile.displayName
      ) {
        profilePatch.displayName = verifiedDisplayName;
        shouldRepairDefaultNames = true;
      }
      if (email !== undefined && email !== profile.email) {
        profilePatch.email = email;
      }
      if (avatarUrl !== undefined && avatarUrl !== profile.avatarUrl) {
        profilePatch.avatarUrl = avatarUrl;
      }
      if (Object.keys(profilePatch).length > 0) {
        profilePatch.updatedAt = timestamp;
        await ctx.db.patch("profiles", profile._id, profilePatch);
        const refreshedProfile = await ctx.db.get("profiles", profile._id);
        if (refreshedProfile === null) {
          return failDataIntegrity("Updated profile could not be loaded");
        }
        profile = refreshedProfile;
      }
    }

    let graph = await loadAccountGraph(ctx, profile);
    let workspace = graph.workspace;
    if (
      workspace !== null &&
      shouldRepairDefaultNames &&
      priorProfileDisplayName !== null &&
      workspace.name === defaultWorkspaceName(priorProfileDisplayName)
    ) {
      await ctx.db.patch("workspaces", workspace._id, {
        name: defaultWorkspaceName(profile.displayName),
        updatedAt: timestamp,
      });
      const refreshedWorkspace = await ctx.db.get(
        "workspaces",
        workspace._id,
      );
      if (refreshedWorkspace === null) {
        return failDataIntegrity("Updated workspace could not be loaded");
      }
      workspace = refreshedWorkspace;
    }
    if (workspace === null) {
      const workspaceId = await ctx.db.insert("workspaces", {
        kind: "personal",
        name: defaultWorkspaceName(profile.displayName),
        createdByProfileId: profile._id,
        lifecycleStatus: "active",
        createdAt: timestamp,
        updatedAt: timestamp,
      });
      workspace = await ctx.db.get("workspaces", workspaceId);
      if (workspace === null) {
        return failDataIntegrity("Created workspace could not be loaded");
      }
      didCreate = true;
    }

    let membership = graph.membership;
    if (membership === null) {
      const membershipId = await ctx.db.insert("workspaceMembers", {
        workspaceId: workspace._id,
        userId: profile._id,
        role: "owner",
        status: "active",
        joinedAt: timestamp,
      });
      membership = await ctx.db.get("workspaceMembers", membershipId);
      if (membership === null) {
        return failDataIntegrity("Created membership could not be loaded");
      }
      didCreate = true;
    }

    let persona = graph.persona;
    if (
      persona !== null &&
      shouldRepairDefaultNames &&
      priorProfileDisplayName !== null &&
      persona.displayName === priorProfileDisplayName &&
      persona.setupState === "notStarted" &&
      persona.currentVersion === 0 &&
      persona.activatedAt === undefined
    ) {
      await ctx.db.patch("personas", persona._id, {
        displayName: profile.displayName,
        updatedAt: timestamp,
      });
      const refreshedPersona = await ctx.db.get("personas", persona._id);
      if (refreshedPersona === null) {
        return failDataIntegrity("Updated persona could not be loaded");
      }
      persona = refreshedPersona;
    }
    if (persona === null) {
      const personaId = await ctx.db.insert("personas", {
        membershipId: membership._id,
        workspaceId: workspace._id,
        ownerUserId: profile._id,
        status: "active",
        displayName: profile.displayName,
        setupState: "notStarted",
        currentVersion: 0,
        createdAt: timestamp,
        updatedAt: timestamp,
      });
      persona = await ctx.db.get("personas", personaId);
      if (persona === null) {
        return failDataIntegrity("Created persona could not be loaded");
      }
      didCreate = true;
    }

    return {
      didCreate,
      snapshot: readySnapshot({
        profile,
        workspace,
        membership,
        persona,
      }),
    };
  },
});
