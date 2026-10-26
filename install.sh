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
.agent/
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
mkdir -p "$HOME/.agent/skills" "$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.config/caveman"

# Helper function to copy skills without accidental double-nesting
deploy_skills() {
  local src="$1"
  local dest="$2"
  if [ -d "$src" ]; then
    # If the source folder itself contains a 'skills' subfolder, copy from inside it
    if [ -d "$src/skills" ]; then
      cp -r "$src/skills/"* "$dest/" 2>/dev/null || true
    else
      cp -r "$src/"* "$dest/" 2>/dev/null || true
    fi
  fi
}

deploy_skills "$DOTFILES_DIR/instructions/skills/ponytail" "$HOME/.agent/skills"
deploy_skills "$DOTFILES_DIR/instructions/skills/caveman"  "$HOME/.agent/skills"

# Mirror to plural and claude paths
cp -r "$HOME/.agent/skills/"* "$HOME/.agents/skills/" 2>/dev/null || true
cp -r "$HOME/.agent/skills/"* "$HOME/.claude/skills/" 2>/dev/null || true

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

# Minimum required major version (Caveman engine baseline)
MIN_NODE_MAJOR=22

# Detect container system architecture
ARCH="x64"
case "$(uname -m)" in
  aarch64|arm64) ARCH="arm64" ;;
  x86_64)        ARCH="x64" ;;
esac

# Check existing Node.js installation (if present)
CURRENT_NODE_MAJOR=0
if command -v node &> /dev/null; then
  CURRENT_NODE_MAJOR=$(node -v 2>/dev/null | tr -d 'v' | cut -d'.' -f1)
fi

# If Node is missing or older than the required minimum, install/update to latest LTS
if [ "$CURRENT_NODE_MAJOR" -lt "$MIN_NODE_MAJOR" ]; then
  echo "Node.js >= ${MIN_NODE_MAJOR} not detected. Resolving latest LTS..."

  # Query official Node.js release index for the newest LTS version (tab-delimited, no jq needed)
  LATEST_LTS=$(curl -fsSL https://nodejs.org/download/release/index.tab 2>/dev/null | \
    awk 'NR>1 && $NF!="-" {print $1; exit}')

  # Safe fallback if network query times out or fails
  NODE_VER="${LATEST_LTS:-v22.14.0}"
  NODE_URL="https://nodejs.org/dist/${NODE_VER}/node-${NODE_VER}-linux-${ARCH}.tar.gz"

  echo "Installing Node.js ${NODE_VER} (${ARCH}) to ~/.local..."

  # Create clean installation directory
  NODE_DIR="$HOME/.local/lib/nodejs"
  mkdir -p "$NODE_DIR" "$HOME/.local/bin"

  # Stream, extract, and strip top-level folder so path is version-agnostic
  curl -fsSL "$NODE_URL" | tar -xz -C "$NODE_DIR" --strip-components=1

  # Create persistent symlinks to ~/.local/bin
  ln -sf "$NODE_DIR/bin/"* "$HOME/.local/bin/"

  # Ensure interactive subshells and new container terminals retain PATH
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$rc" ] && ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$rc"; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc"
    fi
  done
fi

# Configure npm prefix so global installs write to ~/.local without requiring root/sudo
export npm_config_prefix="$HOME/.local"

# Install or update Trail-Code and Caveman to the latest available releases
if command -v npm &> /dev/null; then
  if npm install -g --silent @trailhq/trail-code@latest @caveman-ai/cli@latest 2>/dev/null; then
    echo "Trail-Code and Caveman installed successfully."
  else
    echo "Error: Failed to install Trail-Code and Caveman packages via npm." >&2
  fi
else
  echo "Error: npm not found in PATH. Trail-Code and Caveman failed to install." >&2
fi

# ------------------------------------------------------------------------------
# 4. Workspace Injection, Copilot Slash-Prompt Mapping & Graft Indexing
# Loops through every mounted project workspace in /workspaces/*
# ------------------------------------------------------------------------------
for ws in /workspaces/*; do
  if [ -d "$ws" ] && [ "$(basename "$ws")" != "dotfiles" ] && [ "$(basename "$ws")" != "dev-dotfiles" ]; then

    # A. Inject Instructions for Copilot and Agent Roots
    mkdir -p "$ws/.github" "$ws/.agent/skills" "$ws/.agents/skills"

    if [ -f "$DOTFILES_DIR/instructions/copilot-instructions.md" ]; then
      cp "$DOTFILES_DIR/instructions/copilot-instructions.md" "$ws/.github/copilot-instructions.md"
    fi
    if [ -f "$DOTFILES_DIR/instructions/AGENTS.md" ]; then
      cp "$DOTFILES_DIR/instructions/AGENTS.md" "$ws/AGENTS.md"
    fi

    # B. Copy skills directly into workspace for Antigravity discovery
    cp -r "$HOME/.agent/skills/"* "$ws/.agent/skills/" 2>/dev/null || true
    cp -r "$HOME/.agent/skills/"* "$ws/.agents/skills/" 2>/dev/null || true

    # C. Convert all sub-skills into native Copilot `/` prompts
    mkdir -p "$ws/.github/prompts"
    for skill_dir in "$HOME/.agent/skills/"*; do
      if [ -d "$skill_dir" ] && [ -f "$skill_dir/SKILL.md" ]; then
        skill_name="$(basename "$skill_dir")"
        cp "$skill_dir/SKILL.md" "$ws/.github/prompts/${skill_name}.prompt.md"
      fi
    done

    # D. Initialize Trail-Code (Graft)
    if command -v trail &> /dev/null; then
      (cd "$ws" && trail init --yes &>/dev/null || trail build &>/dev/null || true)
    fi

  fi
done
