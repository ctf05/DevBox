# syntax=docker/dockerfile:1.7

FROM ubuntu:24.04

ARG NODE_VERSION=22

# TZ=UTC is a privacy posture, not a preference: a local zone stamps a
# recoverable offset onto every timestamp any tool on this box emits, which
# pins the operator to a geography. entrypoint.sh re-asserts this at
# boot even if the container is started with -e TZ=..., and /etc/zsh/zshenv
# re-asserts it for login shells, which sshd starts in a clean environment.
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC

# ── Base apt layer (rarely changes; heavy cache value) ─────────────
# All shells, editors, modern CLI tools available in apt, language deps
# for treesitter/mason builds, and plugins for zsh.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget gnupg sudo openssh-server \
      git tmux zsh build-essential locales tzdata jq unzip ncurses-term \
      faketime \
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

# ── claude-swap — multi-account rotation for Claude Code ───────────
# Installs the `cswap` CLI system-wide (pipx venv
# under /opt, shim in /usr/local/bin). entrypoint.sh runs `cswap auto` as `dev`
# on boot to switch accounts before the active one hits its limit (on by
# default; CSWAP_ENABLED=0 to disable per-container). Account logins and state
# live under /home/dev/.local/share/claude-swap, on the persistent home mount,
# so nothing account-specific is baked into the image.
# 0.26.0 is the first stable release with the consume-first strategy and a
# threshold ceiling above 95. `--version` records what landed in the build log.
ARG CSWAP_VERSION=0.26.0
RUN PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin \
      pipx install "claude-swap==${CSWAP_VERSION}" \
    && chmod -R a+rX /opt/pipx \
    && /usr/local/bin/cswap --version

# ── earlyoom — ends agent commands before the host runs out of RAM ──
# Built from source: noble ships 1.7, which predates --ignore, and --ignore is
# what keeps Claude sessions, tmux and the daemons off the kill list. One C
# file set and no dependencies beyond the toolchain above. entrypoint.sh runs it.
ARG EARLYOOM_VERSION=1.9.0
RUN curl -fsSL "https://github.com/rfjakob/earlyoom/archive/refs/tags/v${EARLYOOM_VERSION}.tar.gz" \
      | tar -xz -C /tmp \
    && make -C "/tmp/earlyoom-${EARLYOOM_VERSION}" earlyoom VERSION="v${EARLYOOM_VERSION}" \
    && install -m 755 "/tmp/earlyoom-${EARLYOOM_VERSION}/earlyoom" /usr/local/bin/earlyoom \
    && rm -rf "/tmp/earlyoom-${EARLYOOM_VERSION}" \
    && /usr/local/bin/earlyoom -v

# ── Playwright browsers + their deps (slow, cache-stable) ──────────
# Install into a system-wide path (not root's $HOME cache) so the `dev`
# user can use them. This is a warm-cache seed at `playwright@latest`; the dir
# is world-writable + sticky (1777) so an app pinned to an OLDER playwright can
# `playwright install` its exact browser revisions into the same location at
# runtime (revisions are per-version, so the seed rarely matches an app's pin).
#
# PLAYWRIGHT_BROWSERS_PATH must reach the RUNTIME shell for any of this to work.
# A Docker `ENV` only reaches PID 1 (the entrypoint) — sshd starts login shells
# in a clean environment, so interactive/e2e sessions never saw it and fell back
# to $HOME/.cache/ms-playwright (empty/stale, and $HOME-dependent). We therefore
# set it in three places: this ENV (build + PID 1), /etc/environment (pam_env,
# every login shell regardless of shell type), and /etc/zsh/zshenv (config/zshenv,
# every zsh invocation incl. the node/pnpm children it spawns).
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
RUN echo 'PLAYWRIGHT_BROWSERS_PATH=/ms-playwright' >> /etc/environment
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    mkdir -p /ms-playwright \
    && npx --yes playwright@latest install --with-deps chromium firefox webkit \
    && chmod -R a+rwX /ms-playwright \
    && chmod 1777 /ms-playwright

# ── iGPU userspace drivers ─────────────────────────────────────────
# Playwright's --with-deps brings the Mesa GL driver (iris) and the Vulkan
# loader, but NOT a Vulkan ICD — so any GL-on-Vulkan path fails with
# "vkCreateInstance failed". Add the Intel Vulkan driver so the iGPU (passed in
# at runtime via --device /dev/dri) can accelerate headless rendering instead of
# falling back to CPU/llvmpipe.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      mesa-vulkan-drivers

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
# The deny list keeps container runtimes off the passwordless path. A second
# dockerd or containerd started by hand against the same state directory
# races the entrypoint's own daemon over cgroups, netns and veth teardown,
# which is severe enough on a shared kernel to take the host down. `setsid`
# is denied because sudo matches the invoked binary: `sudo setsid containerd`
# would otherwise walk straight past a `containerd` denial.
# This is a guardrail against a plausible mistake, not a security boundary —
# `sudo sh -c` defeats it by design. Making it a boundary means an allow-list.
RUN userdel -r ubuntu 2>/dev/null || true \
    && useradd -m -u 1000 -U -s /bin/zsh dev \
    && printf '%s\n' 'dev ALL=(ALL) NOPASSWD:ALL, !/usr/sbin/service, !/usr/bin/dockerd, !/usr/bin/containerd, !/usr/bin/setsid, !/bin/setsid' > /etc/sudoers.d/dev \
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
COPY pinclock.sh /usr/local/bin/pinclock
COPY scrub-mtimes.sh /usr/local/bin/scrub-mtimes

# ttyguard filters terminal capability chatter out of the tmux client's pty,
# and the tmux shim (ahead of /usr/bin/tmux on PATH) is what puts it there.
# Without it, attaching from the Superset app sprays the client's late
# device-attribute replies across the pane as keystrokes. See ttyguard.py.
COPY ttyguard.py /usr/local/bin/ttyguard
COPY tmux-shim.sh /usr/local/bin/tmux

# keyrouter puts one Anthropic API endpoint in front of several org API keys
# (the monthly credits of each Max plan) and moves to the next key when one
# runs out. Stdlib-only Python, so it adds no layer of its own. See keyrouter.py.
COPY keyrouter.py /usr/local/bin/keyrouter
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/new-worktree \
             /usr/local/bin/pinclock /usr/local/bin/scrub-mtimes \
             /usr/local/bin/ttyguard /usr/local/bin/tmux \
             /usr/local/bin/keyrouter \
    && [ -x /usr/bin/tmux ]

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
