# Rex devbox integration

Your Namespace devboxes appear as Rex hosts on their own. Create a devbox from the `rex`
blueprint (dashboard or `devbox create --blueprint rex`) and, within about 30 seconds, connect
with `rex -S NAME`. The devbox runs Rex's login server on its tailnet node. Each host has two
endpoints, tried in order: `http://NAME.<tailnet>:7297` (the login server) and
`ssh://devbox@NAME.devbox.namespace` (through Namespace's SSH proxy, as a fallback).

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
- Each host has the endpoints `http://NAME.<tailnet>:7297` and
  `ssh://devbox@NAME.devbox.namespace`. Rex tries them in order. The tailnet endpoint needs the
  tailnet grant from members to `tag:namespace-devbox` on `tcp:7297` (infra-core PR 1041). SSH
  uses your system `ssh` and the Namespace proxy that `devbox configure-ssh` sets up in
  `~/.namespace/ssh/`.

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

**Init script.** It runs once. It installs Rex and tells the login server who may use the
devbox. Replace the login in `YOUR_LOGIN` with your Tailscale login. Choose the Rex channel that
matches your local client, because client and server API revisions can differ between channels.
The sync finds blueprint devboxes by the install URL, so keep `pkgs.superlogical.com/rex`.

```sh
set -eu
if [ "$(id -u)" = 0 ]; then sudo=""; else sudo="sudo -n"; fi
curl -fsSL https://pkgs.superlogical.com/rex/install.sh | $sudo sh -s -- --channel preview
LOGIN=YOUR_LOGIN
$sudo sh -c "cat > /etc/rex/accounts.jsonc" <<ACCOUNTS
{"version":1,"accounts":{"devbox":{"principals":["tailscale:$LOGIN"]}},"defaults":{"tailscale:$LOGIN":"devbox"}}
ACCOUNTS
echo 'XDG_RUNTIME_DIR=/run/user/1001' | $sudo tee -a /etc/environment >/dev/null
```

The devbox has no systemd, so nothing creates `/run/user/1001`, where the login server expects
the account's Rex server. The service below creates it, and `/etc/environment` tells the account's
session where it is.

**Service.**

| Field | Value |
|---|---|
| Name | `rex-server` |
| Command line | `sh -c 'until command -v rex >/dev/null 2>&1; do sleep 1; done; sudo -n mkdir -p /run/user/1001; sudo -n chown devbox:devbox /run/user/1001; sudo -n chmod 700 /run/user/1001; exec sudo -n rex login-server --accounts /etc/rex/accounts.jsonc --extra-listen tailnet://:7297'` |
| Start | `on-boot` |
| Restart | `always` |

Namespace starts services while the init script is still running, so the command waits for `rex`.
The dashboard takes one command line, so keep the single quotes together. `rex login-server`
runs as root (`sudo -n`), identifies each caller through the devbox's Tailscale node, and starts a
Rex server for the `devbox` account. A `pam_setcred ... code 17` warning in the log is harmless.

A later edit to the blueprint does not change devboxes that already exist.

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
