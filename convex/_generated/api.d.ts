/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as accounts from "../accounts.js";
import type * as authorization from "../authorization.js";
import type * as crons from "../crons.js";
import type * as health from "../health.js";
import type * as http from "../http.js";
import type * as identity from "../identity.js";
import type * as personaBoundarySummaries from "../personaBoundarySummaries.js";
import type * as personaFoundation from "../personaFoundation.js";
import type * as personaOnboarding from "../personaOnboarding.js";
import type * as personaOnboardingContext from "../personaOnboardingContext.js";
import type * as personaRecords from "../personaRecords.js";
import type * as requestTickets from "../requestTickets.js";
import type * as validators from "../validators.js";
import type * as workerRequestPolicy from "../workerRequestPolicy.js";
import type * as workerRequestTicketCleanup from "../workerRequestTicketCleanup.js";
import type * as workerRequestTicketMutations from "../workerRequestTicketMutations.js";
import type * as workerServiceBridge from "../workerServiceBridge.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  accounts: typeof accounts;
  authorization: typeof authorization;
  crons: typeof crons;
  health: typeof health;
  http: typeof http;
  identity: typeof identity;
  personaBoundarySummaries: typeof personaBoundarySummaries;
  personaFoundation: typeof personaFoundation;
  personaOnboarding: typeof personaOnboarding;
  personaOnboardingContext: typeof personaOnboardingContext;
  personaRecords: typeof personaRecords;
  requestTickets: typeof requestTickets;
  validators: typeof validators;
  workerRequestPolicy: typeof workerRequestPolicy;
  workerRequestTicketCleanup: typeof workerRequestTicketCleanup;
  workerRequestTicketMutations: typeof workerRequestTicketMutations;
  workerServiceBridge: typeof workerServiceBridge;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {};
