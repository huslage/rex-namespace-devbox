# Rex devbox integration

Rex actions that create a [Namespace](https://namespace.so) devbox from a blueprint and connect
it to your local Rex client over Tailscale.

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
| `rex do devbox_up [name=NAME] [blueprint=rex]` | Create a devbox from the blueprint (or reuse `NAME`), then register it as a Rex host and check that it answers. |
| `rex do devbox_down name=NAME [stop=false]` | Remove the Rex host and stop the devbox. |

Both open a tab that shows progress. Connect with `rex -S NAME ...`. Run `rex config reload`
after you edit `init.lua` or `devbox.lua`.

The devbox does the setup work, not this script. The default image already runs a Rex server,
so the blueprint only has to share it on the tailnet.

## Blueprint `rex`

The `devbox` CLI cannot create blueprints. Create it in the Namespace dashboard
(Devboxes → Blueprints → **New Blueprint**), or with the TypeScript SDK (`blueprints.create`).

| Setting | Value |
|---|---|
| Name | `rex` |
| OS and image | Linux, `builtin:default` |
| Size | `m` |
| Access | private |
| Ephemeral | off |
| Tailscale | the workspace's `tailnet` spec (set as the Devboxes default) |

Service (dashboard only; blueprint services apply when a devbox first starts):

| Field | Value |
|---|---|
| Name | `rex-tailnet` |
| Command | `sh` |
| Args | `-c`, `rex server start && exec tailscale serve unix:///home/devbox/.local/state/rex/run/server.sock` |
| Start policy | `on-boot` |
| Restart policy | `always` |

`tailscale serve` runs in the foreground, so the service keeps the share alive and restarts it
when `tailscaled` is not ready yet. The devbox's node is ephemeral, so the share has to start
again on every boot.

A later edit to the blueprint does not change devboxes that already exist.

## Prerequisites

- `devbox` CLI, logged in (`devbox login`).
- A tailnet policy that lets you reach `tag:namespace-devbox` on `tcp:443`. Without it,
  `devbox_up` registers the host but reports that it cannot reach it. Devbox nodes join the
  tailnet through Namespace's Tailscale integration with a tag, and the tag is not part of
  `autogroup:members`, so add a grant from your users to that tag.

## Known limits

- A config-file action stops after 30 seconds, so the actions only open a tab that runs
  `devbox.lua`.
- `devbox_up` on an existing devbox runs `devbox exec NAME -- true` to wake it. The CLI has no
  start command.
- The `rex` binary is found through `REX_BIN` in `init.lua`. Update it if Rex changes where it
  installs.
