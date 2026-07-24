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

export const workerRequestScopeValidator = v.union(
  v.literal("onboarding_chat"),
  v.literal("onboarding_tts"),
  v.literal("onboarding_transcribe"),
);

export const workerRequestAuditStatusValidator = v.union(
  v.literal("issued"),
  v.literal("consumed"),
  v.literal("completed"),
);

export const workerRequestOutcomeValidator = v.union(
  v.literal("succeeded"),
  v.literal("provider_error"),
  v.literal("client_disconnected"),
);

export const workerRequestUsageValidator = v.object({
  inputUnits: v.optional(v.number()),
  outputUnits: v.optional(v.number()),
});

export const workerRequestCompletionValidator = v.object({
  outcome: workerRequestOutcomeValidator,
  providerRequestId: v.optional(v.string()),
  httpStatusClass: v.optional(v.number()),
  latencyMs: v.number(),
  usage: workerRequestUsageValidator,
  errorCode: v.optional(v.string()),
});

export const onboardingChatPolicyValidator = v.object({
  kind: v.literal("onboarding_chat"),
  model: v.string(),
  systemPrompt: v.string(),
  maximumOutputTokens: v.number(),
});

export const onboardingTTSPolicyValidator = v.object({
  kind: v.literal("onboarding_tts"),
  voiceId: v.string(),
  model: v.string(),
  outputFormat: v.string(),
  stability: v.number(),
  similarityBoost: v.number(),
});

export const onboardingTranscribePolicyValidator = v.object({
  kind: v.literal("onboarding_transcribe"),
  redemptionWindowSeconds: v.number(),
  maximumSessionSeconds: v.number(),
});

export const workerRequestPolicyEnvelopeValidator = v.union(
  onboardingChatPolicyValidator,
  onboardingTTSPolicyValidator,
  onboardingTranscribePolicyValidator,
);

export const workerRequestTicketIssueResultValidator = v.object({
  token: v.string(),
  scope: workerRequestScopeValidator,
  expiresAt: v.number(),
  policyVersion: v.number(),
});

export const workerRequestTicketConsumeResultValidator = v.object({
  consumptionId: v.string(),
  policyVersion: v.number(),
  policy: workerRequestPolicyEnvelopeValidator,
});

export const workerRequestTicketCompletionResultValidator = v.object({
  didComplete: v.boolean(),
});

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

const workerRequestTicketFieldsValidator = v.object({
  ticketDigest: v.string(),
  scope: workerRequestScopeValidator,
  requestBodyDigest: v.string(),
  requestBodyByteCount: v.number(),
  actorProfileId: v.id("profiles"),
  workspaceId: v.id("workspaces"),
  membershipId: v.id("workspaceMembers"),
  personaId: v.id("personas"),
  policyVersion: v.number(),
  issuedAt: v.number(),
  expiresAt: v.number(),
});

export const workerRequestTicketValidator = v.union(
  workerRequestTicketFieldsValidator.extend({
    status: v.literal("issued"),
  }),
  workerRequestTicketFieldsValidator.extend({
    status: v.literal("consumed"),
    consumedAt: v.number(),
    consumptionId: v.string(),
    workerRequestId: v.string(),
    purgeEligibleAt: v.number(),
  }),
);

export const workerRequestAuditValidator = v.object({
  ticketId: v.id("workerRequestTickets"),
  scope: workerRequestScopeValidator,
  actorProfileId: v.id("profiles"),
  workspaceId: v.id("workspaces"),
  membershipId: v.id("workspaceMembers"),
  personaId: v.id("personas"),
  policyVersion: v.number(),
  status: workerRequestAuditStatusValidator,
  issuedAt: v.number(),
  retentionExpiresAt: v.number(),
  consumedAt: v.optional(v.number()),
  completedAt: v.optional(v.number()),
  workerRequestId: v.optional(v.string()),
  completion: v.optional(workerRequestCompletionValidator),
});
