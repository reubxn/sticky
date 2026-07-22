import { defineSchema, defineTable } from "convex/server";

import {
  personaValidator,
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
