# A document with a diagram

This page exercises the Mermaid side of the Markdown pipeline: the code
block below is turned into a drawing by the browser, using the runtime that
is inlined into the page.

```mermaid
stateDiagram-v2
    direction LR
    state "scan — repo" as scan
    state "f1 — one.mbt" as f1
    state "f2 — two.mbt" as f2
    scan --> f1 : 0 actionable, 1 notice(s), parsed
    scan --> f2 : 1 actionable, 2 notice(s), parsed
```

## And some text

| file | actionable | notices |
| --- | --- | --- |
| f1 | 0 | 1 |
| f2 | 1 | 2 |

- a list item
- another one
- [x] a task item
