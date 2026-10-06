# Dockerfile for code-server with Astro, Vercel CLI, and Rust support
FROM ghcr.io/coder/code-server:latest

USER root
ENV DEBIAN_FRONTEND=noninteractive \
    RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:/usr/local/bin:$PATH

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        gnupg \
        lsb-release \
        build-essential \
        python3 \
        python3-pip \
        tmux \
        pkg-config \
        libssl-dev \
        zlib1g-dev \
    && mkdir -p -m 755 /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ENV PATH=/usr/local/cargo/bin:$PATH
ENV PUID=99 PGID=100 UMASK=0002
# Keep Claude Code settings/history on the persisted ~/.config mount
ENV CLAUDE_CONFIG_DIR=/home/coder/.config/claude
# gh already defaults to ~/.config/gh; pin it so the token stays on the persisted mount
ENV GH_CONFIG_DIR=/home/coder/.config/gh

# Set up .bashrc with nvm init and .config sourcing
RUN touch /home/coder/.bashrc && \
    echo '' >> /home/coder/.bashrc && \
    echo 'export NVM_DIR="${HOME}/.local/share/nvm"' >> /home/coder/.bashrc && \
    echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> /home/coder/.bashrc && \
    echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> /home/coder/.bashrc && \
    echo '' >> /home/coder/.bashrc && \
    echo '# Source persisted bashrc from mounted config directory' >> /home/coder/.bashrc && \
    echo '[ -f "${HOME}/.config/.bashrc" ] && . "${HOME}/.config/.bashrc"' >> /home/coder/.bashrc

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY claude-supervisor.sh /usr/local/bin/claude-supervisor.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh /usr/local/bin/claude-supervisor.sh

USER root

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh", "--bind-addr", "0.0.0.0:8080", "."]
