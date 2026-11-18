# Rex devbox integration

Rex actions that create a [Namespace](https://namespace.so) devbox from a blueprint and connect
it to your local Rex client over Tailscale. Each devbox runs Rex's built-in Tailscale node, which
belongs to the person who signs in, so only that person can use it.

## Install

Copy or link the Lua files into your Rex config directory, then reload:

```sh
ln -s "$PWD/init.lua" "$PWD/devbox.lua" ~/.config/rex/
rex config reload
```

If you already have an `init.lua`, copy the contents of this one into it and keep `devbox.lua`
beside it.

## Use

Actions in `init.lua` (logic in `devbox.lua`):

| Command | Effect |
|---|---|
| `rex do devbox_up [name=NAME] [blueprint=rex] [open=false]` | Create a devbox from the blueprint (or reuse `NAME`), register it as a Rex host, open the Tailscale sign-in link in your browser the first time, wait until it answers, and make sure the devbox has a session named `NAME` with one shell. `open=false` skips the session. |
| `rex do devbox_down name=NAME [stop=false]` | Remove the Rex host and stop the devbox. |

Both open a tab that shows progress. Connect with `rex -S NAME ...`. Run `rex config reload`
after you edit `init.lua` or `devbox.lua`.

Connect with `rex -S NAME`, where `NAME` is the devbox name. The session `NAME` lives on the
devbox's Rex server. A script cannot select it in the Rex app, because the app's client is not
attached to the remote server; switch to the host in the app (**Switch Host**) to see it. The Rex node's tailnet name is
`rex-NAME.<tailnet>.ts.net`.

## How the devbox connects

The blueprint installs Rex and runs its server with `--tailscale`, so the server joins the
tailnet as its own device. The first time, Tailscale needs a sign-in. The script reads the link
from the devbox, checks that it is a `https://login.tailscale.com/` URL, and opens it with
`open`. The node belongs to whoever signs in, and Rex admits only its owner by default. The node
keeps its identity on the devbox volume, so a later start needs no sign-in.

This replaces sharing the server with `tailscale serve`. The devbox's own tailnet node comes from
Namespace's Tailscale integration and is tagged. A tagged node has no owner, and Rex cannot
identify callers through Serve for it. Rex's own node needs no tailnet policy change, because
your own devices can already reach each other.

The devbox has no running systemd (its init is `tini`), so `rex server install` does not apply.
The blueprint uses an init script and a service instead.

## Blueprint `rex`

The `devbox` CLI cannot create blueprints. Create it in the Namespace dashboard
(Devboxes → Blueprints → **New Blueprint**), or with the TypeScript SDK (`blueprints.create`).
The init script and services can only be set in the dashboard.

| Setting | Value |
|---|---|
| Name | `rex` |
| OS and image | Linux, `builtin:default` |
| Size | `m` |
| Access | private |
| Ephemeral | off (the Rex node keeps its identity on the volume) |

**Init script.** It runs once, when a devbox is first initialized. It installs Rex from the
Rex package repository. Choose the channel that matches your local client, because the client
and server API revisions can differ between channels.

```sh
set -eu
if [ "$(id -u)" = 0 ]; then sudo=""; else sudo="sudo -n"; fi
curl -fsSL https://pkgs.superlogical.com/rex/install.sh | $sudo sh -s -- --channel preview
```

**Service.** Blueprint services start on every boot and restart when they fail. Do not rely on
the init script having finished (see below).

| Field | Value |
|---|---|
| Name | `rex-server` |
| Command line | `sh -c 'until command -v rex >/dev/null 2>&1; do sleep 1; done; exec rex server run --tailscale --tailscale-hostname "rex-$(hostname)"'` |
| Start | `on-boot` |
| Restart | `always` |

The service waits for `rex` because Namespace starts blueprint services while the init script is
still running. On a test devbox, the service started within a second of the package install
finishing. The loop makes the order safe: `dpkg` moves a finished binary into place in one step, so
once `rex` is found it is complete.

The dashboard takes the service as one command line, not a command and a list of arguments. The
service runs it without a shell, so the `sh -c` is what runs `hostname` and replaces itself with
`rex` (`exec`). Check that the dashboard keeps the single quotes together.

`rex server run` runs in the foreground. `$(hostname)` is the devbox name, and the `rex-` prefix
keeps the Rex node apart from Namespace's own node, which uses the bare devbox name. The Rex node
needs MagicDNS and HTTPS certificates enabled on the tailnet.

A later edit to the blueprint does not change devboxes that already exist.

## Prerequisites

- `devbox` CLI, logged in (`devbox login`).
- MagicDNS and HTTPS certificates enabled on the tailnet.
- Your devices can reach each other on the tailnet (the default for a user's own devices).

## Known limits

- An idle devbox stops, and its Rex node goes offline with it. `rex -S NAME` does not wake it. Run
  `rex do devbox_up name=NAME` (it wakes an existing devbox), or set an auto-stop timeout that
  suits you on the blueprint.
- A config-file action stops after 30 seconds, so the actions only open a tab that runs
  `devbox.lua`.
- `devbox_up` runs two commands inside the devbox: `devbox exec NAME -- true` to wake an
  existing one (the CLI has no start command), and a read-only `rex server status --json` to
  find the sign-in link.
- The `rex` binary is found through `REX_BIN` in `init.lua`. Update it if Rex changes where it
  installs.
