## Rules

{{AGENT_READY_RULE_REFERENCES}}

## Skills

- **`/component-creation`**: Create a React component with Andes UI and Nordic. Use when asked to create a component, widget, or UI element.
- **`/api-endpoint`**: Create a Nordic API endpoint — server hook (`getServerSideProps`) or REST endpoint in `/api`. Use when adding a new endpoint or API route.
- **`/service`**: Create a service layer for external API calls. Use when adding a new service, API client, or data-fetching layer.
- **`/constants-refactor`**: Analyze and refactor static constants, functional literals, and cross-layer contracts into cohesive `constants/` modules. Use when creating, modifying, moving, or reviewing constants.
- **`/logger`**: Set up a shared logger utility in `/utils` using `nordic/logger`. Run this first before `/api-endpoint`.
- **`/karpathy-guidelines`**: Behavioral guidelines to reduce common LLM coding mistakes. Use when writing, reviewing, or refactoring code.
