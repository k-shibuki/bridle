# knowledge-create

## Reads

- `docs/agent-control/knowledge-guidelines.md` (what to include/exclude, format, anti-patterns)
- `knowledge-index.mdc` (check for existing coverage before creating)

## Sense

Check `knowledge-index.mdc` trigger keywords — does an existing atom already cover this topic?

## Act

1. State the decision point in one sentence. **Indivisibility test**: can it be stated as a single question with a single answer? If not, split.
2. Choose category and name: `{category}--{topic}.md` (categories: `test`, `r`, `lint`, `debug`, `ci`, `git`, `agent`, `review`, `workflow`, `controls`).
3. `make knowledge-new NAME=<category>--<topic>`
4. Fill template: `trigger:` field (3-6 keywords), title, content (problem + resolution + example + related).
5. **Self-containment test**: can an agent make the correct decision from this file alone (plus referenced Policy)? If not, add context.
6. `make knowledge-manifest && make knowledge-validate` — both must pass.
7. Include in next commit (no separate commit needed).

## Output

- File created: `.cursor/knowledge/<name>.md`
- Index updated: `.cursor/rules/knowledge-index.mdc`
- Validation: pass/fail

## Guard

- Knowledge must NOT contain executable commands (see `knowledge-guidelines.md` § Anti-pattern)
- Knowledge must NOT declare MUST/MUST NOT rules (those belong in Principle)
