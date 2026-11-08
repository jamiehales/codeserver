#!/bin/bash
# Keeps a "claude --remote-control" instance running (in a detached tmux session)
# for every project folder directly under DEV_ROOT.
#  - New folder           -> instance started
#  - Instance exited      -> restarted immediately (5s pause if it died within 5s)
#  - NOCLAUDE in folder   -> instance killed and not restarted
#  - Folder removed       -> instance killed
# Attach to an instance with: tmux -L claude attach -t claude-<folder>
#
# "claude-supervisor.sh stop" shuts everything down cleanly, for docker stop.
set -u

DEV_ROOT="${DEV_ROOT:-/mnt/development}"
INTERVAL="${CLAUDE_SUPERVISOR_INTERVAL:-30}"
TMUX_SOCKET="${CLAUDE_TMUX_SOCKET:-claude}"
SESSION_PREFIX="claude-"
MODEL="${CLAUDE_MODEL:-sonnet}"
STATE_DIR="${CLAUDE_SUPERVISOR_STATE_DIR:-/tmp}"
PID_FILE="$STATE_DIR/claude-supervisor.pid"
STOP_FLAG="$STATE_DIR/claude-supervisor.stopping"
SHUTDOWN_TIMEOUT="${CLAUDE_SHUTDOWN_TIMEOUT:-8}"
SESSION_SCRIPT="${CLAUDE_SESSION_SCRIPT:-/usr/local/bin/claude-session.sh}"

log() { printf '%s [claude-supervisor] %s\n' "$(date '+%F %T')" "$*"; }
tm() { tmux -L "$TMUX_SOCKET" "$@"; }

# Stops the supervisor and session loops so nothing restarts, asks every claude
# process to exit (including ones in VS Code terminals), and waits for them.
stop_all() {
  touch "$STOP_FLAG"
  [ -f "$PID_FILE" ] && kill "$(cat "$PID_FILE")" 2>/dev/null
  pkill -TERM -x claude
  local waited=0
  while pgrep -x claude >/dev/null && [ "$waited" -lt "$SHUTDOWN_TIMEOUT" ]; do
    sleep 1
    waited=$((waited + 1))
  done
  if pgrep -x claude >/dev/null; then
    log "claude still running after ${SHUTDOWN_TIMEOUT}s; stopping anyway"
  else
    log "all claude sessions exited after ${waited}s"
  fi
  tm kill-server 2>/dev/null
}

if [ "${1:-}" = "stop" ]; then
  stop_all
  exit 0
fi

rm -f "$STOP_FLAG"
echo "$$" >"$PID_FILE"

export NVM_DIR="${NVM_DIR:-$HOME/.local/share/nvm}"
# shellcheck disable=SC1091
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# tmux session names can't contain '.' or ':'
session_name() { printf '%s%s' "$SESSION_PREFIX" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9_-' '_')"; }

# Unattended sessions would otherwise sit at the first-run theme picker and the
# "trust this folder" prompt, so mark onboarding done and the folder trusted.
prepare_config() {
  python3 - "$1" <<'PY'
import json, os, sys, tempfile
cfg_dir = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~")
path = os.path.join(cfg_dir, ".claude.json")
try:
    with open(path) as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
project = data.setdefault("projects", {}).setdefault(sys.argv[1], {})
if data.get("hasCompletedOnboarding") and project.get("hasTrustDialogAccepted"):
    sys.exit(0)
data["hasCompletedOnboarding"] = True
project["hasTrustDialogAccepted"] = True
fd, tmp = tempfile.mkstemp(dir=cfg_dir, prefix=".claude.json.")
with os.fdopen(fd, "w") as f:
    json.dump(data, f, indent=2)
os.replace(tmp, path)
PY
}

while true; do
  if ! command -v claude >/dev/null 2>&1; then
    log "claude not found on PATH yet; waiting"
    sleep "$INTERVAL"
    continue
  fi

  declare -A wanted=()
  for dir in "$DEV_ROOT"/*/; do
    [ -d "$dir" ] || continue
    dir="${dir%/}"
    name="$(basename "$dir")"
    case "$name" in .*) continue ;; esac # skip hidden folders
    session="$(session_name "$name")"

    if [ -e "$dir/NOCLAUDE" ]; then
      if tm has-session -t "=$session" 2>/dev/null; then
        log "NOCLAUDE found in $name; stopping"
        tm kill-session -t "=$session"
      fi
      continue
    fi

    wanted["$session"]=1
    if ! tm has-session -t "=$session" 2>/dev/null; then
      log "starting claude in $name"
      prepare_config "$dir" || log "failed to update claude config for $name"
      tm new-session -d -s "$session" -c "$dir" "$(printf '%q %q' "$SESSION_SCRIPT" "$MODEL")" \
        || log "failed to start session for $name"
    fi
  done

  # Kill sessions whose folder was deleted or is now excluded
  while IFS= read -r session; do
    case "$session" in "$SESSION_PREFIX"*) ;; *) continue ;; esac
    if [ -z "${wanted[$session]:-}" ]; then
      log "stopping $session (folder removed or excluded)"
      tm kill-session -t "=$session"
    fi
  done < <(tm list-sessions -F '#{session_name}' 2>/dev/null)

  unset wanted
  sleep "$INTERVAL"
done
