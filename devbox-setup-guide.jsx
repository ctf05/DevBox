import React, { useState, useEffect, useRef, useCallback } from 'react';
import {
  Check,
  Copy,
  AlertTriangle,
  Info,
  Terminal,
  Server,
  GitBranch,
  Container,
  Cloud,
  Laptop,
  Smartphone,
  Sparkles,
} from 'lucide-react';

const C = {
  bg: '#0E0C0A',
  surface: '#161310',
  surfaceHi: '#1F1B17',
  code: '#080705',
  text: '#F2EBDC',
  textDim: '#A89E8B',
  textFaint: '#6B6358',
  accent: '#E8A547',
  accentHi: '#F5C26E',
  accentLo: '#5C421C',
  warn: '#E07A5F',
  warnBg: '#1E1410',
  done: '#8FB58F',
  doneBg: '#11150F',
  info: '#7FA8C9',
  infoBg: '#0F1316',
  line: '#2A2520',
  lineHi: '#3D3530',
};

const F = {
  display: '"Instrument Serif", "Times New Roman", serif',
  body: '"Geist", -apple-system, "Helvetica Neue", sans-serif',
  mono: '"JetBrains Mono", "SF Mono", Menlo, monospace',
};

function CopyButton({ text }) {
  const [copied, setCopied] = useState(false);
  const onClick = useCallback(() => {
    navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 1400);
  }, [text]);
  return (
    <button
      onClick={onClick}
      aria-label="Copy"
      style={{
        background: 'transparent',
        border: `1px solid ${C.line}`,
        color: copied ? C.done : C.textDim,
        fontFamily: F.mono,
        fontSize: 11,
        padding: '4px 8px',
        borderRadius: 4,
        cursor: 'pointer',
        display: 'inline-flex',
        alignItems: 'center',
        gap: 5,
        letterSpacing: 0.5,
        transition: 'all 0.15s ease',
      }}
      onMouseEnter={(e) => {
        if (!copied) e.currentTarget.style.borderColor = C.lineHi;
      }}
      onMouseLeave={(e) => {
        if (!copied) e.currentTarget.style.borderColor = C.line;
      }}
    >
      {copied ? <Check size={12} /> : <Copy size={12} />}
      {copied ? 'COPIED' : 'COPY'}
    </button>
  );
}

function Code({ children, lang = 'bash', filename }) {
  const text = typeof children === 'string' ? children : '';
  return (
    <div
      style={{
        background: C.code,
        border: `1px solid ${C.line}`,
        borderRadius: 6,
        margin: '14px 0',
        overflow: 'hidden',
      }}
    >
      <div
        style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          padding: '8px 12px',
          borderBottom: `1px solid ${C.line}`,
          background: C.surface,
        }}
      >
        <span
          style={{
            fontFamily: F.mono,
            fontSize: 11,
            color: filename ? C.accent : C.textFaint,
            letterSpacing: 0.4,
          }}
        >
          {filename || lang.toUpperCase()}
        </span>
        <CopyButton text={text} />
      </div>
      <pre
        style={{
          margin: 0,
          padding: '14px 16px',
          overflowX: 'auto',
          fontFamily: F.mono,
          fontSize: 12.5,
          lineHeight: 1.7,
          color: C.text,
        }}
      >
        <code>{text}</code>
      </pre>
    </div>
  );
}

function Inline({ children }) {
  return (
    <code
      style={{
        fontFamily: F.mono,
        fontSize: '0.88em',
        background: C.surfaceHi,
        color: C.accentHi,
        padding: '1px 6px',
        borderRadius: 3,
        border: `1px solid ${C.line}`,
      }}
    >
      {children}
    </code>
  );
}

function Note({ kind = 'info', children }) {
  const conf = {
    info: { color: C.info, bg: C.infoBg, Icon: Info, label: 'Note' },
    warn: { color: C.warn, bg: C.warnBg, Icon: AlertTriangle, label: 'Heads up' },
  }[kind];
  const Icon = conf.Icon;
  return (
    <div
      style={{
        background: conf.bg,
        border: `1px solid ${C.line}`,
        borderLeft: `2px solid ${conf.color}`,
        borderRadius: 4,
        padding: '10px 14px',
        margin: '14px 0',
        display: 'flex',
        gap: 10,
        fontSize: 13.5,
        lineHeight: 1.6,
        color: C.textDim,
      }}
    >
      <Icon size={14} color={conf.color} style={{ flexShrink: 0, marginTop: 3 }} />
      <div style={{ flex: 1 }}>
        <span style={{ color: conf.color, fontWeight: 500, marginRight: 6 }}>
          {conf.label}.
        </span>
        {children}
      </div>
    </div>
  );
}

function Step({ num, title, complete, onToggle, children }) {
  return (
    <div
      style={{
        display: 'flex',
        gap: 16,
        margin: '24px 0',
        opacity: complete ? 0.55 : 1,
        transition: 'opacity 0.3s ease',
      }}
    >
      <button
        onClick={onToggle}
        aria-label={complete ? 'Mark incomplete' : 'Mark complete'}
        style={{
          width: 28,
          height: 28,
          minWidth: 28,
          borderRadius: '50%',
          border: `1px solid ${complete ? C.done : C.line}`,
          background: complete ? C.done : 'transparent',
          color: complete ? C.bg : C.textDim,
          fontFamily: F.mono,
          fontSize: 12,
          fontWeight: 500,
          cursor: 'pointer',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          marginTop: 2,
          transition: 'all 0.15s ease',
        }}
      >
        {complete ? <Check size={14} strokeWidth={2.5} /> : num}
      </button>
      <div style={{ flex: 1, minWidth: 0 }}>
        <h3
          style={{
            fontFamily: F.body,
            fontSize: 17,
            fontWeight: 500,
            color: C.text,
            margin: '4px 0 8px',
            letterSpacing: -0.2,
            textDecoration: complete ? 'line-through' : 'none',
            textDecorationColor: C.textFaint,
          }}
        >
          {title}
        </h3>
        <div
          style={{
            fontFamily: F.body,
            fontSize: 14.5,
            lineHeight: 1.65,
            color: C.textDim,
          }}
        >
          {children}
        </div>
      </div>
    </div>
  );
}

function Phase({ phase, index, complete, total, stepStates, toggleStep, sectionRef }) {
  const Icon = phase.icon;
  const phaseComplete = phase.steps.every((_, i) => stepStates[`${phase.id}-${i}`]);

  return (
    <section
      ref={sectionRef}
      id={`phase-${phase.id}`}
      style={{ padding: '64px 0 16px', borderTop: index > 0 ? `1px solid ${C.line}` : 'none' }}
    >
      <div
        style={{
          display: 'flex',
          alignItems: 'baseline',
          gap: 18,
          marginBottom: 4,
        }}
      >
        <span
          style={{
            fontFamily: F.display,
            fontStyle: 'italic',
            fontSize: 72,
            color: phaseComplete ? C.done : C.accent,
            lineHeight: 0.9,
            letterSpacing: -1,
            transition: 'color 0.3s ease',
          }}
        >
          {phase.num}
        </span>
        <div style={{ flex: 1 }}>
          <div
            style={{
              fontFamily: F.mono,
              fontSize: 10,
              letterSpacing: 2,
              color: C.textFaint,
              marginBottom: 6,
              display: 'flex',
              alignItems: 'center',
              gap: 8,
            }}
          >
            <Icon size={12} />
            PHASE {parseInt(phase.num)} OF {total}
          </div>
          <h2
            style={{
              fontFamily: F.body,
              fontSize: 26,
              fontWeight: 500,
              color: C.text,
              margin: 0,
              letterSpacing: -0.6,
            }}
          >
            {phase.title}
          </h2>
          <p
            style={{
              fontFamily: F.display,
              fontStyle: 'italic',
              fontSize: 17,
              color: C.textDim,
              margin: '4px 0 0',
            }}
          >
            {phase.subtitle}
          </p>
        </div>
      </div>

      {phase.intro && (
        <p
          style={{
            fontFamily: F.body,
            fontSize: 15,
            lineHeight: 1.7,
            color: C.textDim,
            margin: '24px 0 0',
            maxWidth: 620,
          }}
        >
          {phase.intro}
        </p>
      )}

      <div style={{ marginTop: 8 }}>
        {phase.steps.map((step, i) => {
          const key = `${phase.id}-${i}`;
          return (
            <Step
              key={key}
              num={i + 1}
              title={step.title}
              complete={!!stepStates[key]}
              onToggle={() => toggleStep(key)}
            >
              {step.body}
            </Step>
          );
        })}
      </div>
    </section>
  );
}

const phases = [
  {
    id: 'storage',
    num: '01',
    title: 'Unraid storage',
    subtitle: 'Two shares, cache-only',
    icon: Server,
    intro:
      'You\'ll create one new share for code and worktrees, and use your existing appdata share for container state. Both live on the SSD cache pool so everything is fast.',
    steps: [
      {
        title: 'Create the devbox share',
        body: (
          <>
            In the Unraid web UI, go to <Inline>Shares</Inline> → <Inline>Add Share</Inline>. Set
            the name to <Inline>devbox</Inline>, choose your SSD cache pool, and set{' '}
            <Inline>Use cache: Only</Inline> so it never moves to the array. Leave everything else
            default. Click <Inline>Add Share</Inline>.
          </>
        ),
      },
      {
        title: 'Confirm appdata is cache-only',
        body: (
          <>
            Go to <Inline>Shares</Inline> → click <Inline>appdata</Inline>. Confirm{' '}
            <Inline>Use cache</Inline> is set to <Inline>Only</Inline> and the pool is your SSD. If
            not, switch it now. This makes your container state fast and ensures the Backup Appdata
            plugin captures it.
          </>
        ),
      },
      {
        title: 'Pre-create directories',
        body: (
          <>
            Open the Unraid terminal (the <Inline>{'>_'}</Inline> icon top-right) and create the
            folder structure. Running this now means the container won\'t fail on first start with
            missing-mount errors.
            <Code lang="bash">{`mkdir -p /mnt/user/appdata/devbox/ssh_host_keys
mkdir -p /mnt/user/appdata/devbox/secrets
mkdir -p /mnt/user/appdata/devbox/home
mkdir -p /mnt/user/devbox/workspace`}</Code>
          </>
        ),
      },
    ],
  },
  {
    id: 'repo',
    num: '02',
    title: 'The devbox repo',
    subtitle: 'One git repo, four files',
    icon: GitBranch,
    intro:
      'Everything about the container — its OS, its tools, its boot behavior — lives in a single git repo. Rebuild any time by pushing. Restore any time by re-pulling. This is the deterministic core.',
    steps: [
      {
        title: 'Create a new private GitHub repo',
        body: (
          <>
            Go to github.com → <Inline>New repository</Inline>. Name it <Inline>devbox</Inline>,
            make it <Inline>Private</Inline>, no README. Clone it to your laptop:
            <Code lang="bash">{`git clone git@github.com:ctf05/devbox.git
cd devbox`}</Code>
          </>
        ),
      },
      {
        title: 'Add the Dockerfile',
        body: (
          <>
            Create <Inline>Dockerfile</Inline> in the repo root. This is what the container is made
            of: Ubuntu 26.04, Node 22, pnpm, Playwright with all browser deps, tmux, zsh, Claude
            Code, an SSH server, and a <Inline>dev</Inline> user at UID 1000.
            <Code filename="Dockerfile">{`FROM ubuntu:26.04

ARG NODE_VERSION=22

ENV DEBIAN_FRONTEND=noninteractive \\
    LANG=C.UTF-8 \\
    LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \\
      ca-certificates curl wget gnupg sudo openssh-server \\
      git tmux zsh build-essential locales tzdata jq unzip \\
    && locale-gen en_US.UTF-8 \\
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_\${NODE_VERSION}.x | bash - \\
    && apt-get install -y nodejs \\
    && npm install -g pnpm @anthropic-ai/claude-code \\
    && rm -rf /var/lib/apt/lists/*

RUN npx --yes playwright@latest install --with-deps chromium firefox webkit \\
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 1000 -U -s /bin/zsh dev \\
    && echo "dev ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/dev \\
    && mkdir -p /etc/skel-dev \\
    && cp -a /home/dev/. /etc/skel-dev/

RUN mkdir -p /var/run/sshd \\
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config \\
    && sed -i 's/#PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config \\
    && sed -i 's|HostKey /etc/ssh/|HostKey /etc/ssh/keys/|g' /etc/ssh/sshd_config

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]`}</Code>
          </>
        ),
      },
      {
        title: 'Add the entrypoint script',
        body: (
          <>
            Create <Inline>entrypoint.sh</Inline>. This runs every time the container starts and
            applies your env vars to the live system — host keys, authorized_keys, secrets,
            timezone — then hands off to <Inline>sshd</Inline>.
            <Code filename="entrypoint.sh">{`#!/usr/bin/env bash
set -euo pipefail

# Persistent SSH host keys (survive image rebuilds)
HOST_KEYS=/etc/ssh/keys
mkdir -p "$HOST_KEYS"
if [ ! -f "$HOST_KEYS/ssh_host_ed25519_key" ]; then
  ssh-keygen -t ed25519 -f "$HOST_KEYS/ssh_host_ed25519_key" -N ""
  ssh-keygen -t rsa -b 4096 -f "$HOST_KEYS/ssh_host_rsa_key" -N ""
fi
chmod 600 "$HOST_KEYS"/*_key
chmod 644 "$HOST_KEYS"/*.pub

# Populate /home/dev on first boot from skeleton
if [ ! -f /home/dev/.zshrc ]; then
  cp -an /etc/skel-dev/. /home/dev/ || true
fi

# authorized_keys from env var
mkdir -p /home/dev/.ssh
if [ -n "\${SSH_AUTHORIZED_KEYS:-}" ]; then
  printf '%s\\n' "$SSH_AUTHORIZED_KEYS" > /home/dev/.ssh/authorized_keys
fi
chmod 700 /home/dev/.ssh
[ -f /home/dev/.ssh/authorized_keys ] && chmod 600 /home/dev/.ssh/authorized_keys

# Mounted git SSH key (private)
if [ -f /run/secrets/git_ed25519 ]; then
  install -m 600 -o dev -g dev /run/secrets/git_ed25519 /home/dev/.ssh/id_ed25519
fi

# Timezone
if [ -n "\${TZ:-}" ] && [ -f "/usr/share/zoneinfo/\$TZ" ]; then
  ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime
  echo "$TZ" > /etc/timezone
fi

chown -R dev:dev /home/dev
exec /usr/sbin/sshd -D -e`}</Code>
          </>
        ),
      },
      {
        title: 'Add the GitHub Actions workflow',
        body: (
          <>
            Create <Inline>.github/workflows/build.yml</Inline>. Every push to <Inline>main</Inline>{' '}
            now builds and publishes the image to GHCR.
            <Code filename=".github/workflows/build.yml">{`name: build

on:
  push:
    branches: [main]
    paths:
      - 'Dockerfile'
      - 'entrypoint.sh'
      - '.github/workflows/build.yml'

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: \${{ github.actor }}
          password: \${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          cache-from: type=gha
          cache-to: type=gha,mode=max
          tags: |
            ghcr.io/\${{ github.repository_owner }}/devbox:latest
            ghcr.io/\${{ github.repository_owner }}/devbox:\${{ github.sha }}`}</Code>
          </>
        ),
      },
      {
        title: 'Commit and push',
        body: (
          <>
            <Code lang="bash">{`git add Dockerfile entrypoint.sh .github
git commit -m "initial devbox image"
git push -u origin main`}</Code>
            Watch the build on the GitHub <Inline>Actions</Inline> tab. First build takes 8–12 min
            (Playwright pulls big browser binaries). Subsequent builds use the GHA cache and finish
            in 1–2 min.
          </>
        ),
      },
      {
        title: 'Make the package pullable from Unraid',
        body: (
          <>
            On GitHub, go to your profile → <Inline>Packages</Inline> → <Inline>devbox</Inline> →{' '}
            <Inline>Package settings</Inline>. Either set visibility to <Inline>Public</Inline>{' '}
            (easiest), or keep private and add Unraid as a connected repo with a personal access
            token. Public is fine; the Dockerfile contains no secrets.
          </>
        ),
      },
    ],
  },
  {
    id: 'container',
    num: '03',
    title: 'The Unraid container',
    subtitle: 'Everything in the GUI',
    icon: Container,
    intro:
      'Configure the container entirely through the Unraid Docker tab — no SSH to the host, no Compose files. The image carries the OS; the GUI carries your secrets and mounts.',
    steps: [
      {
        title: 'Add the container',
        body: (
          <>
            Unraid web UI → <Inline>Docker</Inline> tab → <Inline>Add Container</Inline>. Switch to{' '}
            <Inline>Advanced view</Inline> (top-right toggle).
            <br />
            <br />
            Fill in the basics:
            <ul style={{ paddingLeft: 18, marginTop: 8 }}>
              <li>
                <Inline>Name</Inline>: <Inline>devbox</Inline>
              </li>
              <li>
                <Inline>Repository</Inline>: <Inline>ghcr.io/ctf05/devbox:latest</Inline>
              </li>
              <li>
                <Inline>Network Type</Inline>: same custom Docker network your cloudflared
                container is on (so they can reach each other by container name). If unsure, use{' '}
                <Inline>bridge</Inline> for both and we\'ll fix in phase 4.
              </li>
              <li>
                <Inline>Console shell command</Inline>: <Inline>bash</Inline>
              </li>
              <li>
                <Inline>Privileged</Inline>: <Inline>No</Inline>
              </li>
            </ul>
          </>
        ),
      },
      {
        title: 'Add the four volume mounts',
        body: (
          <>
            Click <Inline>Add another Path, Port, Variable…</Inline> → <Inline>Path</Inline>. Add
            these four:
            <table
              style={{
                width: '100%',
                marginTop: 12,
                fontFamily: F.mono,
                fontSize: 12,
                borderCollapse: 'collapse',
              }}
            >
              <thead>
                <tr style={{ color: C.textFaint, borderBottom: `1px solid ${C.line}` }}>
                  <th style={{ textAlign: 'left', padding: '6px 4px', fontWeight: 400 }}>
                    Container Path
                  </th>
                  <th style={{ textAlign: 'left', padding: '6px 4px', fontWeight: 400 }}>
                    Host Path
                  </th>
                  <th style={{ textAlign: 'left', padding: '6px 4px', fontWeight: 400 }}>Access</th>
                </tr>
              </thead>
              <tbody style={{ color: C.text }}>
                {[
                  ['/etc/ssh/keys', '/mnt/user/appdata/devbox/ssh_host_keys', 'RW'],
                  ['/home/dev', '/mnt/user/appdata/devbox/home', 'RW'],
                  ['/run/secrets', '/mnt/user/appdata/devbox/secrets', 'RO'],
                  ['/workspace', '/mnt/user/devbox/workspace', 'RW'],
                ].map(([c, h, a]) => (
                  <tr key={c} style={{ borderBottom: `1px solid ${C.line}` }}>
                    <td style={{ padding: '8px 4px', color: C.accentHi }}>{c}</td>
                    <td style={{ padding: '8px 4px' }}>{h}</td>
                    <td style={{ padding: '8px 4px', color: C.textFaint }}>{a}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </>
        ),
      },
      {
        title: 'Add the environment variables',
        body: (
          <>
            Click <Inline>Add another…</Inline> → <Inline>Variable</Inline>. Add these two.
            <Note kind="info">
              You don\'t have your laptop/phone public keys yet. Add a placeholder for now (e.g.{' '}
              <Inline>changeme</Inline>) and come back to update <Inline>SSH_AUTHORIZED_KEYS</Inline>{' '}
              after phases 5 and 6.
            </Note>
            <table
              style={{
                width: '100%',
                marginTop: 8,
                fontFamily: F.mono,
                fontSize: 12,
                borderCollapse: 'collapse',
              }}
            >
              <tbody style={{ color: C.text }}>
                {[
                  ['SSH_AUTHORIZED_KEYS', 'ssh-ed25519 AAAA... laptop\\nssh-ed25519 AAAA... phone'],
                  ['TZ', 'America/New_York'],
                ].map(([k, v]) => (
                  <tr key={k} style={{ borderBottom: `1px solid ${C.line}` }}>
                    <td style={{ padding: '8px 4px', color: C.accent, whiteSpace: 'nowrap' }}>
                      {k}
                    </td>
                    <td style={{ padding: '8px 4px', color: C.textDim }}>{v}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            <Note kind="info">
              For multi-line values like multiple SSH keys, paste them with literal{' '}
              <Inline>\\n</Inline> between keys — Unraid escapes them and the entrypoint script
              handles the rest.
            </Note>
          </>
        ),
      },
      {
        title: 'Pin CPU cores (optional, recommended)',
        body: (
          <>
            Still in Advanced view, find <Inline>CPU Pinning</Inline>. Pin 8–16 physical cores to
            the devbox container — these are reserved for your test runs so parity checks and other
            containers can\'t fight you for cycles. Leave 2–4 cores unpinned for Unraid services.
          </>
        ),
      },
      {
        title: 'Apply and verify',
        body: (
          <>
            Click <Inline>Apply</Inline>. Unraid pulls the image (1–2 min the first time) and
            starts the container. Click the container icon → <Inline>Logs</Inline>. You should see{' '}
            <Inline>Server listening on 0.0.0.0 port 22</Inline>. If you see errors about missing
            paths, re-check the four mounts from step 2.
          </>
        ),
      },
    ],
  },
  {
    id: 'tunnel',
    num: '04',
    title: 'Cloudflare Tunnel',
    subtitle: 'SSH from anywhere, no open ports',
    icon: Cloud,
    intro:
      'Your existing cloudflared container handles the heavy lifting. You just add an SSH hostname pointed at the devbox container, and a Cloudflare Access policy so only you can connect.',
    steps: [
      {
        title: 'Confirm both containers share a Docker network',
        body: (
          <>
            In the Unraid Docker tab, check the <Inline>Network</Inline> column for both your{' '}
            <Inline>cloudflared</Inline> and <Inline>devbox</Inline> containers. They must match.
            If they don\'t, edit one of them and switch to the same custom network. They\'ll then
            be able to reach each other by container name (<Inline>devbox</Inline>) instead of IP.
          </>
        ),
      },
      {
        title: 'Add the public hostname in Cloudflare',
        body: (
          <>
            Go to <Inline>one.dash.cloudflare.com</Inline> → <Inline>Networks</Inline> →{' '}
            <Inline>Tunnels</Inline> → your existing tunnel → <Inline>Configure</Inline> →{' '}
            <Inline>Public Hostname</Inline> → <Inline>Add a public hostname</Inline>.
            <ul style={{ paddingLeft: 18, marginTop: 8 }}>
              <li>
                <Inline>Subdomain</Inline>: <Inline>dev</Inline>
              </li>
              <li>
                <Inline>Domain</Inline>: ctf-compendium.uk
              </li>
              <li>
                <Inline>Service Type</Inline>: <Inline>SSH</Inline>
              </li>
              <li>
                <Inline>URL</Inline>: <Inline>devbox:22</Inline>
              </li>
            </ul>
            Save.
          </>
        ),
      },
      {
        title: 'Lock it down with Cloudflare Access',
        body: (
          <>
            Same dashboard → <Inline>Access</Inline> → <Inline>Applications</Inline> →{' '}
            <Inline>Add an application</Inline> → <Inline>Self-hosted</Inline>.
            <ul style={{ paddingLeft: 18, marginTop: 8 }}>
              <li>
                <Inline>Application name</Inline>: <Inline>devbox</Inline>
              </li>
              <li>
                <Inline>Session duration</Inline>: 24 hours (or longer)
              </li>
              <li>
                <Inline>Application domain</Inline>: dev.ctf-compendium.uk
              </li>
            </ul>
            Add a policy: <Inline>Allow</Inline> → <Inline>Include: Emails</Inline> → list your
            email(s). Save.
            <Note kind="warn">
              No password — Access auth replaces it. Without a valid Access session, the SSH
              handshake never reaches your container. Don\'t skip this.
            </Note>
          </>
        ),
      },
    ],
  },
  {
    id: 'laptop',
    num: '05',
    title: 'The Pop!_OS laptop',
    subtitle: 'Ghostty, SSH, Mutagen',
    icon: Laptop,
    intro:
      'Install the small handful of clients you need locally, generate your SSH key, configure SSH to route through Cloudflare, and set up continuous file sync.',
    steps: [
      {
        title: 'Install base tooling',
        body: (
          <Code lang="bash">{`sudo apt update
sudo apt install -y openssh-client git curl wget tmux`}</Code>
        ),
      },
      {
        title: 'Install cloudflared',
        body: (
          <Code lang="bash">{`curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o /tmp/cloudflared.deb
sudo dpkg -i /tmp/cloudflared.deb
cloudflared --version`}</Code>
        ),
      },
      {
        title: 'Install Mutagen',
        body: (
          <>
            <Code lang="bash">{`mkdir -p ~/.local/bin
curl -L https://github.com/mutagen-io/mutagen/releases/latest/download/mutagen_linux_amd64_v0.18.3.tar.gz \\
  | tar -xz -C ~/.local/bin mutagen mutagen-agents.tar.gz
chmod +x ~/.local/bin/mutagen
grep -q '.local/bin' ~/.bashrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
mutagen version`}</Code>
            <Note kind="info">
              If 0.18.3 isn\'t the current version, browse{' '}
              <Inline>github.com/mutagen-io/mutagen/releases</Inline> and substitute. Mutagen
              bundles its server-side agent inside the client, so the container needs nothing
              extra.
            </Note>
          </>
        ),
      },
      {
        title: 'Install fnm + Node + pnpm (for local LSP)',
        body: (
          <>
            Your editor\'s LSP needs Node to typecheck. Match the container\'s version.
            <Code lang="bash">{`curl -fsSL https://fnm.vercel.app/install | bash
source ~/.bashrc
fnm install 22
fnm default 22
npm install -g pnpm
node --version  # should print v22.x.x`}</Code>
          </>
        ),
      },
      {
        title: 'Generate your laptop SSH key',
        body: (
          <>
            <Code lang="bash">{`ssh-keygen -t ed25519 -C "popos-laptop" -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub`}</Code>
            Copy the output. You\'ll paste it into <Inline>SSH_AUTHORIZED_KEYS</Inline> in the
            Unraid GUI after phase 6 (combined with the phone key).
          </>
        ),
      },
      {
        title: 'Configure SSH to route through Cloudflare',
        body: (
          <>
            Create or edit <Inline>~/.ssh/config</Inline> and add:
            <Code filename="~/.ssh/config">{`Host dev
    HostName dev.ctf-compendium.uk
    User dev
    ProxyCommand /usr/bin/cloudflared access ssh --hostname %h
    RemoteCommand tmux attach -t main || tmux new -s main
    RequestTTY yes
    ServerAliveInterval 30
    ServerAliveCountMax 3`}</Code>
            One command (<Inline>ssh dev</Inline>) now does everything: Cloudflare Access auth,
            tunneled SSH, auto-attach to your persistent tmux session.
          </>
        ),
      },
      {
        title: 'First connect',
        body: (
          <>
            <Code lang="bash">{`ssh dev`}</Code>A browser opens for Cloudflare Access — sign in
            with the email you whitelisted. The SSH session continues automatically and drops you
            into a tmux session called <Inline>main</Inline>. Verify:
            <Code lang="bash">{`whoami        # dev
node --version
claude --version`}</Code>
            Detach from tmux with <Inline>Ctrl-b d</Inline>, then <Inline>exit</Inline>. Run{' '}
            <Inline>ssh dev</Inline> again and you\'re back where you were.
          </>
        ),
      },
      {
        title: 'Set up Mutagen sync for a project',
        body: (
          <>
            On the server, in your tmux session, create the project dir:
            <Code lang="bash">{`mkdir -p /workspace/HushBox`}</Code>
            Back on your laptop:
            <Code lang="bash">{`mutagen sync create \\
  --name=HushBox \\
  --ignore-vcs \\
  --ignore="node_modules,.next,dist,coverage,.turbo,.vite,playwright-report" \\
  --sync-mode=two-way-resolved \\
  ~/code/HushBox dev:/workspace/HushBox`}</Code>
            Mutagen\'s daemon runs in the background from now on, syncing whether or not you have
            an SSH terminal open. <Inline>mutagen sync list</Inline> shows status anytime.
          </>
        ),
      },
    ],
  },
  {
    id: 'phone',
    num: '06',
    title: 'The Android phone',
    subtitle: 'Termux + tmux + one tap',
    icon: Smartphone,
    intro:
      'Same SSH config, same Cloudflare auth, same tmux session as your laptop. From the phone you\'ll talk to Claude Code or watch a test run while away from your desk.',
    steps: [
      {
        title: 'Install Termux from F-Droid',
        body: (
          <>
            Install F-Droid from <Inline>f-droid.org</Inline> first (the Termux on Google Play is
            outdated and unsupported). Then install <Inline>Termux</Inline> from F-Droid.
          </>
        ),
      },
      {
        title: 'Set up Termux packages',
        body: (
          <Code lang="bash">{`pkg update -y && pkg upgrade -y
pkg install -y openssh cloudflared tmux git`}</Code>
        ),
      },
      {
        title: 'Generate the phone SSH key',
        body: (
          <>
            <Code lang="bash">{`ssh-keygen -t ed25519 -C "android-phone" -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub`}</Code>
            Copy this output. Now go back to the Unraid Docker tab, edit the{' '}
            <Inline>devbox</Inline> container, and update{' '}
            <Inline>SSH_AUTHORIZED_KEYS</Inline> to contain both keys (laptop and phone), separated
            by <Inline>\\n</Inline>. Apply — the container restarts in 5 seconds.
          </>
        ),
      },
      {
        title: 'Configure SSH on Termux',
        body: (
          <>
            <Code lang="bash">{`mkdir -p ~/.ssh && cat > ~/.ssh/config <<'EOF'
Host dev
    HostName dev.ctf-compendium.uk
    User dev
    ProxyCommand cloudflared access ssh --hostname %h
    RemoteCommand tmux attach -t main || tmux new -s main
    RequestTTY yes
    ServerAliveInterval 30
EOF
chmod 600 ~/.ssh/config`}</Code>
          </>
        ),
      },
      {
        title: 'Connect and add a home-screen shortcut',
        body: (
          <>
            <Code lang="bash">{`ssh dev`}</Code>
            Cloudflare Access opens in a browser; sign in once and the session persists. To make
            future connections one-tap, install <Inline>Termux:Widget</Inline> from F-Droid and add
            a script:
            <Code lang="bash">{`mkdir -p ~/.shortcuts
cat > ~/.shortcuts/dev <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
ssh dev
EOF
chmod +x ~/.shortcuts/dev`}</Code>
            Long-press your home screen → <Inline>Widgets</Inline> → <Inline>Termux</Inline> → drop
            the <Inline>dev</Inline> shortcut anywhere. One tap connects you to your live tmux
            session, exactly where your laptop left it.
          </>
        ),
      },
    ],
  },
  {
    id: 'claude',
    num: '07',
    title: 'Claude Code login',
    subtitle: 'One-time, then forever',
    icon: Sparkles,
    intro:
      'Claude Code\'s auth is interactive — the only manual step in the whole setup. Do it once on the server, and the credentials live in /home/dev (which is on appdata and survives every rebuild).',
    steps: [
      {
        title: 'SSH in and start Claude Code',
        body: (
          <>
            <Code lang="bash">{`ssh dev
# now inside tmux on the server:
claude`}</Code>
            Follow the prompts to authenticate (it\'ll open a URL in your laptop browser via
            terminal output). Once done, the session is saved to{' '}
            <Inline>/home/dev/.config</Inline> on the appdata mount.
          </>
        ),
      },
      {
        title: 'Verify persistence',
        body: (
          <>
            Exit Claude, detach tmux (<Inline>Ctrl-b d</Inline>), <Inline>exit</Inline> the SSH
            session entirely. Reconnect with <Inline>ssh dev</Inline>, run <Inline>claude</Inline>{' '}
            again — no re-auth prompt. You\'re permanent.
          </>
        ),
      },
    ],
  },
  {
    id: 'worktrees',
    num: '08',
    title: 'Worktrees & test runs',
    subtitle: 'The actual workflow',
    icon: Terminal,
    intro:
      'How the whole system feels in daily use. Your code lives on the server. Your edits sync continuously. Your terminal sessions persist. Your Claude conversations persist.',
    steps: [
      {
        title: 'Set up a project with worktrees',
        body: (
          <>
            On the server (inside tmux):
            <Code lang="bash">{`cd /workspace
git clone --bare git@github.com:ctf05/HushBox.git HushBox/.bare
cd HushBox
echo "gitdir: ./.bare" > .git
git worktree add main main
git worktree add feat-x -b feat-x main`}</Code>
            Now <Inline>/workspace/HushBox/main</Inline> and{' '}
            <Inline>/workspace/HushBox/feat-x</Inline> are separate working dirs sharing the same
            bare repo.
          </>
        ),
      },
      {
        title: 'Point Mutagen at the parent directory',
        body: (
          <>
            Sync the whole <Inline>HushBox</Inline> directory, not individual worktrees. New
            worktrees you create later will be picked up automatically.
            <Code lang="bash">{`# on your laptop
mutagen sync create \\
  --name=HushBox \\
  --ignore="node_modules,.bare,**/.next,**/dist,**/coverage" \\
  --sync-mode=two-way-resolved \\
  ~/code/HushBox dev:/workspace/HushBox`}</Code>
          </>
        ),
      },
      {
        title: 'Install dependencies and run tests',
        body: (
          <>
            In the server tmux session, cd into a worktree:
            <Code lang="bash">{`cd /workspace/HushBox/main
pnpm install   # populates per-worktree node_modules, server-side only
pnpm test      # vitest, full CPU
pnpm exec playwright test   # all browsers, headless`}</Code>
            Test artifacts in <Inline>playwright-report/</Inline> and trace files sync back to your
            laptop within a second or two of being written.
          </>
        ),
      },
      {
        title: 'Disconnect freely',
        body: (
          <>
            Close your laptop, lose wifi, fly somewhere. The container keeps running, tmux holds
            your session, Claude keeps thinking. When you reconnect — laptop or phone — one{' '}
            <Inline>ssh dev</Inline> drops you back exactly where you were.
            <Note kind="info">
              For long Claude tasks: kick them off in a tmux pane, detach with{' '}
              <Inline>Ctrl-b d</Inline>, close your laptop. Check back in the morning. The work
              happened on the server the whole time.
            </Note>
          </>
        ),
      },
    ],
  },
];

export default function DevboxGuide() {
  const [stepStates, setStepStates] = useState({});
  const [activePhase, setActivePhase] = useState(phases[0].id);
  const sectionRefs = useRef({});

  const toggleStep = (key) =>
    setStepStates((s) => ({ ...s, [key]: !s[key] }));

  const totalSteps = phases.reduce((n, p) => n + p.steps.length, 0);
  const doneSteps = Object.values(stepStates).filter(Boolean).length;
  const progress = totalSteps ? (doneSteps / totalSteps) * 100 : 0;

  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((e) => e.isIntersecting)
          .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
        if (visible) {
          const id = visible.target.id.replace('phase-', '');
          setActivePhase(id);
        }
      },
      { rootMargin: '-30% 0px -50% 0px', threshold: [0, 0.25, 0.5] }
    );
    Object.values(sectionRefs.current).forEach((el) => el && observer.observe(el));
    return () => observer.disconnect();
  }, []);

  const scrollToPhase = (id) => {
    const el = document.getElementById(`phase-${id}`);
    if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
  };

  return (
    <div
      style={{
        background: C.bg,
        color: C.text,
        fontFamily: F.body,
        minHeight: '100vh',
        padding: 0,
        margin: 0,
      }}
    >
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&family=Geist:wght@400;500&family=JetBrains+Mono:wght@400;500&display=swap');
        * { box-sizing: border-box; }
        ::-webkit-scrollbar { width: 8px; height: 8px; }
        ::-webkit-scrollbar-track { background: ${C.bg}; }
        ::-webkit-scrollbar-thumb { background: ${C.line}; border-radius: 4px; }
        ::-webkit-scrollbar-thumb:hover { background: ${C.lineHi}; }
        a { color: ${C.accentHi}; }
      `}</style>

      {/* sticky header */}
      <div
        style={{
          position: 'sticky',
          top: 0,
          zIndex: 10,
          background: `${C.bg}f5`,
          backdropFilter: 'blur(10px)',
          borderBottom: `1px solid ${C.line}`,
        }}
      >
        <div style={{ maxWidth: 760, margin: '0 auto', padding: '14px 28px' }}>
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              gap: 12,
              flexWrap: 'wrap',
            }}
          >
            <div
              style={{
                fontFamily: F.mono,
                fontSize: 11,
                color: C.textFaint,
                letterSpacing: 2,
              }}
            >
              DEVBOX / SETUP GUIDE
            </div>
            <div
              style={{
                fontFamily: F.mono,
                fontSize: 11,
                color: C.textFaint,
                letterSpacing: 1,
              }}
            >
              {doneSteps} / {totalSteps} COMPLETE
            </div>
          </div>
          <div
            style={{
              height: 2,
              background: C.line,
              borderRadius: 1,
              marginTop: 10,
              overflow: 'hidden',
            }}
          >
            <div
              style={{
                width: `${progress}%`,
                height: '100%',
                background: C.accent,
                transition: 'width 0.3s ease',
              }}
            />
          </div>
          <div style={{ display: 'flex', gap: 4, marginTop: 12, overflowX: 'auto' }}>
            {phases.map((p) => {
              const phaseDone = p.steps.every((_, i) => stepStates[`${p.id}-${i}`]);
              const isActive = activePhase === p.id;
              return (
                <button
                  key={p.id}
                  onClick={() => scrollToPhase(p.id)}
                  style={{
                    background: isActive ? C.surfaceHi : 'transparent',
                    border: `1px solid ${isActive ? C.accent : C.line}`,
                    color: phaseDone ? C.done : isActive ? C.accentHi : C.textDim,
                    fontFamily: F.mono,
                    fontSize: 11,
                    padding: '5px 10px',
                    borderRadius: 4,
                    cursor: 'pointer',
                    whiteSpace: 'nowrap',
                    transition: 'all 0.15s ease',
                    display: 'flex',
                    alignItems: 'center',
                    gap: 5,
                  }}
                >
                  {phaseDone && <Check size={11} strokeWidth={3} />}
                  {p.num}
                </button>
              );
            })}
          </div>
        </div>
      </div>

      {/* hero */}
      <div style={{ maxWidth: 760, margin: '0 auto', padding: '64px 28px 0' }}>
        <div
          style={{
            fontFamily: F.mono,
            fontSize: 11,
            letterSpacing: 3,
            color: C.accent,
            marginBottom: 16,
          }}
        >
          A COMPLETE GUIDE
        </div>
        <h1
          style={{
            fontFamily: F.display,
            fontSize: 64,
            fontWeight: 400,
            lineHeight: 1.05,
            margin: 0,
            letterSpacing: -1.5,
            color: C.text,
          }}
        >
          A remote{' '}
          <span style={{ fontStyle: 'italic', color: C.accent }}>dev machine</span>
          <br />
          on your Unraid box.
        </h1>
        <p
          style={{
            fontSize: 17,
            lineHeight: 1.65,
            color: C.textDim,
            margin: '28px 0 0',
            maxWidth: 580,
          }}
        >
          Eight phases, each with a few clear steps. Tick them off as you go. By the end you\'ll be
          editing locally in Ghostty, running tests on a real CPU, talking to Claude Code from your
          phone, and disconnecting without losing a thing.
        </p>

        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))',
            gap: 12,
            marginTop: 40,
          }}
        >
          {[
            { label: 'Container OS', value: 'Ubuntu 26.04' },
            { label: 'User', value: 'dev (UID 1000)' },
            { label: 'Image registry', value: 'GHCR' },
            { label: 'Access', value: 'Cloudflare Tunnel' },
            { label: 'Sync', value: 'Mutagen + git' },
            { label: 'Multiplexer', value: 'tmux' },
          ].map((s) => (
            <div
              key={s.label}
              style={{
                background: C.surface,
                border: `1px solid ${C.line}`,
                borderRadius: 6,
                padding: '12px 14px',
              }}
            >
              <div
                style={{
                  fontFamily: F.mono,
                  fontSize: 10,
                  letterSpacing: 1.5,
                  color: C.textFaint,
                  marginBottom: 6,
                }}
              >
                {s.label.toUpperCase()}
              </div>
              <div
                style={{
                  fontFamily: F.body,
                  fontSize: 14,
                  fontWeight: 500,
                  color: C.text,
                }}
              >
                {s.value}
              </div>
            </div>
          ))}
        </div>

        <Note kind="warn">
          This guide is pre-filled for <Inline>ctf05</Inline> / <Inline>ctf-compendium.uk</Inline>{' '}
          / <Inline>HushBox</Inline>. The only value left for you to supply is your SSH public keys
          (generated in phases 5 and 6) — paste them into{' '}
          <Inline>SSH_AUTHORIZED_KEYS</Inline> in the Unraid GUI when ready.
        </Note>
      </div>

      {/* phases */}
      <div style={{ maxWidth: 760, margin: '0 auto', padding: '0 28px' }}>
        {phases.map((phase, i) => (
          <Phase
            key={phase.id}
            phase={phase}
            index={i}
            total={phases.length}
            stepStates={stepStates}
            toggleStep={toggleStep}
            sectionRef={(el) => (sectionRefs.current[phase.id] = el)}
          />
        ))}
      </div>

      {/* footer */}
      <div
        style={{
          maxWidth: 760,
          margin: '0 auto',
          padding: '80px 28px 120px',
          borderTop: `1px solid ${C.line}`,
          marginTop: 64,
        }}
      >
        <div
          style={{
            fontFamily: F.display,
            fontStyle: 'italic',
            fontSize: 48,
            color: progress === 100 ? C.done : C.textDim,
            lineHeight: 1.1,
            letterSpacing: -0.5,
            transition: 'color 0.5s ease',
          }}
        >
          {progress === 100 ? 'You\'re home.' : 'Almost there.'}
        </div>
        <p
          style={{
            fontFamily: F.body,
            fontSize: 15,
            lineHeight: 1.7,
            color: C.textDim,
            marginTop: 16,
            maxWidth: 520,
          }}
        >
          {progress === 100
            ? 'Open Ghostty, type ssh dev, and your machine is waiting. Pull out your phone — same session. Close the lid, walk away — work keeps running.'
            : 'Every step is reversible. If anything looks off, walk it back and try again — the whole system is just a git push away from a clean rebuild.'}
        </p>
      </div>
    </div>
  );
}
