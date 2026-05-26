# syntax=docker/dockerfile:1.7

FROM ubuntu:24.04

ARG NODE_VERSION=22

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# ── Base apt layer (rarely changes; heavy cache value) ─────────────
# All shells, editors, modern CLI tools available in apt, language deps
# for treesitter/mason builds, and plugins for zsh.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget gnupg sudo openssh-server \
      git tmux zsh build-essential locales tzdata jq unzip ncurses-term \
      python3 python3-pip pipx \
      ripgrep fd-find bat fzf httpie \
      zsh-autosuggestions zsh-syntax-highlighting \
      btop \
      tree-sitter-cli \
      gcc g++ make cmake \
      libssl-dev pkg-config \
      openjdk-21-jdk-headless \
    && locale-gen en_US.UTF-8

# ── NodeSource + pnpm + Claude Code ────────────────────────────────
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g pnpm @anthropic-ai/claude-code

# ── Playwright browsers + their deps (slow, cache-stable) ──────────
# Install into a system-wide path (not root's $HOME cache) so the `dev`
# user can use them. PLAYWRIGHT_BROWSERS_PATH is also exported as an ENV
# below so the runtime user resolves the same location.
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    mkdir -p /ms-playwright \
    && npx --yes playwright@latest install --with-deps chromium firefox webkit \
    && chmod -R a+rwX /ms-playwright \
    && chmod 1777 /ms-playwright

# ── Docker Engine + CLI + buildx + compose (official apt repo) ─────
# Ubuntu 24.04 (noble). Per https://docs.docker.com/engine/install/ubuntu/.
# The daemon won't be started by this image's entrypoint; consumers can
# either bind-mount the host /var/run/docker.sock (docker-out-of-docker)
# or run the container with --privileged and start dockerd manually.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && printf 'Types: deb\nURIs: https://download.docker.com/linux/ubuntu\nSuites: noble\nComponents: stable\nArchitectures: %s\nSigned-By: /etc/apt/keyrings/docker.asc\n' "$(dpkg --print-architecture)" > /etc/apt/sources.list.d/docker.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
         docker-ce docker-ce-cli containerd.io \
         docker-buildx-plugin docker-compose-plugin

# ── GitHub-release binaries (parallel download) + terminfo ────────
# This layer rebuilds when versions in install-tools.sh change.
COPY install-tools.sh /tmp/install-tools.sh
COPY config/ghostty.terminfo /tmp/ghostty.terminfo
RUN bash /tmp/install-tools.sh && rm /tmp/install-tools.sh /tmp/ghostty.terminfo

# ── User: `dev` (UID 1000), passwordless sudo, zsh login shell ─────
RUN userdel -r ubuntu 2>/dev/null || true \
    && useradd -m -u 1000 -U -s /bin/zsh dev \
    && echo "dev ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/dev \
    && groupadd -f kvm \
    && usermod -aG docker,kvm dev \
    && mkdir -p /etc/skel-dev \
    && cp -a /home/dev/. /etc/skel-dev/

# ── SSH server hardening ───────────────────────────────────────────
RUN mkdir -p /var/run/sshd \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/#PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config \
    && sed -i 's|HostKey /etc/ssh/|HostKey /etc/ssh/keys/|g' /etc/ssh/sshd_config

# ── System-wide config files (volatile; last for max cache reuse) ──
# Each tool's config search path is set in /etc/zsh/zshenv so updates
# to these files propagate without touching /home/dev.
COPY config/zshenv          /etc/zsh/zshenv
COPY config/zshrc           /etc/zsh/zshrc
COPY config/starship.toml   /etc/starship/config.toml
COPY config/atuin.toml      /etc/atuin/config.toml
COPY config/gitconfig       /etc/gitconfig
COPY config/lazygit.yml     /etc/lazygit/config.yml
COPY config/yazi-theme.toml /etc/yazi/theme.toml
COPY config/nvim            /etc/xdg/nvim
COPY tmux.conf              /etc/tmux.conf

# ── Skeleton files merged into /home/dev on every boot via cp -an ──
# (only needed for tools without a system-wide config path: btop)
COPY config/skel/           /etc/skel-dev/

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY new-worktree.sh /usr/local/bin/new-worktree
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/new-worktree

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
