import { defineSchema, defineTable } from "convex/server";

import {
  personaBoundarySummaryValidator,
  personaOnboardingSessionValidator,
  personaOnboardingTurnValidator,
  personaRecordValidator,
  personaSessionOperationReceiptValidator,
  personaValidator,
  personaVersionValidator,
  profileValidator,
  workerRequestAuditValidator,
  workerRequestTicketValidator,
  workspaceMemberValidator,
  workspaceValidator,
} from "./validators";

export default defineSchema({
  profiles: defineTable(profileValidator)
    .index("by_tokenIdentifier", ["tokenIdentifier"]),

  workspaces: defineTable(workspaceValidator)
    .index("by_createdByProfileId_and_kind", [
      "createdByProfileId",
      "kind",
    ]),

  workspaceMembers: defineTable(workspaceMemberValidator)
    .index("by_workspaceId_and_userId_and_status", [
      "workspaceId",
      "userId",
      "status",
    ])
    .index("by_userId_and_status", ["userId", "status"])
    .index("by_workspaceId_and_status", ["workspaceId", "status"])
    .index("by_workspaceId_and_status_and_role", [
      "workspaceId",
      "status",
      "role",
    ]),

  personas: defineTable(personaValidator)
    .index("by_membershipId", ["membershipId"])
    .index("by_workspaceId_and_ownerUserId_and_status", [
      "workspaceId",
      "ownerUserId",
      "status",
    ])
    .index("by_workspaceId_and_status", ["workspaceId", "status"]),

  personaVersions: defineTable(personaVersionValidator)
    .index("by_personaId_and_versionNumber", ["personaId", "versionNumber"])
    .index("by_personaId_and_clientMutationId", [
      "personaId",
      "clientMutationId",
    ])
    .index("by_membershipId", ["membershipId"]),

  personaRecords: defineTable(personaRecordValidator)
    .index("by_personaId_and_isCurrent_and_state_and_kind", [
      "personaId",
      "isCurrent",
      "state",
      "kind",
    ])
    .index("by_personaId_and_recordKey_and_isCurrent", [
      "personaId",
      "recordKey",
      "isCurrent",
    ])
    .index("by_versionId", ["versionId"])
    .index("by_membershipId", ["membershipId"]),

  personaOnboardingSessions: defineTable(personaOnboardingSessionValidator)
    .index("by_personaId", ["personaId"])
    .index("by_membershipId", ["membershipId"]),

  personaOnboardingTurns: defineTable(personaOnboardingTurnValidator)
    .index("by_sessionId_and_sequence", ["sessionId", "sequence"])
    .index("by_sessionId_and_turnId", ["sessionId", "turnId"])
    .index("by_sessionId_and_clientMutationId", [
      "sessionId",
      "clientMutationId",
    ])
    .index("by_membershipId", ["membershipId"]),

  personaSessionOperationReceipts: defineTable(
    personaSessionOperationReceiptValidator,
  )
    .index("by_personaId_and_clientMutationId", [
      "personaId",
      "clientMutationId",
    ])
    .index("by_sessionId_and_clientMutationId", [
      "sessionId",
      "clientMutationId",
    ])
    .index("by_membershipId", ["membershipId"]),

  personaBoundarySummaries: defineTable(personaBoundarySummaryValidator)
    .index("by_personaId_and_state", ["personaId", "state"])
    .index("by_personaId_and_clientMutationId", [
      "personaId",
      "clientMutationId",
    ])
    .index("by_personaId_and_approvalClientMutationId", [
      "personaId",
      "approvalClientMutationId",
    ])
    .index("by_personaId_and_unpublishClientMutationId", [
      "personaId",
      "unpublishClientMutationId",
    ])
    .index("by_membershipId", ["membershipId"]),

  workerRequestTickets: defineTable(workerRequestTicketValidator)
    .index("by_ticketDigest", ["ticketDigest"])
    .index("by_actorProfileId_and_scope_and_issuedAt", [
      "actorProfileId",
      "scope",
      "issuedAt",
    ])
    .index("by_actorProfileId_and_scope_and_status_and_expiresAt", [
      "actorProfileId",
      "scope",
      "status",
      "expiresAt",
    ])
    .index("by_status_and_expiresAt", ["status", "expiresAt"])
    .index("by_status_and_purgeEligibleAt", [
      "status",
      "purgeEligibleAt",
    ]),

  workerRequestAudits: defineTable(workerRequestAuditValidator)
    .index("by_ticketId", ["ticketId"])
    .index("by_actorProfileId_and_issuedAt", [
      "actorProfileId",
      "issuedAt",
    ])
    .index("by_retentionExpiresAt", ["retentionExpiresAt"]),
});
