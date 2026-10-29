# Unraid host memory guard — stops memory exhaustion from stalling the host.
#
# HOW TO USE: copy this entire file and paste it into the Unraid web terminal
# (the >_ icon, top right). It takes effect immediately, with no reboot, and is
# re-applied on every boot from then on. Pasting it again is safe: it rewrites
# the script and never adds the boot hook twice.
#
# What it does
# ------------
# Without swap that can relieve real pressure (zram compresses pages into RAM,
# so it is still RAM), the kernel keeps reclaiming page cache, the pages it
# drops are needed again at once, and every process stalls on page faults. That
# counts as "progress", so the kernel's OOM killer never runs and the box
# thrashes indefinitely. The settings below turn that stall into a fast kill:
#
#   lru_gen/enabled = y        multi-generational LRU — better choice of which
#                              pages to evict under pressure
#   lru_gen/min_ttl_ms = 1000  if the last 1s of working set cannot stay in
#                              RAM, invoke the OOM killer instead of thrashing
#                              (kernel docs: "an adjustable pressure relief valve")
#   vm.min_free_kbytes = 512 MiB       reserve for the kernel (was ~66 MiB)
#   vm.watermark_scale_factor = 100    background reclaim starts at ~1% free
#                                      instead of 0.1%, so allocations stall
#                                      in direct reclaim less often
#
# None of these cap memory: every process can still use all of RAM. The
# devbox container decides WHICH process the OOM killer picks (its own tool
# commands first) — see entrypoint.sh and config/zshenv.
#
# Pasted-terminal safety: no tabs (they trigger completion), no exclamation
# marks (history expansion), no `exit` or `set -e` (either would close the
# terminal). /boot is FAT, so nothing on it is executable — it is run via bash.

cat > /boot/config/devbox-memory-guard.sh <<'GUARD'
# Installed by host/unraid-memory-guard.sh from the devbox repo. Runs at boot
# from /boot/config/go as `bash <this file>` (no shebang: /boot is FAT, so it
# can't be executable anyway). Edit the repo copy, not this one, and re-paste.
set_knob() {
  if echo "$2" > "$1" 2>/dev/null; then
    echo "devbox-memory-guard: $1 = $(cat "$1")"
  else
    echo "devbox-memory-guard: FAILED to set $1 to $2" >&2
  fi
}
set_knob /sys/kernel/mm/lru_gen/enabled y
set_knob /sys/kernel/mm/lru_gen/min_ttl_ms 1000
set_knob /proc/sys/vm/min_free_kbytes 524288
set_knob /proc/sys/vm/watermark_scale_factor 100
GUARD

# Hook it into /boot/config/go, once, directly after the shebang so an `exit`
# or a blocking command later in go can never skip it. Output goes to syslog.
[ -s /boot/config/go ] || printf '#\041/bin/bash\n' > /boot/config/go
if grep -qF 'devbox-memory-guard.sh' /boot/config/go; then
  echo "boot hook: already present in /boot/config/go"
elif head -n 1 /boot/config/go | grep -q '^#.'; then
  sed -i '1a bash /boot/config/devbox-memory-guard.sh 2>&1 | logger -t devbox-memory-guard' /boot/config/go
  echo "boot hook: added to /boot/config/go"
else
  sed -i '1i bash /boot/config/devbox-memory-guard.sh 2>&1 | logger -t devbox-memory-guard' /boot/config/go
  echo "boot hook: added to /boot/config/go"
fi

# Apply now, so no reboot is needed.
bash /boot/config/devbox-memory-guard.sh

# Show the result. Expect: 0x0007, 1000, 524288, 100.
echo "--- live values ---"
cat /sys/kernel/mm/lru_gen/enabled /sys/kernel/mm/lru_gen/min_ttl_ms /proc/sys/vm/min_free_kbytes /proc/sys/vm/watermark_scale_factor
echo "--- /boot/config/go ---"
cat /boot/config/go
