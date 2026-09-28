# Nordic API Validation Middleware Layout

For REST routes under api/, follow security.md#input-validation for validation behavior and schema scope. Use this rule for module placement and imports.

- Put route-specific @meli/input-validation schemas and iv.createValidationMiddleware(...) declarations under api/middlewares/validation/, with one module per resource or related route group.
- Export named middleware with names that identify the resource and request part, such as usersQueryValidationMiddleware or feedbackValidationMiddleware.
- Re-export those middleware from api/middlewares/validation/index.js in JavaScript projects or index.ts in TypeScript projects.
- Import middleware from the validation directory barrel, for example ./middlewares/validation; do not import each resource module directly from route files.
- Keep the barrel limited to named re-exports. Do not define schemas, add route logic, or call services in index.js / index.ts.
- Keep route modules responsible for mounting validation, authorization, and handlers. Mount validation before authorization and before any middleware or handler that reads the validated request fields.
- Match each schema to the exact req.query, req.body, or req.params properties consumed by its route. Do not add validation for unrelated routes or backend/upstream response payloads.

Example layout:

~~~text
api/
  index.js
  teams.js
  middlewares/
    validation/
      index.js
      teams.js
~~~

Resource validation module:

~~~js
import * as iv from '@meli/input-validation';

export const teamsQueryValidationMiddleware = iv.createValidationMiddleware({
  schema: {
    query: iv.object({
      teamKey: iv.string().secure(),
    }),
  },
});
~~~

Barrel:

~~~js
export { teamsQueryValidationMiddleware } from './teams';
~~~

Route import:

~~~js
import { teamsQueryValidationMiddleware } from './middlewares/validation';
~~~
