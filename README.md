# codeserver

Publishes a custom docker image for vscode using ghcr.io/coder/code-server as the base image with custom tooling installed

## Claude remote-control supervisor

On startup the container runs `claude-supervisor.sh` in the background. Every `CLAUDE_SUPERVISOR_INTERVAL` seconds (default 30) it scans the folders directly under `DEV_ROOT` (default `/mnt/development`) and ensures a `claude --remote-control` instance (in a detached tmux session) is running in each:

- new folders get an instance; instances that exit are restarted
- a `NOCLAUDE` file in a folder's root stops its instance and prevents restarts
- removed folders have their instance stopped

Attach with `tmux -L claude attach -t claude-<folder>`. Logs: `~/.config/claude-supervisor.log`. Disable with `CLAUDE_SUPERVISOR=false`. Hidden folders are ignored. Claude must already be logged in for instances to come up unattended, and the workspace trust prompt must be accepted by hand once per folder (attach to the instance and accept it).
