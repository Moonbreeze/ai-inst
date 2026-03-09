# ai-inst

Modular AI agent instruction manager. Store, sync, and build instructions for AI coding agents (Claude Code, Codex, Cursor, GitHub Copilot) across projects and hosts.

## Quick Start

```bash
# Install
git clone https://github.com/moonbreeze/ai-inst.git ~/ai-inst
~/ai-inst/install.sh

# Initialize rules repo
ai-inst repo init --remote git@github.com:<user>/my-ai-rules.git

# Create modules
ai-inst new common
ai-inst new lang-python
ai-inst push -m "initial modules"

# Use in a project
cd ~/my-project
ai-inst project init
ai-inst project add common lang-python
ai-inst build
```

## Architecture

Two repositories:

1. **Tool repo** (`ai-inst`) — this repo, the CLI + MCP server
2. **Rules repo** (`~/.ai-instructions`) — your personal modules, synced via git

## Commands

### Repository
| Command | Description |
|---------|-------------|
| `ai-inst repo init [--remote <url>]` | Initialize rules repo |
| `ai-inst repo clone <url>` | Clone rules on a new host |
| `ai-inst repo sync` | Pull + push |
| `ai-inst repo path` | Print repo path |

### Modules
| Command | Description |
|---------|-------------|
| `ai-inst list` | List modules (`*` = active in project) |
| `ai-inst new <name>` | Create module |
| `ai-inst edit <name>` | Edit module |
| `ai-inst show <name>` | Show module content |
| `ai-inst rm <name>` | Delete module |
| `ai-inst push [-m "msg"]` | Commit & push |

### Project
| Command | Description |
|---------|-------------|
| `ai-inst project init` | Create `.ai-modules` + `instructions.local.md` |
| `ai-inst project add <mod...>` | Add modules |
| `ai-inst project rm <mod...>` | Remove modules |
| `ai-inst project edit` | Edit local instructions |
| `ai-inst project status` | Show status |
| `ai-inst project targets <file...>` | Set target files |

### Build
| Command | Description |
|---------|-------------|
| `ai-inst build` | Build all target files |
| `ai-inst build --target CLAUDE.md` | Build specific target |

### Hooks
| Command | Description |
|---------|-------------|
| `ai-inst hook install` | Install git hooks for auto-build |
| `ai-inst hook remove` | Remove hooks |

### MCP
| Command | Description |
|---------|-------------|
| `ai-inst mcp install [--claude\|--codex] [--global]` | Install MCP server for Claude Code or Codex |
| `ai-inst mcp remove [--claude\|--codex] [--global]` | Remove MCP server for Claude Code or Codex |
| `ai-inst mcp status [--claude\|--codex]` | Show MCP installation status |

## `.ai-modules` format

```ini
# Target files (default: CLAUDE.md)
targets: CLAUDE.md .cursorrules AGENTS.md

# Modules (in order)
common
lang-python
framework-fastapi
```

## MCP Server

The MCP server wraps the CLI for direct AI agent integration.

### Setup via CLI

Use built-in commands instead of manual edits:

```bash
# Claude Code (project-local: .mcp.json)
ai-inst mcp install --claude

# Claude Code (global)
ai-inst mcp install --claude --global

# Codex (project-local: .codex/config.toml)
ai-inst mcp install --codex

# Codex (global)
ai-inst mcp install --codex --global
```

Check and remove configuration:

```bash
ai-inst mcp status --claude
ai-inst mcp status --codex

ai-inst mcp remove --claude
ai-inst mcp remove --codex --global
```

Notes:
- `ai-inst mcp install` defaults to Claude (`--claude`).
- Claude global install uses `claude mcp add ...` and requires the `claude` CLI.
- Codex config is written to `.codex/config.toml` (project) or `~/.codex/config.toml` (global).

### Manual setup (optional)

If you need to configure manually:

Claude (`.mcp.json`):

```json
{
  "mcpServers": {
    "ai-inst": {
      "command": "npx",
      "args": ["tsx", "/path/to/ai-inst/mcp-server/src/index.ts"]
    }
  }
}
```

Codex (`.codex/config.toml` or `~/.codex/config.toml`):

```toml
[mcp_servers.ai-inst]
command = "npx"
args = ["tsx", "/path/to/ai-inst/mcp-server/src/index.ts"]
```

## New Host Setup

If you already have a rules repo on GitHub:

```bash
git clone git@github.com:<user>/my-ai-rules.git ~/.ai-instructions
~/.ai-instructions/bootstrap.sh
```

## Environment

| Variable | Default | Description |
|----------|---------|-------------|
| `AI_INST_DIR` | `~/.ai-instructions` | Rules repo path |
| `EDITOR` | — | Editor for `new`/`edit` commands |
