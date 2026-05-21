FROM ubuntu:24.04

ARG NODE_VERSION=22

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget gnupg sudo openssh-server \
      git tmux zsh build-essential locales tzdata jq unzip ncurses-term \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/ghostty.terminfo \
      https://raw.githubusercontent.com/ghostty-org/ghostty/main/src/terminfo/ghostty.terminfo \
    && tic -x -o /usr/share/terminfo /tmp/ghostty.terminfo \
    && rm /tmp/ghostty.terminfo

RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g pnpm @anthropic-ai/claude-code \
    && rm -rf /var/lib/apt/lists/*

RUN npx --yes playwright@latest install --with-deps chromium firefox webkit \
    && rm -rf /var/lib/apt/lists/*

RUN userdel -r ubuntu 2>/dev/null || true \
    && useradd -m -u 1000 -U -s /bin/zsh dev \
    && echo "dev ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/dev \
    && mkdir -p /etc/skel-dev \
    && cp -a /home/dev/. /etc/skel-dev/

RUN mkdir -p /var/run/sshd \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/#PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config \
    && sed -i 's|HostKey /etc/ssh/|HostKey /etc/ssh/keys/|g' /etc/ssh/sshd_config

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
