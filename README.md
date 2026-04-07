## Setup

1. Move `./agents` and `./skills` in your `~/.claude` directory.
2. Update `~/.claude/CLAUDE.md` with the contents from `./CLAUDE.md`.
3. Update `~/.claude/settings.json` with the permissions from `./settings.json`.


## Setup LSP

https://karanbansal.in/blog/claude-code-lsp/

1. Add this to your `~/.claude/settings.json`:

```json
  "env": {
    "ENABLE_LSP_TOOL": "1"
  }
```

2. Install the Language Server

```bash
brew install jdtls
```

3. Install the plugin

```bash
claude plugin marketplace update claude-plugins-official
claude plugin install jdtls-lsp
```
