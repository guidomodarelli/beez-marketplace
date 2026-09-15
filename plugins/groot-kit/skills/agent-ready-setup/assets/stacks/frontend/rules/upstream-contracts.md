# Outbound Upstream Contract Rules — BFF

These rules apply to payloads that the BFF sends to an upstream endpoint. They complement the input-validation rules: an outbound request payload is not an upstream response and is not a public middleend DTO.

## Payload ownership

- Treat every request body sent by the BFF to an upstream endpoint as an endpoint-specific contract owned by the adapter or service boundary.
- Keep the outbound payload as a named, complete entity for one upstream operation, such as `CreateShipmentUpstreamRequest` or `buildCreateShipmentPayload`.
- Keep outbound payload construction separate from the client request, the public middleend DTO, the upstream response type, headers, query parameters, and transport configuration.
- Do not pass `req.body` directly to an upstream client, and do not use `{ ...req.body }` as a substitute for explicit mapping. Explicit mapping prevents client-only fields from leaking and makes upstream contract changes easy to locate.
- Build the payload from input that has already been validated at the middleend boundary, plus the domain or integration context required by the upstream contract. Do not move public-input validation into the payload builder.
- Centralize upstream-specific field names, transformations, defaults, and conditional nested sections in the payload factory or builder. The adapter should send the built entity without hidden mutation.
- Keep optional fields omitted unless the upstream contract or business rule requires them; complete means all fields required for the operation are assembled, not that every optional field is populated.

## Factory versus builder

- For a simple payload, use a named object or small factory function close to the adapter; do not add ceremonial builder classes.
- Use a builder when the payload has meaningful composition, conditional sections, repeated transformations, or multiple construction steps. Keep one builder or factory per upstream operation rather than one generic builder for unrelated endpoints.
- Prefer names that identify both operation and upstream boundary, such as `buildCreateShipmentUpstreamRequest`, so the request contract is searchable from the endpoint integration.

## Validation boundary

- Validate untrusted client input once at the middleend boundary using the repository's approved validation mechanism.
- Do not add runtime schema validation of an upstream response or error payload. Consume responses according to the adapter contract and use only the minimal structural narrowing required for control flow, as described in the payload-validation boundary rule.
- Do not treat a payload factory as a reason to revalidate an already validated request or to verify the provider's response shape.

## Tests

- Test the observable outbound contract by asserting the request body received by the project's real HTTP mock or integration test boundary.
- Cover required fields, upstream-specific transformations, conditional sections, omission of client-only fields, and operation-specific defaults.
- Do not mock the platform HTTP client when the repository provides a real HTTP interception mechanism; use that mechanism to verify the actual request sent to the upstream endpoint.
