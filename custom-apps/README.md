# Custom Apps

Four native macOS Dock shortcuts, rebuilt locally without Rosetta.

- `DarkPDF`: toggles Firefox PDF dark CSS.
- `StreamMode`: toggles AWDL/LLW off for Moonlight streaming.
- `Sidecar`: toggles iPad Sidecar via `~/bin/SidecarLauncher`.
- `Synology`: mounts or unmounts the Synology SMB share over Tailscale.

## Install

```bash
./custom-apps/install.sh --dock --privileged
```

`--dock` adds the apps to the Dock. `--privileged` installs StreamMode's LaunchDaemons and sudoers rule.

## Requirements

- Xcode Command Line Tools: `xcode-select --install`
- Firefox for `DarkPDF`
- Tailscale and saved SMB credentials for `Synology`
- Mac/iPad support for Sidecar

Synology config is read from `~/.config/macuserland/synology.conf`; copy `apps/Synology/synology.conf.example` and edit it locally.

Notes: `DarkPDF` needs `toolkit.legacyUserProfileCustomizations.stylesheets=true` in Firefox. `StreamMode` needs `--privileged` to work.
