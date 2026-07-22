import { v } from "convex/values";

export const profileLifecycleStatusValidator = v.union(
  v.literal("active"),
  v.literal("deletionPending"),
);

export const workspaceKindValidator = v.union(
  v.literal("personal"),
  v.literal("team"),
);

export const workspaceLifecycleStatusValidator = v.union(
  v.literal("active"),
  v.literal("deleting"),
);

export const workspaceRoleValidator = v.union(
  v.literal("owner"),
  v.literal("admin"),
  v.literal("member"),
);

export const workspaceMemberStatusValidator = v.union(
  v.literal("active"),
  v.literal("removed"),
);

export const personaLifecycleStatusValidator = v.union(
  v.literal("active"),
  v.literal("removing"),
);

export const personaSetupStateValidator = v.union(
  v.literal("notStarted"),
  v.literal("essentials"),
  v.literal("interview"),
  v.literal("complete"),
);

export const accountBootstrapSnapshotValidator = v.object({
  profileId: v.id("profiles"),
  profileDisplayName: v.string(),
  workspaceId: v.id("workspaces"),
  workspaceName: v.string(),
  businessType: v.union(v.string(), v.null()),
  membershipId: v.id("workspaceMembers"),
  personaId: v.id("personas"),
  personaDisplayName: v.string(),
  personaSetupState: personaSetupStateValidator,
  personaCurrentVersion: v.number(),
});

export const currentAccountResultValidator = v.union(
  v.object({
    status: v.literal("needsProvisioning"),
  }),
  v.object({
    status: v.literal("ready"),
    snapshot: accountBootstrapSnapshotValidator,
  }),
);

export const profileValidator = v.object({
  tokenIdentifier: v.string(),
  displayName: v.string(),
  email: v.optional(v.string()),
  avatarUrl: v.optional(v.string()),
  accountSettings: v.object({
    locale: v.optional(v.string()),
    timeZone: v.optional(v.string()),
  }),
  lifecycleStatus: profileLifecycleStatusValidator,
  deletionRequestedAt: v.optional(v.number()),
  deletionScheduledFor: v.optional(v.number()),
  createdAt: v.number(),
  updatedAt: v.number(),
});

const workspaceFieldsValidator = v.object({
  name: v.string(),
  createdByProfileId: v.id("profiles"),
  lifecycleStatus: workspaceLifecycleStatusValidator,
  createdAt: v.number(),
  updatedAt: v.number(),
});

export const workspaceValidator = v.union(
  workspaceFieldsValidator.extend({
    kind: v.literal("personal"),
    businessType: v.optional(v.string()),
  }),
  workspaceFieldsValidator.extend({
    kind: v.literal("team"),
    businessType: v.string(),
  }),
);

export const workspaceMemberValidator = v.object({
  workspaceId: v.id("workspaces"),
  userId: v.id("profiles"),
  role: workspaceRoleValidator,
  status: workspaceMemberStatusValidator,
  joinedAt: v.number(),
  removedAt: v.optional(v.number()),
});

export const personaValidator = v.object({
  membershipId: v.id("workspaceMembers"),
  workspaceId: v.id("workspaces"),
  ownerUserId: v.id("profiles"),
  status: personaLifecycleStatusValidator,
  displayName: v.string(),
  professionalRole: v.optional(v.string()),
  voiceId: v.optional(v.string()),
  avatarUrl: v.optional(v.string()),
  setupState: personaSetupStateValidator,
  currentVersion: v.number(),
  createdAt: v.number(),
  updatedAt: v.number(),
});
