# Repo pattern: service -> api -> hook (kraken-role-management-fe)

## API-only services used via hooks
- services/revalidations.js -> api/revalidations.js (mounted at /management/roles/frm) -> app/hooks/useRevalidationsFrm.js (baseURL /api/management/roles/frm)
- services/application.js -> api/biso.js (route /management/roles/biso/applications) -> app/hooks/useRestclient.js (getAllApplications)

## Common base paths and hook owners
- /management/roles -> api/role.js, api/revisions.js, api/userRevisions.js, api/role-life-cycle.js, api/permissionRevisions.js -> app/hooks/useRestclient.js (baseURL /api/management/roles)
- /management/roles/configuration -> api/role-configuration.js -> app/hooks/useRoleRestClient.js
- /management/roles/permissions-request -> api/roles-permission-request.js -> app/hooks/useRestclientBiso.js
- /management/roles/collections-permissions-request -> api/roles-collections-permissions-request.js -> app/hooks/useRestclientCollectionsPermissions.js
- /management/roles/biso -> api/biso.js -> app/hooks/useRestclient.js (biso-related methods)
- /management/roles/frm -> api/revalidations.js -> app/hooks/useRevalidationsFrm.js
- /management/domains -> api/domains.js -> app/hooks/useRestclientDomains.js
- /management/subdomains -> api/subdomains.js -> app/hooks/useRestclientDomains.js

## Service call template
- Use `services/restclients/<name>.js` (krakenClient + config).
- Call `<Restclient>(req).get/post/put/delete` and return `response.data`.
- Include `headersFromReq(req)` for authenticated upstream calls.

## Hook parameter normalization patterns
- Arrays: join with commas before sending (status/types/roles/domain_key filters).
- Page index: UI uses 1-based; API expects 0-based, so decrement in hooks where needed.
- Optional params: remove undefined values before sending (see app/hooks/useRevalidationsFrm.js).

## Error handling pattern in api/
- Call service, send result, on error log with nordic/logger and forward err.response.status/data when safe.
