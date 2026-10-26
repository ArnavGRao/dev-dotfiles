#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ------------------------------------------------------------------------------
# 1. Global Git Ignore Configuration
# Ensures injected instruction files, prompt templates, and Graft/Trail caches
# never pollute `git status` inside your project repositories.
# ------------------------------------------------------------------------------
mkdir -p "$HOME/.config/git"
cat << 'EOF' > "$HOME/.config/git/ignore"
.github/copilot-instructions.md
.github/prompts/
AGENTS.md
CLAUDE.md
.agents/
.claude/
.trail/
graft/
.mcp.json
EOF
git config --global core.excludesfile "$HOME/.config/git/ignore"

# ------------------------------------------------------------------------------
# 2. Global Skill Deployment (Antigravity AI & Multi-Agent Discovery)
# Copies all Ponytail and Caveman sub-skill folders into global agent paths
# and enforces default active state configs where supported.
# ------------------------------------------------------------------------------
mkdir -p "$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.config/caveman"

if [ -d "$DOTFILES_DIR/instructions/skills/ponytail" ]; then
  cp -r "$DOTFILES_DIR/instructions/skills/ponytail/"* "$HOME/.agents/skills/" 2>/dev/null || true
  cp -r "$DOTFILES_DIR/instructions/skills/ponytail/"* "$HOME/.claude/skills/" 2>/dev/null || true
fi

if [ -d "$DOTFILES_DIR/instructions/skills/caveman" ]; then
  cp -r "$DOTFILES_DIR/instructions/skills/caveman/"* "$HOME/.agents/skills/" 2>/dev/null || true
  cp -r "$DOTFILES_DIR/instructions/skills/caveman/"* "$HOME/.claude/skills/" 2>/dev/null || true
fi

# Remove top-level plugin.json if copied from skills root so only skill directories remain
rm -f "$HOME/.agents/skills/plugin.json" "$HOME/.claude/skills/plugin.json"

# Force Caveman default mode configuration
cat << 'EOF' > "$HOME/.config/caveman/config.json"
{
  "defaultMode": "caveman"
}
EOF

# ------------------------------------------------------------------------------
# 3. Runtime CLI Installation (Trail-Code / Graft & Caveman Engine)
# Installs the global npm packages for MCP servers and codebase graph indexing.
# ------------------------------------------------------------------------------
export PATH="$HOME/.local/bin:$PATH"

if ! command -v npm &> /dev/null || [ "$(node -v 2>/dev/null | cut -d'.' -f1 | tr -d 'v')" -lt 22 ]; then
  echo "Node.js >= 22 not found. Installing portable Node into ~/.local..."

  ARCH="x64"
  if [ "$(uname -m)" = "aarch64" ]; then ARCH="arm64"; fi

  NODE_VER="v22.14.0"
  NODE_URL="https://nodejs.org/dist/${NODE_VER}/node-${NODE_VER}-linux-${ARCH}.tar.gz"

  mkdir -p "$HOME/.local/lib" "$HOME/.local/bin"
  curl -fsSL "$NODE_URL" | tar -xz -C "$HOME/.local/lib"

  # Link node, npm, and npx to ~/.local/bin
  ln -sf "$HOME/.local/lib/node-${NODE_VER}-linux-${ARCH}/bin/"* "$HOME/.local/bin/"

  # Ensure future interactive terminal sessions inherit the PATH
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
  if [ -f "$HOME/.zshrc" ]; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
  fi
fi

# Set npm global prefix to ~/.local so global packages don't require sudo
export npm_config_prefix="$HOME/.local"

# Install Trail-Code and Caveman CLIs
npm install -g --silent @trailhq/trail-code @caveman-ai/cli 2>/dev/null || true

# ------------------------------------------------------------------------------
# 4. Workspace Injection, Copilot Slash-Prompt Mapping & Graft Indexing
# Loops through every mounted project workspace in /workspaces/*
# ------------------------------------------------------------------------------
for ws in /workspaces/*; do
  if [ -d "$ws" ] && [ "$(basename "$ws")" != "dotfiles" ] && [ "$(basename "$ws")" != "dev-dotfiles" ]; then

    # A. Inject Always-On Base Instructions (Ponytail + Caveman Master Rules)
    mkdir -p "$ws/.github"
    if [ -f "$DOTFILES_DIR/instructions/copilot-instructions.md" ]; then
      cp "$DOTFILES_DIR/instructions/copilot-instructions.md" "$ws/.github/copilot-instructions.md"
    fi
    if [ -f "$DOTFILES_DIR/instructions/AGENTS.md" ]; then
      cp "$DOTFILES_DIR/instructions/AGENTS.md" "$ws/AGENTS.md"
    fi

    # B. Bonus: Convert all sub-skills into native GitHub Copilot `/` prompts
    # Allows invoking `/ponytail-review`, `/ultracave`, `/caveman-commit`, etc. in Copilot Chat
    mkdir -p "$ws/.github/prompts"
    for skill_dir in "$HOME/.agents/skills/"*; do
      if [ -d "$skill_dir" ] && [ -f "$skill_dir/SKILL.md" ]; then
        skill_name="$(basename "$skill_dir")"
        cp "$skill_dir/SKILL.md" "$ws/.github/prompts/${skill_name}.prompt.md"
      fi
    done

    # C. Initialize Trail-Code (Graft) Tree-Sitter Code Map in the workspace
    if command -v trail &> /dev/null; then
      (cd "$ws" && trail init --yes &>/dev/null || trail build &>/dev/null || true)
    fi

  fi
done
