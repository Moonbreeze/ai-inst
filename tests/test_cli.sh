#!/usr/bin/env bash
set -euo pipefail

AI_INST="$(cd "$(dirname "$0")/.." && pwd)/ai-inst"

# ─── Test runner ──────────────────────────────────────────────────────────────

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_NAMES=()

TMPDIR_BASE=""
PROJECT_DIR=""

setup() {
  TMPDIR_BASE="$(mktemp -d)"
  export AI_INST_DIR="$TMPDIR_BASE/repo"
  PROJECT_DIR="$TMPDIR_BASE/project"
  mkdir -p "$PROJECT_DIR"
  export HOME="$TMPDIR_BASE/home"
  mkdir -p "$HOME"
  cd "$PROJECT_DIR"
  # git needs user info for commits
  export GIT_AUTHOR_NAME="test"
  export GIT_AUTHOR_EMAIL="test@test.com"
  export GIT_COMMITTER_NAME="test"
  export GIT_COMMITTER_EMAIL="test@test.com"
  # don't open editor
  unset EDITOR
}

teardown() {
  cd /
  [[ -n "$TMPDIR_BASE" ]] && rm -rf "$TMPDIR_BASE"
}

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [[ "$expected" != "$actual" ]]; then
    echo "    FAIL: ${msg:-assert_eq}"
    echo "      expected: '$expected'"
    echo "      actual:   '$actual'"
    return 1
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "    FAIL: ${msg:-assert_contains}"
    echo "      expected to contain: '$needle'"
    echo "      in: '$haystack'"
    return 1
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "    FAIL: ${msg:-assert_not_contains}"
    echo "      expected NOT to contain: '$needle'"
    echo "      in: '$haystack'"
    return 1
  fi
}

assert_file_exists() {
  local path="$1" msg="${2:-}"
  if [[ ! -f "$path" ]]; then
    echo "    FAIL: ${msg:-assert_file_exists}: $path"
    return 1
  fi
}

assert_file_not_exists() {
  local path="$1" msg="${2:-}"
  if [[ -f "$path" ]]; then
    echo "    FAIL: ${msg:-assert_file_not_exists}: $path exists"
    return 1
  fi
}

assert_dir_exists() {
  local path="$1" msg="${2:-}"
  if [[ ! -d "$path" ]]; then
    echo "    FAIL: ${msg:-assert_dir_exists}: $path"
    return 1
  fi
}

assert_exit_code() {
  local expected="$1"
  shift
  local actual=0
  "$@" >/dev/null 2>&1 || actual=$?
  if [[ "$actual" -ne "$expected" ]]; then
    echo "    FAIL: expected exit code $expected, got $actual"
    echo "      command: $*"
    return 1
  fi
}

run_test() {
  local name="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "  [$TESTS_RUN] $name"
  setup
  if "$name" 2>&1 | sed 's/^/    | /'; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "    -> PASS"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_NAMES+=("$name")
    echo "    -> FAIL"
  fi
  teardown
}

# ─── Helpers ──────────────────────────────────────────────────────────────────

init_repo() {
  "$AI_INST" repo init 2>&1
}

init_project() {
  "$AI_INST" project init 2>&1
}

create_module() {
  local name="$1"
  local content="${2:-# $name module content}"
  mkdir -p "$AI_INST_DIR/modules"
  echo "$content" > "$AI_INST_DIR/modules/$name.md"
  cd "$AI_INST_DIR" && git add -A && git commit -m "add $name" >/dev/null 2>&1 && cd - >/dev/null
}

# ─── repo tests ───────────────────────────────────────────────────────────────

test_repo_init() {
  init_repo
  assert_dir_exists "$AI_INST_DIR/.git" "git init"
  assert_dir_exists "$AI_INST_DIR/modules" "modules dir"
  assert_file_exists "$AI_INST_DIR/README.md" "README"
  assert_file_exists "$AI_INST_DIR/bootstrap.sh" "bootstrap"
}

test_repo_init_with_remote() {
  "$AI_INST" repo init --remote "https://example.com/repo.git" 2>&1
  local remote
  remote="$(cd "$AI_INST_DIR" && git remote get-url origin)"
  assert_eq "https://example.com/repo.git" "$remote" "remote url"
}

test_repo_init_duplicate() {
  init_repo
  assert_exit_code 1 "$AI_INST" repo init
}

test_repo_path() {
  init_repo
  local path
  path="$("$AI_INST" repo path)"
  assert_eq "$AI_INST_DIR" "$path" "repo path"
}

# ─── module tests ─────────────────────────────────────────────────────────────

test_new_module() {
  init_repo
  "$AI_INST" new testmod 2>&1
  assert_file_exists "$AI_INST_DIR/modules/testmod.md" "module file"
  # verify committed
  local status
  status="$(cd "$AI_INST_DIR" && git status --porcelain)"
  assert_eq "" "$status" "clean after new"
}

test_new_duplicate() {
  init_repo
  "$AI_INST" new testmod 2>&1
  assert_exit_code 1 "$AI_INST" new testmod
}

test_show_module() {
  init_repo
  create_module "mymod" "# My module content"
  local output
  output="$("$AI_INST" show mymod)"
  assert_contains "$output" "My module content" "show content"
}

test_show_missing() {
  init_repo
  assert_exit_code 1 "$AI_INST" show nonexistent
}

test_rm_module() {
  init_repo
  "$AI_INST" new testmod 2>&1
  "$AI_INST" rm testmod 2>&1
  assert_file_not_exists "$AI_INST_DIR/modules/testmod.md" "file removed"
}

test_list_modules() {
  init_repo
  create_module "alpha"
  create_module "beta"
  local output
  output="$("$AI_INST" list)"
  assert_contains "$output" "alpha" "list alpha"
  assert_contains "$output" "beta" "list beta"
}

test_list_with_project_markers() {
  init_repo
  create_module "active"
  create_module "inactive"
  init_project
  "$AI_INST" project add active 2>&1
  local output
  output="$("$AI_INST" list)"
  assert_contains "$output" "* active" "active marker"
  assert_contains "$output" "  inactive" "inactive no marker"
}

# ─── project tests ────────────────────────────────────────────────────────────

test_project_init() {
  init_repo
  init_project
  assert_file_exists "$PROJECT_DIR/.ai-modules" ".ai-modules"
  assert_file_exists "$PROJECT_DIR/instructions.local.md" "local instructions"
  assert_file_exists "$PROJECT_DIR/.gitignore" ".gitignore"
}

test_project_init_idempotent() {
  init_repo
  init_project
  # write something to local instructions
  echo "custom content" > "$PROJECT_DIR/instructions.local.md"
  init_project
  local content
  content="$(cat "$PROJECT_DIR/instructions.local.md")"
  assert_eq "custom content" "$content" "not overwritten"
}

test_project_add() {
  init_repo
  create_module "mymod"
  init_project
  "$AI_INST" project add mymod 2>&1
  local content
  content="$(cat "$PROJECT_DIR/.ai-modules")"
  assert_contains "$content" "mymod" "module added"
}

test_project_add_duplicate() {
  init_repo
  create_module "mymod"
  init_project
  "$AI_INST" project add mymod 2>&1
  local output
  output="$("$AI_INST" project add mymod 2>&1)"
  assert_contains "$output" "already in project" "duplicate message"
}

test_project_rm() {
  init_repo
  create_module "mymod"
  init_project
  "$AI_INST" project add mymod 2>&1
  "$AI_INST" project rm mymod 2>&1
  local content
  content="$(cat "$PROJECT_DIR/.ai-modules")"
  assert_not_contains "$content" "mymod" "module removed"
}

test_project_targets() {
  init_repo
  init_project
  "$AI_INST" project targets CLAUDE.md .cursorrules 2>&1
  local content
  content="$(cat "$PROJECT_DIR/.ai-modules")"
  assert_contains "$content" "targets: CLAUDE.md .cursorrules" "targets line"
}

test_project_status() {
  init_repo
  create_module "mymod"
  init_project
  "$AI_INST" project add mymod 2>&1
  local output
  output="$("$AI_INST" project status 2>&1)"
  assert_contains "$output" "mymod" "status modules"
  assert_contains "$output" "CLAUDE.md" "status targets"
}

# ─── build tests ──────────────────────────────────────────────────────────────

test_build_single_target() {
  init_repo
  create_module "mod1" "# Module One Content"
  init_project
  "$AI_INST" project add mod1 2>&1
  "$AI_INST" build 2>&1
  assert_file_exists "$PROJECT_DIR/CLAUDE.md" "CLAUDE.md built"
  local content
  content="$(cat "$PROJECT_DIR/CLAUDE.md")"
  assert_contains "$content" "Module One Content" "module content"
}

test_build_multi_target() {
  init_repo
  create_module "mod1" "# Module One"
  init_project
  "$AI_INST" project add mod1 2>&1
  "$AI_INST" project targets CLAUDE.md .cursorrules 2>&1
  "$AI_INST" build 2>&1
  assert_file_exists "$PROJECT_DIR/CLAUDE.md" "CLAUDE.md"
  assert_file_exists "$PROJECT_DIR/.cursorrules" ".cursorrules"
}

test_build_filter_target() {
  init_repo
  create_module "mod1" "# Module One"
  init_project
  "$AI_INST" project add mod1 2>&1
  "$AI_INST" project targets CLAUDE.md .cursorrules 2>&1
  "$AI_INST" build --target CLAUDE.md 2>&1
  assert_file_exists "$PROJECT_DIR/CLAUDE.md" "CLAUDE.md built"
  assert_file_not_exists "$PROJECT_DIR/.cursorrules" ".cursorrules not built"
}

test_build_includes_local_instructions() {
  init_repo
  create_module "mod1" "# Module One"
  init_project
  "$AI_INST" project add mod1 2>&1
  echo "## Local project rules" > "$PROJECT_DIR/instructions.local.md"
  "$AI_INST" build 2>&1
  local content
  content="$(cat "$PROJECT_DIR/CLAUDE.md")"
  assert_contains "$content" "Local project rules" "local instructions included"
}

test_build_auto_generated_header() {
  init_repo
  create_module "mod1" "# Test"
  init_project
  "$AI_INST" project add mod1 2>&1
  "$AI_INST" build 2>&1
  local content
  content="$(cat "$PROJECT_DIR/CLAUDE.md")"
  assert_contains "$content" "<!-- AUTO-GENERATED by ai-inst" "auto-generated header"
}

test_build_module_order() {
  init_repo
  create_module "first" "FIRST_CONTENT"
  create_module "second" "SECOND_CONTENT"
  init_project
  "$AI_INST" project add first 2>&1
  "$AI_INST" project add second 2>&1
  "$AI_INST" build 2>&1
  local content
  content="$(cat "$PROJECT_DIR/CLAUDE.md")"
  # first should appear before second
  local pos_first pos_second
  pos_first=$(echo "$content" | grep -n "FIRST_CONTENT" | head -1 | cut -d: -f1)
  pos_second=$(echo "$content" | grep -n "SECOND_CONTENT" | head -1 | cut -d: -f1)
  if [[ "$pos_first" -ge "$pos_second" ]]; then
    echo "    FAIL: first ($pos_first) should come before second ($pos_second)"
    return 1
  fi
}

test_build_missing_module_warning() {
  init_repo
  init_project
  echo "nonexistent" >> "$PROJECT_DIR/.ai-modules"
  local output
  output="$("$AI_INST" build 2>&1)"
  assert_contains "$output" "warning" "missing module warning"
}

# ─── hook tests ───────────────────────────────────────────────────────────────

test_hook_install() {
  init_repo
  init_project
  git init "$PROJECT_DIR" >/dev/null 2>&1
  cd "$PROJECT_DIR"
  "$AI_INST" hook install 2>&1
  assert_file_exists "$PROJECT_DIR/.git/hooks/post-checkout" "post-checkout"
  assert_file_exists "$PROJECT_DIR/.git/hooks/post-merge" "post-merge"
  # verify executable
  [[ -x "$PROJECT_DIR/.git/hooks/post-checkout" ]] || { echo "    FAIL: post-checkout not executable"; return 1; }
}

test_hook_remove() {
  init_repo
  init_project
  git init "$PROJECT_DIR" >/dev/null 2>&1
  cd "$PROJECT_DIR"
  "$AI_INST" hook install 2>&1
  "$AI_INST" hook remove 2>&1
  assert_file_not_exists "$PROJECT_DIR/.git/hooks/post-checkout" "post-checkout removed"
  assert_file_not_exists "$PROJECT_DIR/.git/hooks/post-merge" "post-merge removed"
}

test_hook_install_idempotent() {
  init_repo
  init_project
  git init "$PROJECT_DIR" >/dev/null 2>&1
  cd "$PROJECT_DIR"
  "$AI_INST" hook install 2>&1
  local output
  output="$("$AI_INST" hook install 2>&1)"
  assert_contains "$output" "already installed" "idempotent message"
}

# ─── mcp tests ────────────────────────────────────────────────────────────────

test_mcp_install() {
  cd "$PROJECT_DIR"
  "$AI_INST" mcp install 2>&1
  assert_file_exists "$PROJECT_DIR/.mcp.json" ".mcp.json created"
  local content
  content="$(cat "$PROJECT_DIR/.mcp.json")"
  assert_contains "$content" '"ai-inst"' "has ai-inst key"
  assert_contains "$content" '"npx"' "has npx command"
  assert_contains "$content" '"tsx"' "has tsx arg"
  assert_contains "$content" 'mcp-server/src/index.ts' "has mcp-server path"
  assert_contains "$content" '"mcpServers"' "has mcpServers wrapper"
}

test_mcp_install_idempotent() {
  cd "$PROJECT_DIR"
  "$AI_INST" mcp install 2>&1
  local output
  output="$("$AI_INST" mcp install 2>&1)"
  assert_contains "$output" "already configured" "idempotent message"
  # verify file is still valid JSON
  node -e "JSON.parse(require('fs').readFileSync('$PROJECT_DIR/.mcp.json','utf-8'))" 2>&1
}

test_mcp_install_into_existing_mcp_json() {
  cd "$PROJECT_DIR"
  echo '{"mcpServers": {"other": {"command": "test"}}}' > "$PROJECT_DIR/.mcp.json"
  "$AI_INST" mcp install 2>&1
  local content
  content="$(cat "$PROJECT_DIR/.mcp.json")"
  assert_contains "$content" '"other"' "preserves other server"
  assert_contains "$content" '"ai-inst"' "has ai-inst"
}

test_mcp_remove() {
  cd "$PROJECT_DIR"
  "$AI_INST" mcp install 2>&1
  "$AI_INST" mcp remove 2>&1
  local content
  content="$(cat "$PROJECT_DIR/.mcp.json")"
  assert_not_contains "$content" '"ai-inst"' "ai-inst removed"
  # file should still be valid JSON
  node -e "JSON.parse(require('fs').readFileSync('$PROJECT_DIR/.mcp.json','utf-8'))" 2>&1
}

test_mcp_remove_not_installed() {
  cd "$PROJECT_DIR"
  echo '{"mcpServers": {}}' > "$PROJECT_DIR/.mcp.json"
  local output
  output="$("$AI_INST" mcp remove 2>&1)"
  assert_contains "$output" "not found" "not found message"
}

test_mcp_remove_no_file() {
  cd "$PROJECT_DIR"
  local output
  output="$("$AI_INST" mcp remove 2>&1 || true)"
  assert_contains "$output" "not found" "error when no .mcp.json"
}

test_mcp_status_not_installed() {
  cd "$PROJECT_DIR"
  local output
  output="$("$AI_INST" mcp status 2>&1)"
  assert_contains "$output" "Claude Code" "shows Claude Code in header"
  assert_contains "$output" "not installed" "shows not installed"
}

test_mcp_status_installed() {
  cd "$PROJECT_DIR"
  "$AI_INST" mcp install 2>&1
  local output
  output="$("$AI_INST" mcp status 2>&1)"
  assert_contains "$output" "Claude Code" "shows Claude Code in header"
  assert_contains "$output" "installed" "shows installed"
}

test_mcp_install_with_claude_flag() {
  cd "$PROJECT_DIR"
  "$AI_INST" mcp install --claude 2>&1
  assert_file_exists "$PROJECT_DIR/.mcp.json" ".mcp.json created with --claude"
  local content
  content="$(cat "$PROJECT_DIR/.mcp.json")"
  assert_contains "$content" '"ai-inst"' "has ai-inst key"
}

test_mcp_install_codex_local() {
  cd "$PROJECT_DIR"
  "$AI_INST" mcp install --codex 2>&1
  local cfg="$PROJECT_DIR/.codex/config.toml"
  assert_file_exists "$cfg" "codex project config created"
  local content
  content="$(cat "$cfg")"
  assert_contains "$content" "[mcp_servers.ai-inst]" "codex entry header"
  assert_contains "$content" "command = \"npx\"" "codex command"
  assert_contains "$content" "tsx" "codex args"
}

test_mcp_install_codex_global() {
  cd "$PROJECT_DIR"
  "$AI_INST" mcp install --codex --global 2>&1
  local cfg="$HOME/.codex/config.toml"
  assert_file_exists "$cfg" "codex global config created"
  local content
  content="$(cat "$cfg")"
  assert_contains "$content" "[mcp_servers.ai-inst]" "global codex entry header"
}

test_mcp_remove_codex_local() {
  cd "$PROJECT_DIR"
  "$AI_INST" mcp install --codex 2>&1
  "$AI_INST" mcp remove --codex 2>&1
  local cfg="$PROJECT_DIR/.codex/config.toml"
  local content
  content="$(cat "$cfg")"
  assert_not_contains "$content" "[mcp_servers.ai-inst]" "codex local entry removed"
}

test_mcp_remove_codex_global() {
  cd "$PROJECT_DIR"
  "$AI_INST" mcp install --codex --global 2>&1
  "$AI_INST" mcp remove --codex --global 2>&1
  local cfg="$HOME/.codex/config.toml"
  local content
  content="$(cat "$cfg")"
  assert_not_contains "$content" "[mcp_servers.ai-inst]" "codex global entry removed"
}

test_mcp_status_codex() {
  cd "$PROJECT_DIR"
  local output
  output="$("$AI_INST" mcp status --codex 2>&1)"
  assert_contains "$output" "MCP server status (Codex)" "codex header"
  assert_contains "$output" "Global:  not installed" "global not installed default"
  assert_contains "$output" "Project: not installed" "project not installed default"

  "$AI_INST" mcp install --codex 2>&1
  output="$("$AI_INST" mcp status --codex 2>&1)"
  assert_contains "$output" "Project: installed" "project installed after add"
}

# ─── skill helpers ────────────────────────────────────────────────────────────

create_skill() {
  local name="$1"
  local description="${2:-Test skill}"
  local content="${3:-Skill instructions for $name}"
  mkdir -p "$AI_INST_DIR/skills/$name"
  cat > "$AI_INST_DIR/skills/$name/SKILL.md" << EOF
---
name: $name
description: $description
---

$content
EOF
  cd "$AI_INST_DIR" && git add -A && git commit -m "add skill $name" >/dev/null 2>&1 && cd - >/dev/null
}

# ─── skill tests ──────────────────────────────────────────────────────────────

test_skill_new() {
  init_repo
  "$AI_INST" skill new myskill 2>&1
  assert_dir_exists "$AI_INST_DIR/skills/myskill" "skill dir created"
  assert_file_exists "$AI_INST_DIR/skills/myskill/SKILL.md" "SKILL.md created"
  local content
  content="$(cat "$AI_INST_DIR/skills/myskill/SKILL.md")"
  assert_contains "$content" "name: myskill" "name in frontmatter"
  # verify committed
  local status
  status="$(cd "$AI_INST_DIR" && git status --porcelain)"
  assert_eq "" "$status" "clean after skill new"
}

test_skill_new_duplicate() {
  init_repo
  "$AI_INST" skill new myskill 2>&1
  assert_exit_code 1 "$AI_INST" skill new myskill
}

test_skill_show() {
  init_repo
  create_skill "myskill" "Test skill" "Do something useful"
  local output
  output="$("$AI_INST" skill show myskill)"
  assert_contains "$output" "Do something useful" "skill content shown"
}

test_skill_show_missing() {
  init_repo
  assert_exit_code 1 "$AI_INST" skill show nonexistent
}

test_skill_rm() {
  init_repo
  create_skill "myskill"
  "$AI_INST" skill rm myskill 2>&1
  if [[ -d "$AI_INST_DIR/skills/myskill" ]]; then
    echo "    FAIL: skill directory still exists"
    return 1
  fi
}

test_skill_list() {
  init_repo
  create_skill "alpha" "First skill"
  create_skill "beta" "Second skill"
  local output
  output="$("$AI_INST" skill list)"
  assert_contains "$output" "alpha" "alpha in list"
  assert_contains "$output" "beta" "beta in list"
}

test_skill_list_with_project_markers() {
  init_repo
  create_skill "active-skill"
  create_skill "inactive-skill"
  init_project
  "$AI_INST" project add-skill active-skill 2>&1
  local output
  output="$("$AI_INST" skill list)"
  assert_contains "$output" "* active-skill" "active marker"
  assert_contains "$output" "  inactive-skill" "inactive no marker"
}

# ─── project skill tests ──────────────────────────────────────────────────────

test_project_add_skill() {
  init_repo
  create_skill "deploy" "Deploy skill"
  init_project
  "$AI_INST" project add-skill deploy 2>&1
  local content
  content="$(cat "$PROJECT_DIR/.ai-modules")"
  assert_contains "$content" "[skills]" "skills section created"
  assert_contains "$content" "deploy" "skill added"
}

test_project_add_skill_creates_section() {
  init_repo
  create_skill "refactor" "Refactor skill"
  init_project
  # Ensure no [skills] section yet
  local content
  content="$(cat "$PROJECT_DIR/.ai-modules")"
  assert_not_contains "$content" "[skills]" "no skills section initially"
  "$AI_INST" project add-skill refactor 2>&1
  content="$(cat "$PROJECT_DIR/.ai-modules")"
  assert_contains "$content" "[skills]" "skills section created"
  assert_contains "$content" "refactor" "skill added"
}

test_project_add_skill_duplicate() {
  init_repo
  create_skill "deploy"
  init_project
  "$AI_INST" project add-skill deploy 2>&1
  local output
  output="$("$AI_INST" project add-skill deploy 2>&1)"
  assert_contains "$output" "already in project" "duplicate message"
}

test_project_rm_skill() {
  init_repo
  create_skill "deploy"
  init_project
  "$AI_INST" project add-skill deploy 2>&1
  "$AI_INST" project rm-skill deploy 2>&1
  local content
  content="$(cat "$PROJECT_DIR/.ai-modules")"
  assert_not_contains "$content" "deploy" "skill removed"
}

# ─── build with skills tests ──────────────────────────────────────────────────

test_build_copies_skills_to_claude_dir() {
  init_repo
  create_skill "deploy" "Deploy the app"
  init_project
  "$AI_INST" project add-skill deploy 2>&1
  "$AI_INST" build 2>&1
  assert_dir_exists "$PROJECT_DIR/.claude/skills/deploy" "skill in .claude/skills"
  assert_file_exists "$PROJECT_DIR/.claude/skills/deploy/SKILL.md" "SKILL.md in .claude/skills"
}

test_build_copies_skills_to_agents_dir() {
  init_repo
  create_skill "deploy" "Deploy the app"
  init_project
  "$AI_INST" project add-skill deploy 2>&1
  "$AI_INST" build 2>&1
  assert_dir_exists "$PROJECT_DIR/.agents/skills/deploy" "skill in .agents/skills"
  assert_file_exists "$PROJECT_DIR/.agents/skills/deploy/SKILL.md" "SKILL.md in .agents/skills"
}

test_build_skill_directory_structure() {
  init_repo
  create_skill "deploy" "Deploy the app"
  # Add a subdirectory with resources
  mkdir -p "$AI_INST_DIR/skills/deploy/scripts"
  echo "#!/bin/bash" > "$AI_INST_DIR/skills/deploy/scripts/deploy.sh"
  cd "$AI_INST_DIR" && git add -A && git commit -m "add deploy script" >/dev/null 2>&1 && cd - >/dev/null
  init_project
  "$AI_INST" project add-skill deploy 2>&1
  "$AI_INST" build 2>&1
  assert_file_exists "$PROJECT_DIR/.claude/skills/deploy/scripts/deploy.sh" "script copied"
  assert_file_exists "$PROJECT_DIR/.agents/skills/deploy/scripts/deploy.sh" "script in agents dir"
}

test_build_skills_index_in_target() {
  init_repo
  create_skill "deploy" "Deploy the application to production"
  create_skill "refactor" "Refactor code following best practices"
  init_project
  "$AI_INST" project add-skill deploy 2>&1
  "$AI_INST" project add-skill refactor 2>&1
  "$AI_INST" build 2>&1
  local content
  content="$(cat "$PROJECT_DIR/CLAUDE.md")"
  assert_contains "$content" "## Available skills" "skills index header"
  assert_contains "$content" "deploy" "deploy in index"
  assert_contains "$content" "Deploy the application to production" "deploy description"
  assert_contains "$content" "refactor" "refactor in index"
}

test_build_cleans_old_skills() {
  init_repo
  create_skill "old-skill" "Old skill"
  create_skill "new-skill" "New skill"
  init_project
  "$AI_INST" project add-skill old-skill 2>&1
  "$AI_INST" build 2>&1
  assert_dir_exists "$PROJECT_DIR/.claude/skills/old-skill" "old skill built"
  # Replace skill in project
  "$AI_INST" project rm-skill old-skill 2>&1
  "$AI_INST" project add-skill new-skill 2>&1
  "$AI_INST" build 2>&1
  assert_dir_exists "$PROJECT_DIR/.claude/skills/new-skill" "new skill present"
  if [[ -d "$PROJECT_DIR/.claude/skills/old-skill" ]]; then
    echo "    FAIL: old skill should have been cleaned up"
    return 1
  fi
}

test_build_updates_gitignore_for_skills() {
  init_repo
  create_skill "deploy" "Deploy skill"
  init_project
  "$AI_INST" project add-skill deploy 2>&1
  "$AI_INST" build 2>&1
  local content
  content="$(cat "$PROJECT_DIR/.gitignore")"
  assert_contains "$content" ".claude/skills/" ".claude/skills/ in gitignore"
  assert_contains "$content" ".agents/skills/" ".agents/skills/ in gitignore"
}

test_build_missing_skill_warning() {
  init_repo
  init_project
  # Manually add nonexistent skill to .ai-modules
  printf '\n[skills]\nnonexistent-skill\n' >> "$PROJECT_DIR/.ai-modules"
  local output
  output="$("$AI_INST" build 2>&1)"
  assert_contains "$output" "warning" "missing skill warning"
}

# ─── migration helpers ────────────────────────────────────────────────────────

create_migration() {
  local id="$1"
  local filename="$2"
  local content="$3"
  mkdir -p "$AI_INST_DIR/migrations"
  echo "$content" > "$AI_INST_DIR/migrations/$filename"
  cd "$AI_INST_DIR" && git add -A && git commit -m "add migration $id" >/dev/null 2>&1 && cd - >/dev/null
}

# ─── migration tests ─────────────────────────────────────────────────────────

test_migrate_add_skill_when_has_module() {
  init_repo
  create_module "typescript" "# TypeScript rules"
  create_skill "jsdoc" "JSDoc generation"
  init_project
  "$AI_INST" project add typescript 2>&1
  create_migration "2026-01-01-jsdoc" "2026-01-01-jsdoc.yml" 'id: "2026-01-01-jsdoc"
description: "Extract JSDoc into skill"
rules:
  - when:
      has_module: typescript
    then:
      add_skill: jsdoc'

  "$AI_INST" migrate 2>&1
  local content
  content="$(cat "$PROJECT_DIR/.ai-modules")"
  assert_contains "$content" "jsdoc" "jsdoc skill added"
  assert_contains "$content" "[skills]" "skills section created"
}

test_migrate_remove_and_add_module() {
  init_repo
  create_module "old-name" "# Old module"
  create_module "new-name" "# New module"
  init_project
  "$AI_INST" project add old-name 2>&1
  create_migration "2026-01-02-rename" "2026-01-02-rename.yml" 'id: "2026-01-02-rename"
description: "Rename old-name to new-name"
rules:
  - when:
      has_module: old-name
    then:
      remove_module: old-name
      add_module: new-name'

  "$AI_INST" migrate 2>&1
  local content
  content="$(cat "$PROJECT_DIR/.ai-modules")"
  assert_not_contains "$content" "old-name" "old module removed"
  assert_contains "$content" "new-name" "new module added"
}

test_migrate_condition_not_met() {
  init_repo
  create_module "python" "# Python rules"
  create_skill "jsdoc" "JSDoc generation"
  init_project
  "$AI_INST" project add python 2>&1
  create_migration "2026-01-03-jsdoc" "2026-01-03-jsdoc.yml" 'id: "2026-01-03-jsdoc"
description: "Extract JSDoc into skill"
rules:
  - when:
      has_module: typescript
    then:
      add_skill: jsdoc'

  "$AI_INST" migrate 2>&1
  local content
  content="$(cat "$PROJECT_DIR/.ai-modules")"
  assert_not_contains "$content" "jsdoc" "jsdoc not added (no typescript)"
}

test_migrate_idempotent() {
  init_repo
  create_module "typescript" "# TypeScript rules"
  create_skill "jsdoc" "JSDoc generation"
  init_project
  "$AI_INST" project add typescript 2>&1
  create_migration "2026-01-04-idem" "2026-01-04-idem.yml" 'id: "2026-01-04-idem"
description: "Test idempotency"
rules:
  - when:
      has_module: typescript
    then:
      add_skill: jsdoc'

  "$AI_INST" migrate 2>&1
  "$AI_INST" migrate 2>&1
  # Should not duplicate
  local count
  count="$(grep -c "jsdoc" "$PROJECT_DIR/.ai-modules" || true)"
  assert_eq "1" "$count" "jsdoc appears once"
}

test_migrate_state_file() {
  init_repo
  create_module "typescript" "# TypeScript rules"
  create_skill "jsdoc" "JSDoc generation"
  init_project
  "$AI_INST" project add typescript 2>&1
  create_migration "2026-01-05-state" "2026-01-05-state.yml" 'id: "2026-01-05-state"
description: "Test state tracking"
rules:
  - when:
      has_module: typescript
    then:
      add_skill: jsdoc'

  "$AI_INST" migrate 2>&1
  assert_file_exists "$PROJECT_DIR/.ai-migrations-state" "state file created"
  local content
  content="$(cat "$PROJECT_DIR/.ai-migrations-state")"
  assert_contains "$content" "2026-01-05-state" "migration id tracked"
}

test_migrate_status() {
  init_repo
  create_module "typescript" "# TypeScript rules"
  create_skill "jsdoc" "JSDoc generation"
  init_project
  "$AI_INST" project add typescript 2>&1
  create_migration "2026-01-06-status" "2026-01-06-status.yml" 'id: "2026-01-06-status"
description: "Test status display"
rules:
  - when:
      has_module: typescript
    then:
      add_skill: jsdoc'

  local output
  output="$("$AI_INST" migrate --status 2>&1)"
  assert_contains "$output" "2026-01-06-status" "migration id shown"
  assert_contains "$output" "1 pending" "pending count"

  "$AI_INST" migrate 2>&1
  output="$("$AI_INST" migrate --status 2>&1)"
  assert_contains "$output" "0 pending" "no pending after apply"
}

test_migrate_order() {
  init_repo
  create_module "base" "# Base module"
  create_module "extra" "# Extra module"
  create_skill "s1" "Skill one"
  create_skill "s2" "Skill two"
  init_project
  "$AI_INST" project add base 2>&1

  create_migration "2026-01-01-first" "2026-01-01-first.yml" 'id: "2026-01-01-first"
description: "First migration"
rules:
  - when:
      has_module: base
    then:
      add_module: extra'

  create_migration "2026-01-02-second" "2026-01-02-second.yml" 'id: "2026-01-02-second"
description: "Second migration depends on first"
rules:
  - when:
      has_module: extra
    then:
      add_skill: s1'

  "$AI_INST" migrate 2>&1
  local content
  content="$(cat "$PROJECT_DIR/.ai-modules")"
  assert_contains "$content" "extra" "first migration applied"
  assert_contains "$content" "s1" "second migration applied (chained)"
}

test_migrate_no_migrations_dir() {
  init_repo
  init_project
  # Should not error
  "$AI_INST" migrate 2>&1
}

test_build_runs_migrations() {
  init_repo
  create_module "typescript" "# TypeScript rules"
  create_skill "jsdoc" "JSDoc generation"
  init_project
  "$AI_INST" project add typescript 2>&1
  create_migration "2026-01-07-build" "2026-01-07-build.yml" 'id: "2026-01-07-build"
description: "Auto-migrate on build"
rules:
  - when:
      has_module: typescript
    then:
      add_skill: jsdoc'

  "$AI_INST" build 2>&1
  local content
  content="$(cat "$PROJECT_DIR/.ai-modules")"
  assert_contains "$content" "jsdoc" "migration applied during build"
}

test_build_no_migrate_flag() {
  init_repo
  create_module "typescript" "# TypeScript rules"
  create_skill "jsdoc" "JSDoc generation"
  init_project
  "$AI_INST" project add typescript 2>&1
  create_migration "2026-01-08-skip" "2026-01-08-skip.yml" 'id: "2026-01-08-skip"
description: "Should be skipped"
rules:
  - when:
      has_module: typescript
    then:
      add_skill: jsdoc'

  "$AI_INST" build --no-migrate 2>&1
  local content
  content="$(cat "$PROJECT_DIR/.ai-modules")"
  assert_not_contains "$content" "jsdoc" "migration skipped with --no-migrate"
}

test_migrate_gitignore() {
  init_repo
  create_module "typescript" "# TypeScript rules"
  create_skill "jsdoc" "JSDoc generation"
  init_project
  "$AI_INST" project add typescript 2>&1
  create_migration "2026-01-09-gi" "2026-01-09-gi.yml" 'id: "2026-01-09-gi"
description: "Gitignore test"
rules:
  - when:
      has_module: typescript
    then:
      add_skill: jsdoc'

  "$AI_INST" migrate 2>&1
  local content
  content="$(cat "$PROJECT_DIR/.gitignore")"
  assert_contains "$content" ".ai-migrations-state" "state file in gitignore"
}

test_migrate_not_has_skill_condition() {
  init_repo
  create_module "typescript" "# TypeScript rules"
  create_skill "jsdoc" "JSDoc generation"
  init_project
  "$AI_INST" project add typescript 2>&1
  "$AI_INST" project add-skill jsdoc 2>&1
  create_migration "2026-01-10-nothas" "2026-01-10-nothas.yml" 'id: "2026-01-10-nothas"
description: "Only add if not already present"
rules:
  - when:
      not_has_skill: jsdoc
    then:
      add_skill: jsdoc'

  "$AI_INST" migrate 2>&1
  # jsdoc was already there, condition not met — should still be there once
  local count
  count="$(grep -c "jsdoc" "$PROJECT_DIR/.ai-modules" || true)"
  assert_eq "1" "$count" "jsdoc not duplicated"
}

# ─── recommend tests ─────────────────────────────────────────────────────────

test_recommend_list_empty() {
  init_repo
  local out
  out="$("$AI_INST" recommend list 2>&1)"
  assert_contains "$out" "No recommended modules configured"
}

test_recommend_add() {
  init_repo
  create_module "workflow"
  create_module "testing"
  "$AI_INST" recommend add workflow testing >/dev/null 2>&1
  local out
  out="$("$AI_INST" recommend list 2>&1)"
  assert_contains "$out" "workflow"
  assert_contains "$out" "testing"
}

test_recommend_add_duplicate() {
  init_repo
  create_module "workflow"
  "$AI_INST" recommend add workflow >/dev/null 2>&1
  local out
  out="$("$AI_INST" recommend add workflow 2>&1)"
  assert_contains "$out" "already recommended"
  # should not duplicate
  local count
  count="$(grep -c "workflow" "$AI_INST_DIR/recommended" || true)"
  assert_eq "1" "$count" "workflow not duplicated"
}

test_recommend_add_nonexistent_module() {
  init_repo
  assert_exit_code 1 "$AI_INST" recommend add nonexistent
}

test_recommend_rm() {
  init_repo
  create_module "workflow"
  create_module "testing"
  "$AI_INST" recommend add workflow testing >/dev/null 2>&1
  "$AI_INST" recommend rm workflow >/dev/null 2>&1
  local out
  out="$("$AI_INST" recommend list 2>&1)"
  assert_not_contains "$out" "workflow"
  assert_contains "$out" "testing"
}

test_recommend_rm_not_in_list() {
  init_repo
  create_module "workflow"
  "$AI_INST" recommend add workflow >/dev/null 2>&1
  local out
  out="$("$AI_INST" recommend rm testing 2>&1)"
  assert_contains "$out" "not in recommended"
}

test_recommend_commits_to_repo() {
  init_repo
  create_module "workflow"
  "$AI_INST" recommend add workflow >/dev/null 2>&1
  local log
  log="$(cd "$AI_INST_DIR" && git log --oneline -1)"
  assert_contains "$log" "recommend"
}

# ─── project doctor tests ────────────────────────────────────────────────────

test_doctor_no_recommended_file() {
  init_repo
  init_project
  local out
  out="$("$AI_INST" project doctor 2>&1)"
  assert_contains "$out" "No recommended modules configured"
}

test_doctor_all_present() {
  init_repo
  create_module "workflow"
  init_project
  "$AI_INST" project add workflow >/dev/null 2>&1
  "$AI_INST" recommend add workflow >/dev/null 2>&1
  local out
  out="$("$AI_INST" project doctor 2>&1)"
  assert_contains "$out" "All recommended modules are present"
}

test_doctor_missing_modules() {
  init_repo
  create_module "workflow"
  create_module "testing"
  init_project
  "$AI_INST" project add workflow >/dev/null 2>&1
  "$AI_INST" recommend add workflow testing >/dev/null 2>&1
  local out
  out="$("$AI_INST" project doctor 2>&1)" || true
  assert_contains "$out" "testing"
  assert_contains "$out" "Missing recommended modules"
}

test_doctor_exit_code() {
  init_repo
  create_module "workflow"
  create_module "testing"
  init_project
  "$AI_INST" project add workflow >/dev/null 2>&1
  "$AI_INST" recommend add workflow testing >/dev/null 2>&1
  # missing testing → exit 1
  assert_exit_code 1 "$AI_INST" project doctor
  # add testing → exit 0
  "$AI_INST" project add testing >/dev/null 2>&1
  assert_exit_code 0 "$AI_INST" project doctor
}

test_doctor_skips_comments_and_blanks() {
  init_repo
  create_module "workflow"
  init_project
  "$AI_INST" project add workflow >/dev/null 2>&1
  # Manually write recommended file with comments and blanks
  printf "# This is a comment\n\nworkflow\n\n" > "$AI_INST_DIR/recommended"
  cd "$AI_INST_DIR" && git add -A && git commit -m "test" >/dev/null 2>&1 && cd "$PROJECT_DIR"
  local out
  out="$("$AI_INST" project doctor 2>&1)"
  assert_contains "$out" "All recommended modules are present"
}

test_project_init_shows_doctor() {
  init_repo
  create_module "workflow"
  create_module "testing"
  "$AI_INST" recommend add workflow testing >/dev/null 2>&1
  local out
  out="$("$AI_INST" project init 2>&1)" || true
  assert_contains "$out" "Missing recommended modules"
  assert_contains "$out" "testing"
  assert_contains "$out" "workflow"
}

# ─── edge case tests ─────────────────────────────────────────────────────────

test_no_repo_error() {
  assert_exit_code 1 "$AI_INST" list
}

test_no_project_error() {
  init_repo
  assert_exit_code 1 "$AI_INST" project add somemod
}

test_version() {
  local output
  output="$("$AI_INST" version)"
  assert_eq "ai-inst 0.1.0" "$output" "version string"
}

test_help() {
  local output
  output="$("$AI_INST" help)"
  assert_contains "$output" "Usage:" "help contains Usage"
}

# ─── Run all tests ────────────────────────────────────────────────────────────

echo "Running ai-inst CLI tests..."
echo ""

echo "repo:"
run_test test_repo_init
run_test test_repo_init_with_remote
run_test test_repo_init_duplicate
run_test test_repo_path

echo ""
echo "modules:"
run_test test_new_module
run_test test_new_duplicate
run_test test_show_module
run_test test_show_missing
run_test test_rm_module
run_test test_list_modules
run_test test_list_with_project_markers

echo ""
echo "project:"
run_test test_project_init
run_test test_project_init_idempotent
run_test test_project_add
run_test test_project_add_duplicate
run_test test_project_rm
run_test test_project_targets
run_test test_project_status

echo ""
echo "build:"
run_test test_build_single_target
run_test test_build_multi_target
run_test test_build_filter_target
run_test test_build_includes_local_instructions
run_test test_build_auto_generated_header
run_test test_build_module_order
run_test test_build_missing_module_warning

echo ""
echo "hooks:"
run_test test_hook_install
run_test test_hook_remove
run_test test_hook_install_idempotent

echo ""
echo "mcp:"
run_test test_mcp_install
run_test test_mcp_install_idempotent
run_test test_mcp_install_into_existing_mcp_json
run_test test_mcp_remove
run_test test_mcp_remove_not_installed
run_test test_mcp_remove_no_file
run_test test_mcp_status_not_installed
run_test test_mcp_status_installed
run_test test_mcp_install_with_claude_flag
run_test test_mcp_install_codex_local
run_test test_mcp_install_codex_global
run_test test_mcp_remove_codex_local
run_test test_mcp_remove_codex_global
run_test test_mcp_status_codex

echo ""
echo "skills:"
run_test test_skill_new
run_test test_skill_new_duplicate
run_test test_skill_show
run_test test_skill_show_missing
run_test test_skill_rm
run_test test_skill_list
run_test test_skill_list_with_project_markers

echo ""
echo "project skills:"
run_test test_project_add_skill
run_test test_project_add_skill_creates_section
run_test test_project_add_skill_duplicate
run_test test_project_rm_skill

echo ""
echo "build with skills:"
run_test test_build_copies_skills_to_claude_dir
run_test test_build_copies_skills_to_agents_dir
run_test test_build_skill_directory_structure
run_test test_build_skills_index_in_target
run_test test_build_cleans_old_skills
run_test test_build_updates_gitignore_for_skills
run_test test_build_missing_skill_warning

echo ""
echo "migrations:"
run_test test_migrate_add_skill_when_has_module
run_test test_migrate_remove_and_add_module
run_test test_migrate_condition_not_met
run_test test_migrate_idempotent
run_test test_migrate_state_file
run_test test_migrate_status
run_test test_migrate_order
run_test test_migrate_no_migrations_dir
run_test test_build_runs_migrations
run_test test_build_no_migrate_flag
run_test test_migrate_gitignore
run_test test_migrate_not_has_skill_condition

echo ""
echo "recommend:"
run_test test_recommend_list_empty
run_test test_recommend_add
run_test test_recommend_add_duplicate
run_test test_recommend_add_nonexistent_module
run_test test_recommend_rm
run_test test_recommend_rm_not_in_list
run_test test_recommend_commits_to_repo

echo ""
echo "project doctor:"
run_test test_doctor_no_recommended_file
run_test test_doctor_all_present
run_test test_doctor_missing_modules
run_test test_doctor_exit_code
run_test test_doctor_skips_comments_and_blanks
run_test test_project_init_shows_doctor

echo ""
echo "edge cases:"
run_test test_no_repo_error
run_test test_no_project_error
run_test test_version
run_test test_help

# ─── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════"
echo "  Total:  $TESTS_RUN"
echo "  Passed: $TESTS_PASSED"
echo "  Failed: $TESTS_FAILED"
echo "════════════════════════════════════════"

if [[ ${#FAILED_NAMES[@]} -gt 0 ]]; then
  echo ""
  echo "Failed tests:"
  for name in "${FAILED_NAMES[@]}"; do
    echo "  - $name"
  done
fi

echo ""
exit "$TESTS_FAILED"
