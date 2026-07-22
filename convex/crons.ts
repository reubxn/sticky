import { cronJobs } from "convex/server";

import { internal } from "./_generated/api";

const crons = cronJobs();

crons.interval(
  "clean issued Worker request tickets",
  { hours: 1 },
  internal.workerRequestTicketCleanup.cleanupIssuedTickets,
  {},
);

crons.interval(
  "clean consumed Worker request tickets",
  { hours: 1 },
  internal.workerRequestTicketCleanup.cleanupConsumedTickets,
  {},
);

crons.interval(
  "clean Worker request audits",
  { hours: 1 },
  internal.workerRequestTicketCleanup.cleanupAudits,
  {},
);

export default crons;
