# Model outcome log

One row per task, appended when the task reaches `review` or `done`. Purpose: measure `P(success | class, size, risk)` for the routing rules in [docs/agents/model-routing.md](../docs/agents/model-routing.md). No secrets and no conversation content. Validated in CI by `tool/check_model_log.dart`.

## Fields

| Field | Values |
|---|---|
| `date` | `YYYY-MM-DD` |
| `task` | task ID, unique in this file |
| `prefix` | `AGT`, `DOM`, `AUD`, `UX`, `MOB`, `QA`, `REL` |
| `size` | `S`, `M`, `L` |
| `risk` | `-`, `risk-ux`, `risk-scope`, `risk-platform`, `risk-audio` (the highest one) |
| `agent` | `claude`, `codex` |
| `model` | a model known to `tool/check_model_log.dart` (the class floor is enforced from it) |
| `reasoning` | `low`, `medium`, `high`, `-` |
| `success` | `yes`: acceptance criteria met with no class change and no rewrite by another agent; otherwise `no` |
| `attempts` | integer >= 1; a new hypothesis counts as a new attempt |
| `escalation` | free text: what was raised and why, or `-` |
| `error type` | required when `success` is `no` or `attempts` > 1, otherwise `-`: `random`, `misread-task`, `missing-context`, `model-limit`, `environment`. Only `misread-task`, `missing-context` and `model-limit` count against a model's success rate |
| `review` | `ok`, `changes`, `blocked`, `-` (the reviewer goes in `notes`) |
| `ci` | `green`, `red-green`, `red`, `-` |
| `evidence` | highest level reached: `static`, `unit`, `widget`, `emulator`, `device`. An emulator is not evidence of listening quality |
| `failure cost` | when `success` is `no`: `L` code fix, `M` manual diagnosis, `H` device or user-data impact; otherwise `-` |
| `minutes` | wall time from worker start to `review`, may be empty |
| `tokens` | from Orca or the CLI when available, may be empty |

## Entries

| date | task | prefix | size | risk | agent | model | reasoning | success | attempts | escalation | error type | review | ci | evidence | failure cost | minutes | tokens | notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-10-01 | AGT-002 | AGT | S | - | codex | gpt-6-sol | medium | yes | 2 | CLI updated | environment | - | - | static | - |  |  | first attempt failed on an outdated CLI, not on the model |
| 2026-10-01 | AGT-001 | AGT | M | risk-platform | claude | claude-opus-5-5 | medium | yes | 1 | - | - | - | - | widget | - |  |  | workspace bootstrap and flutter create |
| 2026-10-01 | MOB-001 | MOB | S | risk-platform | claude | claude-opus-5-5 | medium | yes | 1 | - | - | ok | green | static | - |  |  | reviewed by codex gpt-5.6-terra; Linux CI green, iOS not built (manual only) |
| 2026-10-01 | AGT-003 | AGT | M | - | claude | claude-opus-5-5 | medium | yes | 1 | - | - | ok | green | static | - |  |  | reviewed by codex gpt-5.6-terra (PR #1); first full PR, CI, review and merge cycle |

## Summary

Update at each review (about every 20 entries, or after two failures in one cell). Estimate a success rate only from five or more tasks per (class, size, risk) cell.

| class x size x risk | n | successes | success rate | notes |
|---|---:|---:|---|---|
| no data |  |  |  |  |
