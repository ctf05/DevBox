# Orca Relay on the devbox

The devbox runs the Orca desktop app headless, so the Orca Mobile app can reach
the agents on this box through Orca Relay: outbound-only, no open ports, works
with the laptop closed. `entrypoint.sh` starts it at boot. `orca-relay.sh`
(installed as `orca-relay`) has the details and the reasons behind them. tmux
is untouched; this runs alongside it.

What lives where:

| Thing | Where | Survives a rebuild? |
|---|---|---|
| Orca app, keyring, VNC server | the image (`Dockerfile`) | rebuilt from `ORCA_VERSION` |
| Orca settings, projects, paired phones | `/home/dev/.config/orca` | yes |
| Orca account login (sealed) | `/home/dev/.local/share/keyrings` + `/home/dev/.local/share/devbox-orca/keyring-password` | yes, keep them together |
| Log | `/var/log/orca.log` | no |

Everyday commands, run on the box as `dev`:

```bash
orca-relay status         # running? which port? last sign-in link
orca-relay add-projects   # register ~/.superset/projects/* with Orca
tail -f /var/log/orca.log
```

---

## First-time setup (or redoing it)

Do these after a fresh container, or any time the phone loses the box.

### 1. Look at Orca's screen from the laptop

Orca draws on a virtual screen (`:77`) that only VNC shows. On the laptop:

```bash
sudo apt install remmina remmina-plugin-vnc   # once; or tigervnc-viewer
ssh -L 5900:127.0.0.1:5900 dev orca-relay vnc
```

`dev` is the SSH host from `~/.ssh/config`. Keep that terminal open. The VNC
server stops when it closes.

Open Remmina, switch the protocol dropdown to **VNC**, connect to
`localhost:5900`, leave the password empty. If 5900 is taken on the laptop, use
`-L 5901:127.0.0.1:5900` and connect to `localhost:5901`.

(With TigerVNC instead: `vncviewer localhost:5900`.)

### 2. First-run screens

Pick the default agent (Claude). **Yolo mode is on by default**; turn it off if
agents should ask before running commands. Finish or skip the rest.

### 3. Sign in for Relay

**Orca Mobile** (sidebar) → **Get started** → **Continue** → select
**Orca Relay** → **Sign in for Relay**.

A browser window opens on the same screen with Orca's login page. Use GitHub or
email; Google may refuse this browser ("Chrome for Testing"). When the page says
**Signed in to Orca**, you're done. The window closes by itself a few seconds
later.

If the login page never appears or won't work in that window:

1. On the box: `orca-relay status` prints the sign-in link.
2. Open it in the laptop's browser and sign in. The final redirect goes to
   `http://127.0.0.1:<port>/auth/callback?...` and fails to load. That's
   expected, since it means the box, not the laptop.
3. Copy that whole URL from the address bar and, on the box, run
   `orca-relay callback '<that URL>'`.

Orca waits 5 minutes for a sign-in; after that, click **Sign in for Relay**
again.

### 4. Pair the phone

Still on **Orca Mobile → Pair this computer** with **Orca Relay** selected:
in the phone app tap **Pair Desktop** and scan the QR code from the VNC window.
The phone must be signed in to the **same Orca account**.

### 5. Add the projects

Orca's sidebar (and the phone) only shows repos registered with this box's Orca.
On the box:

```bash
orca-relay add-projects
```

It registers every git repo in `/home/*/.superset/projects/` and tells Orca to
show their existing worktrees (Orca hides worktrees it didn't create itself
until told otherwise). Run it again any time; it's safe to repeat. To add one
repo: `orca-relay add-projects /path/to/repo`.

Do step 6 first if the laptop is still using this box as an SSH host.

### 6. Laptop: use the box's Orca, not a second one

Only one Orca should run on this box. If the laptop's Orca has this box as an
**SSH host**, it runs its own Orca here (`~/.orca-remote/orcad`), with its own
terminals and session list. The phone can't see that one; it only sees the
box's Orca. `orca-relay status` warns while both are up.

To switch:

1. In the laptop's Orca, let the sessions on this box finish (or `/exit` them;
   a Claude conversation can be picked up again later with `claude --resume`).
   Then remove this box under **Settings → SSH**.
2. In the box's Orca (over VNC): **Settings → Remote Orca Servers → Advertise
   this app as a server → New Link**. Choose `127.0.0.1` as the connection
   address. The laptop reaches it through an SSH tunnel, so from the laptop's
   side the server *is* on 127.0.0.1. Then **Generate Access Link** and copy it.
3. On the box, `orca-relay status` prints the runtime port (6768, or a little
   higher if that was taken when Orca first started). On the laptop, keep a
   tunnel to it open:

   ```bash
   ssh -N -L <port>:127.0.0.1:<port> dev
   ```

4. In the laptop's Orca: **Settings → Remote Orca Servers → Add Server**, paste
   the link, and connect.

Step 6 is untested on this box so far. Orca's own docs list SSH forwarding as a
supported route.

---

## Sessions started before the switch

A terminal belongs to the Orca that started it. Sessions the laptop's Orca
started here (SSH mode) never show up in the box's Orca or on the phone, even
though they run on the same machine. Only sessions started inside the box's
Orca do. To move a conversation: exit it, then in a box-Orca terminal in the
same worktree run `claude --resume` and pick it.

## Updating Orca

The image pins Orca (`ARG ORCA_VERSION` in `Dockerfile`), and the `.deb` never
updates itself. Set it to a tag from <https://github.com/stablyai/orca/releases>,
push, and update the container. Don't let it lag far behind: Orca Mobile refuses
a host whose protocol is too old. Settings, login, and pairing carry over.

## Turning it off

Set the container variable `ORCA_ENABLED=0` and restart. The phone can't reach
the box while it's off.

## Cost

About 580 MB of RAM always on (Orca ~525 MB, the virtual screen ~50 MB) and
~0% CPU at rest. x11vnc (~20 MB) only runs while you're connected. The sign-in
browser (~350 MB) only exists during a sign-in.

## Troubleshooting

- **Phone says it can't reach the box.** `orca-relay status`: is Orca running?
  Look at `grep '\[relay\]' /var/log/orca.log`. If Orca was signed out (for
  example the keyring files were lost), redo steps 1, 3 and 4.
- **Signed out after every restart.** The keyring didn't open. The log says so
  (`login keyring would not unlock`), and orca-relay sets the old keyring aside
  and starts fresh; sign in once more. Keep `keyrings/` and
  `devbox-orca/keyring-password` together if you ever back up or restore
  `/home/dev`.
- **VNC shows a black screen.** Orca is restarting; check `/var/log/orca.log`.
  The entrypoint restarts it within 10 seconds.
- **Orca window doesn't fill the VNC view.** Disconnect and run
  `orca-relay vnc` again; it resizes the window on start.
- **Orca crashed and keeps restarting.** `tail -50 /var/log/orca.log`.
