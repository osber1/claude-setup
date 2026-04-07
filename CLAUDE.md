### Code Intelligence
Prefer LSP over Grep/Glob/Read for code navigation:
- `goToDefinition` / `goToImplementation` to jump to source
- `findReferences` to see all usages across the codebase
- `workspaceSymbol` to find where something is defined
- `documentSymbol` to list all symbols in a file
- `hover` for type info without reading the file
- `incomingCalls` / `outgoingCalls` for call hierarchy

Before renaming or changing a function signature, use
`findReferences` to find all call sites first.

Use Grep/Glob only for text/pattern searches (comments,
strings, config values) where LSP doesn't help.

After writing or editing code, check LSP diagnostics before
moving on. Fix any type errors or missing imports immediately.

### Approach
- Think before acting. Read existing files before writing code.
- Be concise in output, no sycophantic openers or closing fluff.
- Prefer editing over rewriting whole files.
- Do not re-read files you have already read unless the file may have changed.
- Keep solutions simple and direct. Minimize the amount of code generated.

### Plan Mode
- Enter plan mode for any task with 3+ steps or architectural decisions.
- Use plan mode for verification steps, not just building.
- Write detailed specs upfront to reduce ambiguity.

### Self-Improvement Loop
- At session start, read `tasks/lessons.md` if it exists.
- After any correction from the user, update `tasks/lessons.md` with the pattern.
- Write rules that prevent the same mistake from recurring.

### Verification Before Done
- Never mark a task complete without running tests and verifying correctness.
- Diff behavior between your changes and the previous state when relevant.

### Simplicity & Elegance
- For non-trivial changes, pause and ask: "is there a more elegant way?"
- No overengineering. No speculative abstractions. No temporary fixes.
- Find root causes. Senior developer standards.

### Testing
- Create positive and negative test cases for all generated code.
