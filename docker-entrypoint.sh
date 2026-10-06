#!/bin/sh
set -eu

PUID="${PUID:-99}"
PGID="${PGID:-100}"
UMASK="${UMASK:-0002}"

# Only adjust if running as root
if [ "$(id -u)" = '0' ]; then
  # Ensure coder group exists with correct GID
  if ! getent group "$PGID" >/dev/null 2>&1; then
    groupmod -g "$PGID" coder 2>/dev/null || groupadd -g "$PGID" coder
  else
    # Try to rename conflicting group if not already named coder
    existing_group=$(getent group "$PGID" | cut -d: -f1)
    if [ "$existing_group" != "coder" ]; then
      groupmod -n coder "$existing_group" 2>/dev/null || true
    fi
  fi

  # Ensure coder user exists with correct UID
  if id coder >/dev/null 2>&1; then
    usermod -u "$PUID" -g "$PGID" coder 2>/dev/null || true
  else
    useradd -u "$PUID" -g "$PGID" -m -s /bin/bash coder
  fi

  # Claude Code config lives on the persisted ~/.config mount (CLAUDE_CONFIG_DIR).
  # One-time migration of any existing non-persisted ~/.claude state.
  CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-/home/coder/.config/claude}"
  if [ ! -e "$CLAUDE_DIR" ]; then
    mkdir -p "$(dirname "$CLAUDE_DIR")"
    if [ -d /home/coder/.claude ]; then
      cp -a /home/coder/.claude "$CLAUDE_DIR"
      [ -f /home/coder/.claude.json ] && cp -a /home/coder/.claude.json "$CLAUDE_DIR/.claude.json"
    else
      mkdir -p "$CLAUDE_DIR"
    fi
  fi

  # Fix home directory ownership
  if [ -d "/home/coder" ]; then
    chown -R "$PUID":"$PGID" /home/coder
  fi

  # Ensure .bashrc has nvm init and .config sourcing (re-adds if home was recreated)
  BASHRC="/home/coder/.bashrc"
  if ! grep -qF 'NVM_DIR' "$BASHRC" 2>/dev/null; then
    printf '\nexport NVM_DIR="${HOME}/.local/share/nvm"\n[ -s "$NVM_DIR/nvm.sh" ] && \\. "$NVM_DIR/nvm.sh"\n[ -s "$NVM_DIR/bash_completion" ] && \\. "$NVM_DIR/bash_completion"\n' >> "$BASHRC"
    chown "$PUID":"$PGID" "$BASHRC"
  fi
  if ! grep -qF '.config/.bashrc' "$BASHRC" 2>/dev/null; then
    printf '\n# Source persisted bashrc from mounted config directory\n[ -f "${HOME}/.config/.bashrc" ] && . "${HOME}/.config/.bashrc"\n' >> "$BASHRC"
    chown "$PUID":"$PGID" "$BASHRC"
  fi

  # Run nvm setup as coder user
  cat > /tmp/nvm-setup.sh << 'NVMSCRIPT'
#!/bin/sh
set -e
NVM_DIR="/home/coder/.local/share/nvm"
if [ ! -f "$NVM_DIR/nvm.sh" ]; then
  # First boot after rebuild: install nvm, Node 24, and global packages
  mkdir -p "$NVM_DIR"
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | NVM_DIR="$NVM_DIR" PROFILE=/dev/null bash
  . "$NVM_DIR/nvm.sh"
  nvm install 24
  nvm alias default 24
  npm install -g pnpm astro vercel @anthropic-ai/claude-code
else
  # Subsequent boots: just update Claude Code
  . "$NVM_DIR/nvm.sh"
  npm install -g @anthropic-ai/claude-code
fi
NVMSCRIPT
  chmod +x /tmp/nvm-setup.sh
  su -s /bin/sh coder /tmp/nvm-setup.sh

  export HOME=/home/coder
fi

# Apply umask before starting services
umask "$UMASK"

# Call the original code-server entrypoint with all arguments
# This preserves the original startup behavior (fixuid, DOCKER_USER support, etc.)
exec /usr/bin/entrypoint.sh "$@"
