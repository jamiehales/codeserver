# codeserver

Publishes a custom docker image for vscode using ghcr.io/coder/code-server as the base image with custom tooling installed

## Claude remote-control supervisor

On startup the container runs `claude-supervisor.sh` in the background. Every `CLAUDE_SUPERVISOR_INTERVAL` seconds (default 30) it scans the folders directly under `DEV_ROOT` (default `/mnt/development`) and ensures a `claude --model sonnet --remote-control --name code-<folder>` instance (in a detached tmux session) is running in each:

- new folders get an instance; instances that exit are restarted
- a restart resumes the newest conversation named `code-<folder>`, and only starts a new one if there isn't any
- the "Resume this conversation?" dialog is answered with Resume automatically, which spends the usage it quotes on your next message
- a `NOCLAUDE` file in a folder's root stops its instance and prevents restarts
- removed folders have their instance stopped

Attach with `tmux -L claude attach -t claude-<folder>`. Logs: `~/.config/claude-supervisor.log`. Disable with `CLAUDE_SUPERVISOR=false`. Set the model with `CLAUDE_MODEL` (default `sonnet`). Hidden folders are ignored. Claude must already be logged in for instances to come up unattended. The supervisor marks first-run onboarding as done and each folder as trusted in `$CLAUDE_CONFIG_DIR/.claude.json`, so every folder under `DEV_ROOT` is trusted automatically; add `NOCLAUDE` to any folder you don't want that for.

Use `/clear` for a fresh start in a session. Renaming a session drops it from the lookup above, so the next restart starts a new conversation. A resumed conversation stays on its own model, so `CLAUDE_MODEL` only applies to new ones.

## Stopping the container

On `docker stop`, every `claude` process, including ones in VS Code terminals, is asked to exit before code-server stops. It waits up to `CLAUDE_SHUTDOWN_TIMEOUT` seconds (default 8), which has to fit inside Docker's stop timeout (default 10). To allow longer, raise both, for example `--stop-timeout 30` in Unraid's Extra Parameters.
