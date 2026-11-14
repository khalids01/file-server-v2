# Active execution backlog

This replaces the original parity backlog. See [the product roadmap](01-replacement-plan.md). No v1 compatibility work is planned.

| Order | Milestone | Acceptance |
| --- | --- | --- |
| 1 | File management experience | Grid/list URLs, private details/preview, upload progress/cancel/reselection, bounded bulk delete/tags, honest copy-link feedback; ownership and partial-failure tests |
| Deferred | Optional controlled sharing | Explicit expiring/revocable tokens, narrow permissions, private defaults, abuse limits and access tests |
| Delivered | Application visibility | Live Usage & recovery UI, scoped API, per-app storage totals, processing/cleanup state and recovery buttons |
| Next | Production operations | Backup/restore, transfer/retention design, resource limits, monitoring and isolated staging rehearsal |
| Optional | Chosen data imports | Resumable manifests, counts/checksums and authorization; no legacy API or credential compatibility |

Every milestone requires focused tests plus `mix precommit`, `mix assets.build`, `mix ash.codegen --check` and `node --test test/js/*_test.mjs`. Document actual verification and limitations. Real-provider or production changes require their own authorized scope. The sole Git contributor is the configured human owner.
