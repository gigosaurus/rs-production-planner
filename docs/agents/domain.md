# Domain Docs

This file tells the engineering skills how to use the domain documents of this repo when they explore the codebase.

## Before you explore, read these

- **`GLOSSARY.md`** at the repo root, or
- **`GLOSSARY-MAP.md`** at the repo root, if it exists. It points to one `GLOSSARY.md` for each context. Read each one that applies to the topic.
- **`docs/adr/`**: read the ADRs that touch the area where you will work. In a repo with more than one context, also examine `src/<context>/docs/adr/` for decisions about one context.

If some of these files do not exist, **continue and say nothing**. Do not report that they are missing. Do not suggest that someone creates them first. The `/domain-modeling` skill (through `/grill-with-docs` and `/improve-codebase-architecture`) creates them when terms or decisions are resolved.

## File structure

Repo with one context (most repos):

```
/
├── GLOSSARY.md
├── docs/adr/
│   ├── 0001-event-sourced-orders.md
│   └── 0002-postgres-for-write-model.md
└── src/
```

Repo with more than one context (a `GLOSSARY-MAP.md` is at the root):

```
/
├── GLOSSARY-MAP.md
├── docs/adr/                          ← decisions for all of the system
└── src/
    ├── ordering/
    │   ├── GLOSSARY.md
    │   └── docs/adr/                  ← decisions for one context
    └── billing/
        ├── GLOSSARY.md
        └── docs/adr/
```

## Use the vocabulary of the glossary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis or a test name), use the term that `GLOSSARY.md` defines. Do not change to a synonym that the glossary tells you to avoid.

If the glossary does not have the concept that you need, this is a signal. Possibly you are making up words that the project does not use. Then think again. Or possibly the glossary has a real gap. Then record it for `/domain-modeling`.

## Report ADR conflicts

If your output contradicts an ADR, say so clearly. Do not override the ADR silently:

> _This contradicts ADR 0003 (no stored progress). But it is worth opening again, because…_
