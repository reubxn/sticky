export const workerServiceHmacVector = {
  method: "POST",
  path: "/internal/worker/request-tickets/consume",
  timestamp: "1800000000000",
  requestId: "worker_vector_request_0001",
  body:
    '{"expectedRequestBodyByteCount":42,"expectedRequestBodyDigest":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","expectedScope":"onboarding_chat","ticketDigest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","workerRequestId":"worker_request_vector_0001"}',
  bodyDigest:
    "c35fae2fe6daa92fb9f5fa3142616fe0c4b937ec8631e33bb54d7390a19c80bc",
  keyId: "test-key-2026-07",
  key: "sticky-test-hmac-key-material-2026-07",
  signature:
    "30e6f447b805361e535cb7a572e4cf84ae9c5e748540954d834a761a1b109dc3",
} as const;
