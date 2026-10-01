# Model outcome log

One JSON file per task in `logs/outcomes/<TASK-ID>.json`, added when the task reaches `review` or `done`. One file per task means parallel branches never conflict and a PR diff shows exactly one new record. Purpose: measure `P(success | class, size, risk)` for the routing rules in [docs/agents/model-routing.md](../docs/agents/model-routing.md). No secrets and no conversation content.

CI runs `dart run tool/model_log.dart check`. Locally:

```text
dart run tool/model_log.dart check      # validate
dart run tool/model_log.dart summary    # success rate per class x size x risk (estimate only from n >= 5)
```

Ad hoc analysis without installing anything into the repo, for example with [DuckDB](https://duckdb.org):

```sql
SELECT size, risk, model, count(*) AS n, avg(success::int) AS success_rate
FROM read_json('logs/outcomes/*.json')
GROUP BY ALL ORDER BY n DESC;
```

## Fields

Required (never null):

| Field | Values |
|---|---|
| `date` | `YYYY-MM-DD` |
| `task` | task ID, equal to the file name |
| `prefix` | `AGT`, `DOM`, `AUD`, `UX`, `MOB`, `QA`, `REL` |
| `size` | `S`, `M`, `L` |
| `risk` | `none`, `risk-ux`, `risk-scope`, `risk-platform`, `risk-audio` (the highest one) |
| `agent` | `claude`, `codex` |
| `model` | a model known to `tool/model_log.dart`; the class floor is enforced from it |
| `success` | `true`: acceptance criteria met with no class change and no rewrite by another agent; otherwise `false` |
| `attempts` | integer >= 1; a new hypothesis counts as a new attempt |
| `evidence` | highest level reached: `static`, `unit`, `widget`, `emulator`, `device`. An emulator is not evidence of listening quality |
| `notes` | string, may be empty; put the reviewer here |

Optional (`null` when not applicable):

| Field | Values |
|---|---|
| `reasoning` | `low`, `medium`, `high` |
| `escalation` | free text: what was raised and why |
| `error_type` | required when `success` is `false` or `attempts` > 1, otherwise `null`: `random`, `misread-task`, `missing-context`, `model-limit`, `environment`. Only `misread-task`, `missing-context` and `model-limit` count against a model's success rate; other failures are excluded from the summary |
| `review` | `ok`, `changes`, `blocked` |
| `ci` | `green`, `red-green`, `red` |
| `failure_cost` | required when `success` is `false`: `L` code fix, `M` manual diagnosis, `H` device or user-data impact |
| `minutes` | integer, wall time from worker start to `review` |
| `tokens` | integer, from Orca or the CLI when available |

Unknown fields are rejected. A new model must be added to `_modelClass` in `tool/model_log.dart` together with its class.
