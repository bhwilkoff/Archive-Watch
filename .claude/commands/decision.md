Log an architecture decision in DECISIONS.md.

Invoke the `architectural-decision-log` skill for the full methodology.
Short version:

1. Find the highest existing decision number in DECISIONS.md
2. If not provided in args, ask: what's the decision, what's the WHY,
   how do future contributors apply it?
3. Note which platform applies: [SHARED] / [WEB] / [tvOS]
4. Append in this format:

```
---

## NNN — Short imperative title
*Date: YYYY-MM-DD*

One paragraph stating the concrete decision. Lead with WHAT in
specific terms — avoid prose buildup; the first sentence is the
choice.

**Why**: the constraint, past incident, or alternative-rejected that
makes this choice make sense. References to bugs/projects that drove
it.

**How to apply**: when the next developer encounters this decision,
what should they do or not do?

(Optional) **Consequences**: forward-looking implications for
adjacent systems.
```

5. The entry must answer: "what would the next developer get wrong
   if they didn't know this?" If it doesn't, the entry isn't earning
   its keep — push back and ask for a sharper rationale.
6. Confirm: "Decision NNN logged"
7. NEVER edit or remove existing entries — append-only.

Note: this project's first 15 decisions (001–015) use an older
"Decision NNN — title / Decision / Rationale / Alternatives /
Trade-offs" format. Do not retro-fit them — they remain readable
and append-only is the rule. Use the new lead-with-WHY format for
all entries from 016 onward.
