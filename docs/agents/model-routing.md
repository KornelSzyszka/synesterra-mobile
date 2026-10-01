# Model routing

Version 0: qualitative rules, to be refined with measured outcomes.

## Principle

Pick the model class by expected cost of a solved task, not by cost per attempt:

`expected cost = attempt cost + P(failure) x failure cost + latency cost`

For this project the failure cost dominates. A failed audio-timing change costs a build, a device install and a listening test, which is far more than the tokens of any model.

## Classes

| Class | Typical work |
|---|---|
| `S` | inventory, status checks, small mechanical edits, running a command |
| `M` | scoped implementation, tests, focused review |
| `L` | multi-module architecture, audio timing, native code, data migration |
| `X` | cross-domain synthesis, conflicting evidence, large blast radius |

## Minimum class (hard floor)

| Failure cost (risk tag) | size `S` | size `M` | size `L` |
|---|---|---|---|
| low: no risk tag, easy to revert | `S` | `M` | `M`, reviewed at `L` |
| medium: `risk-platform` (build, gradle/xcode, persistence) | `M` | `M` | `L` |
| high: `risk-audio`, user-data corruption, physical device is the only proof | `L` | `L` | `L` + review by another agent |

The table is a floor, not the final choice: within the allowed classes prefer the model with the lowest expected cost once outcome data exists. Never use class `S` for `lib/audio/`, `android/`, `ios/` or data migrations.

## Escalation

- Raise reasoning effort before changing the model.
- A repeated failure needs a new hypothesis or a higher class, not an identical retry. Retries of the same model on the same task are correlated, not independent trials.
- Change class when: two reasonable attempts failed; the decision crosses three or more module boundaries; an error could corrupt user data, audio timing or platform compatibility; requirements stay contradictory after research.

## Cost reference

Official API prices, USD per 1M tokens (standard tier), checked 2026-10-01:
[Anthropic](https://platform.claude.com/docs/en/about-claude/pricing), [OpenAI](https://developers.openai.com/api/docs/pricing).

| Class | Model | Input | Output |
|---|---|---:|---:|
| S | `claude-haiku-4-5` | 1 | 5 |
| S | `gpt-5.6-luna` | 0.20 | 1.20 |
| M | `claude-sonnet-5-5` | 2 | 10 |
| M | `gpt-5.6-terra` | 2 | 12 |
| L | `claude-opus-5-5` | 4 | 20 |
| L | `gpt-6-sol` | 2 | 10 |
| X | `claude-fable-5-1` | 10 | 50 |
| X | `gpt-6-astra` | 10 | 50 |

A typical worker attempt (assumed 300k input and 30k output tokens, no caching) costs roughly $0.10 to $4.50 across all classes. This is small next to an hour of manual diagnosis, which is why the floor above does not depend on token price. Claude models from 4.7 on use about 30% more tokens for the same text. On subscriptions the marginal cost is usage quota, not dollars.

## Benchmarks are not priors

Public benchmark scores come from secondary sources, differ by benchmark version and mode, and disagree on model order (for example Sonnet 5.5 ahead of Opus 5.5 on one Terminal-Bench version, behind it on SWE-Bench Pro). None of them measures Dart/Flutter, audio timing or on-device behaviour. Use them at most to order models within a class. Success probabilities must come from this project's own task outcomes.

## Outcome logging

After each task append a row to [`logs/model-outcomes.md`](../../logs/model-outcomes.md); CI validates it with `tool/check_model_log.dart` (schema, allowed values, model class floor). The row records: date, task ID, size, risk tag, agent, model, reasoning effort, success (criteria met without a class change or rewrite by another agent), attempts, escalation, error type (`random`, `misread task`, `missing context`, `model limit`, `environment`), review verdict, CI result, highest evidence level reached, failure cost, wall time. Only `misread task`, `missing context` and `model limit` count against a model's success rate; `environment` and `random` do not. Estimate success rates per (class, size, risk) cell only from five or more tasks.
