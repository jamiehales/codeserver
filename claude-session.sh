#!/bin/bash
# Runs "claude --remote-control" for the current folder inside a supervised tmux
# session, restarting it when it exits. See claude-supervisor.sh.
#  - Resumes the newest conversation named code-<folder>, so a restart continues
#    the same conversation. Starts a new one if there isn't any.
#  - Answers "Resume this conversation?", which nobody is around to answer.
set -u

MODEL="${1:-sonnet}"
NAME="code-$(basename "$PWD")"
STATE_DIR="${CLAUDE_SUPERVISOR_STATE_DIR:-/tmp}"
STOP_FLAG="$STATE_DIR/claude-supervisor.stopping"
LOG_FILE="${CLAUDE_SUPERVISOR_LOG:-$HOME/.config/claude-supervisor.log}"

# Logs go to the file: writing to the pane would draw over claude's screen.
log() { printf '%s [%s] %s\n' "$(date '+%F %T')" "$NAME" "$*" >>"$LOG_FILE" 2>/dev/null; }

# Prints the ID of the newest conversation in this folder whose title is $NAME.
# A transcript's filename is its session ID, and a later rename overrides an
# earlier title. Prints nothing if the transcript format ever stops matching,
# which means a new conversation.
find_session() {
  python3 - "$NAME" "$PWD" <<'PY' 2>/dev/null
import glob, json, os, re, sys
name, cwd = sys.argv[1:]
config = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
folder = os.path.join(config, "projects", re.sub(r"[^A-Za-z0-9]", "-", cwd))
for path in sorted(glob.glob(os.path.join(folder, "*.jsonl")), key=os.path.getmtime, reverse=True):
    title = None
    with open(path, "rb") as f:
        for line in f:
            if b'"custom-title"' in line:
                try:
                    entry = json.loads(line)
                except ValueError:
                    continue
                if entry.get("type") == "custom-title":
                    title = entry.get("customTitle")
    if title == name:
        print(os.path.splitext(os.path.basename(path))[0])
        break
PY
}

# Picks "Resume" whenever the dialog is showing. It can appear at startup or when
# the first message arrives after a long break, so this watches the whole session.
answer_resume_dialog() {
  local screen answered=""
  while sleep 3; do
    screen="$(tmux capture-pane -p -t "$TMUX_PANE" 2>/dev/null)" || return
    case "$screen" in *"Resume this conversation?"*) ;; *) answered=""; continue ;; esac
    [ "$screen" = "$answered" ] && continue
    grep -qE '^[[:space:]│]*(❯ *)?([0-9]+\. *)?Start a new conversation' <<<"$screen" || continue
    if grep -qE '^[[:space:]│]*❯ *([0-9]+\. *)?Resume[[:space:]│]*$' <<<"$screen"; then
      log "answering the resume dialog with Resume"
      tmux send-keys -t "$TMUX_PANE" Enter
      answered="$screen"
    elif grep -qE '^[[:space:]│]*❯' <<<"$screen"; then
      tmux send-keys -t "$TMUX_PANE" Up
    fi
  done
}

answer_resume_dialog &
watcher=$!
trap 'kill "$watcher" 2>/dev/null' EXIT

skip_resume=false
while [ ! -e "$STOP_FLAG" ]; do
  session=""
  $skip_resume || session="$(find_session)"
  skip_resume=false
  start=$(date +%s)
  if [ -n "$session" ]; then
    log "resuming $session"
    # No --model: a resumed conversation stays on the model it was using.
    claude --resume "$session" --name "$NAME" --remote-control
  else
    log "starting a new conversation"
    claude --model "$MODEL" --remote-control --name "$NAME"
  fi
  status=$?
  log "claude exited ($status)"
  [ -e "$STOP_FLAG" ] && break
  if [ $(($(date +%s) - start)) -lt 5 ]; then
    # Died straight away: don't get stuck on a conversation that won't resume.
    [ -n "$session" ] && [ "$status" -ne 0 ] && skip_resume=true
    sleep 5
  fi
done
