#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
CLI_SCRIPT="$SCRIPT_DIR/ai-inst"
MCP_DIR="$SCRIPT_DIR/mcp-server"

echo ":: Installing ai-inst..."

# Ensure CLI script is executable
chmod +x "$CLI_SCRIPT"

# Create symlink
mkdir -p "$BIN_DIR"
ln -sf "$CLI_SCRIPT" "$BIN_DIR/ai-inst"
echo "   Symlink: $BIN_DIR/ai-inst -> $CLI_SCRIPT"

# Check PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo ""
  echo "   WARNING: $BIN_DIR is not in your PATH."
  echo "   Add this to your shell profile (~/.bashrc or ~/.zshrc):"
  echo "     export PATH=\"\$HOME/.local/bin:\$PATH\""
  echo ""
fi

# Install MCP server dependencies if Node.js available
if command -v node &>/dev/null && [[ -f "$MCP_DIR/package.json" ]]; then
  echo ":: Installing MCP server dependencies..."
  cd "$MCP_DIR"
  npm install --silent 2>/dev/null || echo "   npm install failed (non-critical)"
  cd - > /dev/null

  echo ""
  echo ":: MCP server available. To add to Claude Code, add to ~/.claude/settings.json:"
  echo "   {"
  echo "     \"mcpServers\": {"
  echo "       \"ai-inst\": {"
  echo "         \"command\": \"npx\","
  echo "         \"args\": [\"tsx\", \"$MCP_DIR/src/index.ts\"]"
  echo "       }"
  echo "     }"
  echo "   }"
fi

echo ""
echo ":: ai-inst installed successfully!"
echo "   Run 'ai-inst help' to get started."
