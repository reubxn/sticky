import { v } from "convex/values";

import { query } from "./_generated/server";

export const check = query({
  args: {},
  returns: v.object({
    service: v.literal("sticky-convex"),
    status: v.literal("ok"),
  }),
  handler: async () => {
    return {
      service: "sticky-convex" as const,
      status: "ok" as const,
    };
  },
});
