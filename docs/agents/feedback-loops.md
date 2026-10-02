# Feedback loops

How information flows back into the work. This document describes the mechanism; the rules each loop relies on live in the linked documents and are not repeated here.

Loops are ordered from fast and cheap (L1) to slow and expensive (L4, L5) and then to the loops that change the process itself (L6, L7).

```text
change ──L1 local──► PR ──L2 CI──► L3 cross-agent review ──► merge ──► L4 device
                      │                                                   │
                      └──────────── L6 outcome log ◄──────────────────────┘
                                          │
              L5 Founder gates ◄── L7 retrospective (after every wave) ──► rules
```

## The loops

| Loop | Trigger | Signal | Reaction | Owner | Defined in |
|---|---|---|---|---|---|
| L1 local check | every change | the local checks the author runs before pushing | fix before pushing | author | [AGENTS.md](../../AGENTS.md), [review-and-merge.md](review-and-merge.md) |
| L2 CI | push, PR | the CI result | fix on the same branch | author | [ci.yml](../../.github/workflows/ci.yml), [review-and-merge.md](review-and-merge.md) |
| L3 cross-agent review | open PR | the review verdict and findings by severity | blocking findings go back to the author, then re-review | reviewer (not the author) | [review-and-merge.md](review-and-merge.md) |
| L4 device proof | a change whose result can only be judged on a device (audio, feel, UX on a phone) | evidence from a device, against criteria fixed beforehand | a fix or a new issue; the Founder is involved only when the issue has `founder-review` or a `decision-gate` | task owner, `qa-release` | [docs/testing.md](../testing.md) |
| L5 Founder gate | `decision-gate` or `founder-review` | the decision package | decision recorded in `docs/decisions/`, dependent issues updated | Founder, coordinator | [founder-collaboration.md](founder-collaboration.md) |
| L6 outcome log | a task reaches review or done | `logs/outcomes/<TASK-ID>.json` | none by itself: it only collects data | author | [model-routing.md](model-routing.md), [logs/README.md](../../logs/README.md) |
| L7 retrospective | the end of every wave (one Orca Run) | inputs listed below | conclusions, then deliberate rule changes through a normal task | coordinator | this document |

L1 to L3 run without the Founder. The Founder joins at L5, and at L4 only when the issue requires it ([founder-collaboration.md](founder-collaboration.md)).

## L4: the expensive quality loop

L4 costs a build, an install and a hands-on session, so it is used on purpose and not as a routine check. What counts as evidence, and how a device hand-off is written, is defined in [AGENTS.md](../../AGENTS.md) and [docs/testing.md](../testing.md).

This document adds one rule: for audio and UX, the acceptance criteria are fixed in the issue before the device test, so the result is not judged after the fact. Concrete thresholds belong to the spike's issue or to the testing docs.

## L6: collect, do not decide

L6 records honest attempts, the error type and the outcome. A failure count alone does not change any rule. The log answers "what happened"; L7 decides "what do we change".

## L7: retrospective after every wave

Run it when the wave's Orca Run closes (or, outside Orca, when its last PR merges). It is short: the coordinator reads the inputs, writes the conclusions in a single issue or PR comment, and opens a task for every rule change.

### Inputs

1. **Outcome log.** `dart run tool/model_log.dart summary` and the wave's new `logs/outcomes/*.json`.
2. **Routing trigger.** Two consecutive failures in the same task class and domain start a routing review (below). The count is a prompt to look, not a verdict.
3. **Repeated failure modes.** Any failure mode that appeared more than once in L2 (CI) or L3 (review) findings.
4. **Unplanned Founder escalations.** Anything that reached the Founder without a gate planned in the issue.
5. **Decomposition and routing.** Tasks that were split badly, merged badly, given to the wrong role or agent, or had the wrong task class.
6. **Queue state.** `gh pr list` and `gh issue list`; never a stale hand-off note.

### Routing review

Started by the trigger in input 2. It decides the cause before anyone touches a rule. Allowed causes:

| Cause | Typical change |
|---|---|
| model capability | none to routing yet; check whether another attempt at a higher class is justified for this task only |
| bad brief | rewrite the Agent brief or the issue template |
| bad decomposition | split or merge tasks differently; write the lesson down |
| missing context | add the missing file to the brief or to a doc the brief links |
| tooling or CI problem | fix the tool; the failure does not count against the model |
| wrong task class | correct the class or the floor for that kind of work |

Only the result of this review may change [model-routing.md](model-routing.md). Routing changes are a deliberate rule change made through a normal task, never an automatic reaction to a failure count.

### Outputs

- A short conclusion per input that had something to report.
- For each problem that should not return, a rule added to [AGENTS.md](../../AGENTS.md) or `docs/agents/*`, through its own `AGT` task and PR.
- Issues for work that was deferred.
- Nothing, when nothing happened. A wave with no findings is a valid result.

## What this document does not do

It does not set audio thresholds, change model routing, or add automation. A recurring check may be proposed as a hook, but a hook is enabled only with the Founder's explicit consent.
