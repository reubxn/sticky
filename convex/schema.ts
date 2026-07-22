import { defineSchema, defineTable } from "convex/server";

import {
  personaValidator,
  profileValidator,
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
});
