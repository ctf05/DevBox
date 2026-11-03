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

Then **Settings → General → Workspace Directory**: set it to
`/home/popper-mobile/.superset/worktrees` (spelled out; `~` here is
`/home/dev`, which Mutagen doesn't sync). Orca's default,
`/home/dev/orca/workspaces`, would put every new worktree outside Mutagen, so it
would never reach the laptop. Leave **Nest Workspaces** on; new worktrees land
at `…/worktrees/<repo>/<name>`.

This has to be set here, on the box. A laptop connected to the box can't change
it: a server's workspace folder isn't one of the settings remote clients may
write, and the laptop's per-host "Apply to" override is ignored by the server.

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

It's fine to run this while the laptop still uses the box as an SSH host
(step 6); until that's switched over, create new worktrees only through the
box's Orca, so its workspace folder is the one used.

### 6. Laptop: use the box's Orca, not a second one

Only one Orca should run on this box. If the laptop's Orca has this box as an
**SSH host**, it runs its own Orca here (`~/.orca-remote/orcad`), with its own
terminals and session list. The phone can't see that one; it only sees the
box's Orca. `orca-relay status` warns while both are up.

To switch:

1. In the box's Orca (over VNC): **Settings → Remote Orca Servers → Share this
   computer → This computer → Create link**. "This computer" makes a link that
   dials `127.0.0.1`, which is right: through the SSH tunnel below, the laptop's
   127.0.0.1 *is* the box. Copy the **Access link** (`orca://pair?code=…`;
   anyone holding it can run commands as you, so treat it like a password).
   Revoke links under **Active links** in the same dialog.
2. On the box, `orca-relay status` prints the runtime port (6770 on this box,
   because the laptop's SSH-mode orcad held 6768 when Orca first started; Orca
   keeps the port it got). On the laptop, keep a tunnel to that port open, with
   the same number on both sides, since the link names it. The dotfiles repo
   does this as a user service, `devbox-orca-tunnel` (`hosts/popos.nix`),
   which reconnects on its own after sleep or network changes. Check it with
   `systemctl --user status devbox-orca-tunnel`. By hand, the same thing is:

   ```bash
   ssh -N -L 6770:127.0.0.1:6770 dev
   ```

   When the Cloudflare Access login lapses, the service can't renew it (that
   needs a browser). The laptop shows the server disconnected until any
   interactive `ssh dev` signs in again; the service then reconnects within
   30 seconds.

3. In the laptop's Orca: **Settings → Remote Orca Servers → Add server**, give
   it a name (e.g. `DevBox Orca`), paste the access link, and connect.
4. Once the laptop shows the box's projects, move what's still running in the
   old SSH-mode sessions (`/exit`, then `claude --resume` in a box-Orca
   terminal), and remove this box under **Settings → SSH** on the laptop. Do
   this last: it ends every terminal the laptop's SSH mode started here.

---

## Sessions started before the switch

A terminal belongs to the Orca that started it. Sessions the laptop's Orca
started here (SSH mode) never show up in the box's Orca or on the phone, even
though they run on the same machine. Only sessions started inside the box's
Orca do. To move a conversation: exit it, then in a box-Orca terminal in the
same worktree run `claude --resume` and pick it.

## Mutagen

Mutagen keeps syncing `~/.superset` as before; worktrees Orca creates on the
box land in `~/.superset/worktrees` and reach the laptop like the ones
`new-worktree` makes. One rule keeps it safe: **only the box runs git on these
repos.** Create worktrees through the box's Orca (or `new-worktree` on the box),
not from projects the laptop's own Orca has open locally. Two machines writing
the same `.git` at once is the one thing Mutagen can't merge.

The laptop's `devbox-autosync` timer (dotfiles) makes one sync per folder under
`~/.superset/worktrees/`, including folders that only exist on the devbox, so a
worktree Orca makes for a repo the laptop has no worktrees folder for still
comes back within about 2 minutes. Orca's scratch folder
(`worktrees/.orca-preparing`) sits outside every per-repo sync and is skipped.

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
