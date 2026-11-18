# Rex devbox integration

Your Namespace devboxes appear as Rex hosts on their own. Create a devbox from the `rex`
blueprint (dashboard or `devbox create --blueprint rex`) and, within about 30 seconds, connect
with `rex -S NAME`. Rex reaches the devbox over SSH, through Namespace's SSH proxy. No Tailscale
node, tailnet grant, or sign-in link is involved.

## Install

```sh
cp init.lua devbox-sync.lua ~/.config/rex/
rex config reload
```

If you already have an `init.lua`, merge this one into it and keep `devbox-sync.lua` beside it.

## How it works

- `init.lua` declares a Rex host for each line of `~/.cache/rex-devbox/hosts` and starts
  `devbox-sync.lua` in the background.
- `devbox-sync.lua` runs `devbox list -o json` every 30 seconds. It keeps the devboxes whose init
  script installs Rex, runs `devbox configure-ssh NAME` for new ones, and rewrites the cache. When
  the list changes, it runs `rex config reload`, which makes the hosts appear.
- Each host is `ssh://devbox@NAME.devbox.namespace`. Rex runs your system `ssh`, which uses the
  Namespace proxy that `devbox configure-ssh` sets up in `~/.namespace/ssh/`.
- Over SSH, Rex finds the devbox's Rex server, or starts one if none runs.

Only one sync runs at a time. A reload starts a new copy and the old copy stops.

## Use

```sh
rex hosts                 # lists the devboxes
rex -S NAME ls            # sessions on the devbox
rex -S NAME run ...       # run a command there
```

The hosts come from `init.lua`, so they are not stored in `rex hosts` and they are not in the
Mac app's **Remote Hosts** list unless the app reads config hosts (not verified). The Rex docs
say `rex hosts` does not sync to the app.

## Blueprint `rex`

The `devbox` CLI cannot create blueprints. Create it in the Namespace dashboard
(Devboxes → Blueprints → **New Blueprint**).

| Setting | Value |
|---|---|
| Name | `rex` |
| OS and image | Linux, `builtin:default` |
| Size | `m` |

**Init script.** Choose the channel that matches your local client, because client and server API
revisions can differ between channels. The sync finds blueprint devboxes by the install URL, so
keep `pkgs.superlogical.com/rex` in the script.

```sh
set -eu
if [ "$(id -u)" = 0 ]; then sudo=""; else sudo="sudo -n"; fi
curl -fsSL https://pkgs.superlogical.com/rex/install.sh | $sudo sh -s -- --channel preview
```

No service is needed. Rex starts its server over SSH when none runs. If you keep a service, use
`sh -c 'until command -v rex >/dev/null 2>&1; do sleep 1; done; exec rex server run'`; the wait
loop is there because Namespace starts services while the init script is still running.

## Prerequisites

- `devbox` CLI, logged in (`devbox login`).
- `devbox configure-ssh` run once on your machine, so `~/.ssh/config` includes
  `~/.namespace/ssh/*.ssh`.
- `rex` on the devbox's `PATH` (the package installs `/usr/bin/rex`).

## Known limits

- A new devbox takes up to 30 seconds to appear, and the config reload happens by itself.
- A stopped devbox is a host that fails to connect. Wake it with `devbox exec NAME -- true`.
  Whether the SSH proxy wakes it by itself was not tested.
- The `rex` binary is found through `REX_BIN` in `init.lua` and `devbox-sync.lua`. Update both if
  Rex changes where it installs.
- Hosts are not added to the Mac app's **Remote Hosts** list by this integration (see Use).
