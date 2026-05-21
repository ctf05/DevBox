#!/usr/bin/env bash
# Download release binaries for the CLI ecosystem in parallel.
# Versions pinned so the resulting Docker layer is cache-stable.
set -euo pipefail

ARCH="$(uname -m)"          # x86_64
KERN="$(uname -s | tr A-Z a-z)"   # linux

# ── Versions (bump as needed) ──────────────────────────────────────
EZA_VER=0.20.13
STARSHIP_VER=1.21.1
LAZYGIT_VER=0.46.0
ATUIN_VER=18.5.0
ZOXIDE_VER=0.9.6
DIFFTASTIC_VER=0.62.0
DUST_VER=1.1.2
SD_VER=1.0.0
TOKEI_VER=12.1.2
YAZI_VER=0.4.2
TLRC_VER=1.11.0
DELTA_VER=0.18.2
NVIM_VER=0.11.0
GH_VER=2.63.2

DL=/tmp/dl
BIN=/usr/local/bin
mkdir -p "$DL" "$BIN"

# Helper: download to $DL/$1 from $2; prints which URL failed (silent
# curl in parallel hides the offender otherwise).
fetch() {
  local out="$DL/$1"
  local url="$2"
  if [[ -s "$out" ]]; then return 0; fi
  if ! curl -fsSL --retry 3 --retry-delay 2 "$url" -o "$out"; then
    echo "✗ FAILED: $1 ($url)" >&2
    return 1
  fi
}

echo "→ Downloading binaries in parallel"
pids=()

# Each fetch in background; collect PIDs to wait on.
fetch eza.tgz         "https://github.com/eza-community/eza/releases/download/v${EZA_VER}/eza_${ARCH}-unknown-linux-gnu.tar.gz" & pids+=($!)
fetch starship.tgz    "https://github.com/starship/starship/releases/download/v${STARSHIP_VER}/starship-${ARCH}-unknown-linux-gnu.tar.gz" & pids+=($!)
fetch lazygit.tgz     "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VER}/lazygit_${LAZYGIT_VER}_Linux_x86_64.tar.gz" & pids+=($!)
fetch atuin.tgz       "https://github.com/atuinsh/atuin/releases/download/v${ATUIN_VER}/atuin-${ARCH}-unknown-linux-gnu.tar.gz" & pids+=($!)
fetch zoxide.tgz      "https://github.com/ajeetdsouza/zoxide/releases/download/v${ZOXIDE_VER}/zoxide-${ZOXIDE_VER}-${ARCH}-unknown-linux-musl.tar.gz" & pids+=($!)
fetch difftastic.tgz  "https://github.com/Wilfred/difftastic/releases/download/${DIFFTASTIC_VER}/difft-${ARCH}-unknown-linux-gnu.tar.gz" & pids+=($!)
fetch dust.tgz        "https://github.com/bootandy/dust/releases/download/v${DUST_VER}/dust-v${DUST_VER}-${ARCH}-unknown-linux-gnu.tar.gz" & pids+=($!)
fetch sd.tgz          "https://github.com/chmln/sd/releases/download/v${SD_VER}/sd-v${SD_VER}-${ARCH}-unknown-linux-gnu.tar.gz" & pids+=($!)
fetch tokei.tgz       "https://github.com/XAMPPRocky/tokei/releases/download/v${TOKEI_VER}/tokei-${ARCH}-unknown-linux-gnu.tar.gz" & pids+=($!)
fetch yazi.zip        "https://github.com/sxyazi/yazi/releases/download/v${YAZI_VER}/yazi-${ARCH}-unknown-linux-gnu.zip" & pids+=($!)
fetch tlrc.tgz        "https://github.com/tldr-pages/tlrc/releases/download/v${TLRC_VER}/tlrc-v${TLRC_VER}-${ARCH}-unknown-linux-musl.tar.gz" & pids+=($!)
fetch delta.tgz       "https://github.com/dandavison/delta/releases/download/${DELTA_VER}/delta-${DELTA_VER}-${ARCH}-unknown-linux-gnu.tar.gz" & pids+=($!)
fetch nvim.tgz        "https://github.com/neovim/neovim/releases/download/v${NVIM_VER}/nvim-linux-x86_64.tar.gz" & pids+=($!)
fetch gh.tgz          "https://github.com/cli/cli/releases/download/v${GH_VER}/gh_${GH_VER}_linux_amd64.tar.gz" & pids+=($!)

# Wait for all parallel downloads.
for p in "${pids[@]}"; do
  wait "$p"
done
echo "→ Downloads complete"

# ── Extract / install ──────────────────────────────────────────────
echo "→ Installing binaries to ${BIN}"
cd "$DL"

# eza: archive contains ./eza
tar -xzf eza.tgz       && install -m755 eza                    "$BIN/eza"

# starship: archive contains ./starship
tar -xzf starship.tgz  && install -m755 starship               "$BIN/starship"

# lazygit: archive contains ./lazygit
mkdir -p lazygit && tar -xzf lazygit.tgz -C lazygit && install -m755 lazygit/lazygit "$BIN/lazygit"

# atuin: archive root: atuin-${ARCH}-unknown-linux-gnu/atuin
tar -xzf atuin.tgz && install -m755 atuin-*/atuin              "$BIN/atuin"

# zoxide: archive root contains zoxide binary directly
mkdir -p zoxide && tar -xzf zoxide.tgz -C zoxide && install -m755 zoxide/zoxide "$BIN/zoxide"

# difftastic: archive root: difft binary
mkdir -p difft && tar -xzf difftastic.tgz -C difft && install -m755 difft/difft "$BIN/difft"

# dust: dust-v${VER}-${ARCH}-unknown-linux-gnu/dust
tar -xzf dust.tgz && install -m755 dust-*/dust                 "$BIN/dust"

# sd: archive contains sd binary at root
mkdir -p sd && tar -xzf sd.tgz -C sd && install -m755 sd/sd-*/sd "$BIN/sd"

# tokei: archive root: tokei binary
mkdir -p tokei && tar -xzf tokei.tgz -C tokei && install -m755 tokei/tokei "$BIN/tokei"

# yazi: archive root: yazi-${ARCH}-unknown-linux-gnu/{yazi,ya}
unzip -q yazi.zip && install -m755 yazi-*/yazi                 "$BIN/yazi"
install -m755 yazi-*/ya "$BIN/ya"

# tlrc: archive root: tldr binary
mkdir -p tlrc && tar -xzf tlrc.tgz -C tlrc && install -m755 tlrc/tldr "$BIN/tldr"

# delta: archive root: delta-${VER}-${ARCH}-unknown-linux-gnu/delta
tar -xzf delta.tgz && install -m755 delta-*/delta              "$BIN/delta"

# neovim: archive root: nvim-linux-x86_64/{bin,share,lib}
tar -xzf nvim.tgz -C /opt
ln -sfn /opt/nvim-linux-x86_64/bin/nvim                        "$BIN/nvim"

# gh: archive root: gh_${VER}_linux_amd64/{bin,share}
tar -xzf gh.tgz && install -m755 gh_*/bin/gh                   "$BIN/gh"

# ── terminfo (vendored from Ghostty 1.2.3; Tc + Su capabilities) ───
# The file is COPY'd into the image by the Dockerfile to /tmp/ghostty.terminfo.
tic -x -o /usr/share/terminfo /tmp/ghostty.terminfo

# ── Symlinks for apt-named binaries ────────────────────────────────
# Ubuntu names: fd-find -> fdfind, bat -> batcat (avoid namespace clashes)
[[ -x /usr/bin/fdfind  ]] && ln -sfn /usr/bin/fdfind  "$BIN/fd"
[[ -x /usr/bin/batcat  ]] && ln -sfn /usr/bin/batcat  "$BIN/bat"

# ── mise (via official installer; small + handles latest) ─────────
curl -fsSL https://mise.run | MISE_INSTALL_PATH="$BIN/mise" sh

# ── uv (Python package manager) ────────────────────────────────────
curl -fsSL https://astral.sh/uv/install.sh | UV_INSTALL_DIR="$BIN" sh

# ── Cleanup ────────────────────────────────────────────────────────
cd /
rm -rf "$DL"

echo "→ Tool install complete"
