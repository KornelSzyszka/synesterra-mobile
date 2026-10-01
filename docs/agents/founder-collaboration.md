# Founder collaboration

The Founder is the Technical Product Owner and Musical Director. The Founder owns:
- product direction and release scope;
- musical quality and how the rhythm feels;
- technical decisions that are expensive to reverse;
- business model, spending and public promises;
- the decision to publish.

Agents produce evidence, recommendations, implementation, tests and documentation.

## How it is marked on an issue

- `founder-review` label: the Founder reviews the result before the task is done.
- `decision-gate` label plus the gate name in the Agent brief: `product`, `experience`, `musical`, `business`, `architecture`, `release`.
- No label: agents may finish the task against its acceptance criteria.

| Gate | When |
|---|---|
| `product` | audience, problem, release scope or priority changes |
| `experience` | the main flow or behaviour during an active session changes |
| `musical` | musical semantics or feel change (swing, phase, accent, improvisation rules) |
| `business` | price, monetisation, spending or a public promise |
| `architecture` | a decision that is hard to reverse or crosses key boundaries (session model, audio backend, platform) |
| `release` | publishing, distribution or another irreversible external operation |

## Stop rule

Work alone up to the last safe, reversible point. With an active gate:

1. put the result and evidence in the PR or the issue;
2. leave the PR open and say what is waiting for the Founder;
3. send the decision package below;
4. publish nothing, buy nothing and make no hard-to-reverse change before the answer;
5. after the answer, record the decision in [docs/decisions/](../decisions/README.md) and update the dependent issues.

Gates block only the part of the work that depends on them; other safe work continues. A gate is not for approving every small step.

## Decision package

```markdown
Decision: one sentence
Options: A / B (/ C) — cost, risk, reversibility
Recommendation: option + why
Evidence: paths, tests, measurements
If undecided: what waits
```
