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

export const personaRecordKindValidator = v.union(
  v.literal("work_context"),
  v.literal("communication_preference"),
  v.literal("judgment_principle"),
  v.literal("expertise"),
  v.literal("boundary"),
);

export const personaRecordStateValidator = v.union(
  v.literal("active"),
  v.literal("superseded"),
  v.literal("tombstone"),
);

export const personaBoundaryModeValidator = v.union(
  v.literal("always"),
  v.literal("ask_first"),
  v.literal("never"),
);

export const personaRecordContentValidator = v.union(
  v.object({
    kind: v.literal("work_context"),
    statement: v.string(),
  }),
  v.object({
    kind: v.literal("communication_preference"),
    statement: v.string(),
  }),
  v.object({
    kind: v.literal("judgment_principle"),
    statement: v.string(),
  }),
  v.object({
    kind: v.literal("expertise"),
    statement: v.string(),
  }),
  v.object({
    kind: v.literal("boundary"),
    mode: personaBoundaryModeValidator,
    statement: v.string(),
  }),
);

export const personaVersionSourceValidator = v.union(
  v.object({
    kind: v.literal("onboarding_answer"),
    sessionId: v.id("personaOnboardingSessions"),
    sourceTurnId: v.id("personaOnboardingTurns"),
  }),
  v.object({
    kind: v.literal("manual_owner_edit"),
  }),
);

export const personaRecordSourceValidator = v.union(
  v.object({
    kind: v.literal("onboarding_explicit_answer"),
    sessionId: v.id("personaOnboardingSessions"),
    sourceTurnId: v.id("personaOnboardingTurns"),
    sourceClientTurnId: v.string(),
    evidenceExcerpt: v.string(),
  }),
  v.object({
    kind: v.literal("manual_owner_edit"),
  }),
);

export const personaOnboardingSessionStatusValidator = v.union(
  v.literal("active"),
  v.literal("paused"),
  v.literal("completed"),
);

export const personaOnboardingPauseReasonValidator = v.union(
  v.literal("userPaused"),
  v.literal("skippedForNow"),
);

export const personaOnboardingSpeakerValidator = v.union(
  v.literal("owner"),
  v.literal("sticky"),
);

export const personaOnboardingTurnKindValidator = v.union(
  v.literal("answer"),
  v.literal("introduction"),
  v.literal("question"),
  v.literal("acknowledgement"),
  v.literal("informational_summary"),
);

export const personaOnboardingInputModeValidator = v.union(
  v.literal("voice"),
  v.literal("text"),
);

export const personaOnboardingInterpretationStatusValidator = v.union(
  v.literal("pending"),
  v.literal("applied"),
);

export const personaSessionOperationValidator = v.union(
  v.literal("start"),
  v.literal("resume"),
  v.literal("pause"),
  v.literal("complete"),
);

export const personaBoundarySummaryStateValidator = v.union(
  v.literal("draft"),
  v.literal("approved"),
  v.literal("superseded"),
  v.literal("unpublished"),
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
  activatedAt: v.optional(v.number()),
  createdAt: v.number(),
  updatedAt: v.number(),
});

export const personaVersionValidator = v.object({
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

export const personaRecordValidator = v.object({
  personaId: v.id("personas"),
  membershipId: v.id("workspaceMembers"),
  workspaceId: v.id("workspaces"),
  ownerUserId: v.id("profiles"),
  recordKey: v.string(),
  versionId: v.id("personaVersions"),
  versionNumber: v.number(),
  kind: personaRecordKindValidator,
  state: personaRecordStateValidator,
  isCurrent: v.boolean(),
  content: v.optional(personaRecordContentValidator),
  deletedKind: v.optional(personaRecordKindValidator),
  source: personaRecordSourceValidator,
  confidence: v.number(),
  createdAt: v.number(),
  supersededAt: v.optional(v.number()),
  supersededByRecordId: v.optional(v.id("personaRecords")),
});

export const personaOnboardingSessionValidator = v.object({
  personaId: v.id("personas"),
  membershipId: v.id("workspaceMembers"),
  workspaceId: v.id("workspaces"),
  ownerUserId: v.id("profiles"),
  status: personaOnboardingSessionStatusValidator,
  pauseReason: v.optional(personaOnboardingPauseReasonValidator),
  revision: v.number(),
  turnCount: v.number(),
  nextSequence: v.number(),
  lastClientMutationId: v.optional(v.string()),
  startedAt: v.number(),
  updatedAt: v.number(),
  pausedAt: v.optional(v.number()),
  completedAt: v.optional(v.number()),
});

export const personaOnboardingTurnValidator = v.object({
  sessionId: v.id("personaOnboardingSessions"),
  personaId: v.id("personas"),
  membershipId: v.id("workspaceMembers"),
  workspaceId: v.id("workspaces"),
  ownerUserId: v.id("profiles"),
  turnId: v.string(),
  clientMutationId: v.string(),
  sequence: v.number(),
  speaker: personaOnboardingSpeakerValidator,
  kind: personaOnboardingTurnKindValidator,
  text: v.string(),
  inputMode: v.optional(personaOnboardingInputModeValidator),
  interpretationStatus: v.optional(
    personaOnboardingInterpretationStatusValidator,
  ),
  interpretationClientMutationId: v.optional(v.string()),
  interpretationRequestFingerprint: v.optional(v.string()),
  interpretedVersionId: v.optional(v.id("personaVersions")),
  createdAt: v.number(),
});

export const personaSessionOperationReceiptValidator = v.object({
  personaId: v.id("personas"),
  sessionId: v.id("personaOnboardingSessions"),
  membershipId: v.id("workspaceMembers"),
  workspaceId: v.id("workspaces"),
  ownerUserId: v.id("profiles"),
  clientMutationId: v.string(),
  operation: personaSessionOperationValidator,
  requestFingerprint: v.string(),
  resultStatus: personaOnboardingSessionStatusValidator,
  resultRevision: v.number(),
  resultSetupState: personaSetupStateValidator,
  createdAt: v.number(),
});

export const personaBoundarySummaryValidator = v.object({
  personaId: v.id("personas"),
  membershipId: v.id("workspaceMembers"),
  workspaceId: v.id("workspaces"),
  ownerUserId: v.id("profiles"),
  summaryText: v.string(),
  sourceVersionNumber: v.number(),
  state: personaBoundarySummaryStateValidator,
  clientMutationId: v.string(),
  requestFingerprint: v.string(),
  approvalClientMutationId: v.optional(v.string()),
  approvalRequestFingerprint: v.optional(v.string()),
  unpublishClientMutationId: v.optional(v.string()),
  unpublishRequestFingerprint: v.optional(v.string()),
  createdAt: v.number(),
  approvedAt: v.optional(v.number()),
  supersededAt: v.optional(v.number()),
  unpublishedAt: v.optional(v.number()),
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
