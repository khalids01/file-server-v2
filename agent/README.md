# File Server v2 implementation notes

Start with [the active product roadmap](01-replacement-plan.md) and [current status](status.md).

V2 is an independent product with the hierarchy **User → Applications → Files/storage settings/API keys**. V1 SDK compatibility, legacy routes, old public URLs and workspaces are not requirements. Authentication is GitHub and email OTP only.

Current documentation:

- [Active roadmap](01-replacement-plan.md): file management, sharing, analytics and operations.
- [Execution backlog](07-execution-backlog.md): ordered milestones and acceptance checks.
- [Status](status.md): verified delivery and remaining work.
- [Authentication](04-authentication.md): current auth behavior; older methods are superseded.
- [Project structure](../docs/project-structure.md), [v2 API](../docs/file-api.md), [quotas/images](../docs/storage-reliability-images.md).

The v1 parity matrix, tenancy design, storage/API parity design, migration/cutover design, MVP delivery log and older storage milestone are historical context only. Their compatibility/workspace/password requirements are superseded by the active roadmap and current user instructions. Keep v1 unchanged. Extend this existing Phoenix app; do not regenerate it.

Follow `../AGENTS.md`, test only against disposable fixtures, and use the configured human Git identity without AI attribution.
