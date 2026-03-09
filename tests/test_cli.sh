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
