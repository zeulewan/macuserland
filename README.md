# macuserland

Native macOS Dock shortcuts for small local tools.

## Apps

- `DarkPDF`: toggles Firefox PDF dark mode CSS.
- `StreamMode`: toggles AWDL/LLW for smoother Moonlight streaming.
- `Sidecar`: toggles iPad Sidecar using the local Swift launcher.
- `Synology`: mounts or unmounts the Synology SMB share over Tailscale.

## Install

```
git clone https://github.com/zeulewan/macuserland.git ~/macuserland
cd ~/macuserland
./custom-apps/install.sh --dock --privileged
```

`--dock` adds the apps to the Dock. `--privileged` installs the StreamMode LaunchDaemons and sudoers rule.

Requires Xcode Command Line Tools:

```
xcode-select --install
```

Synology config lives outside Git:

```
mkdir -p ~/.config/macuserland
cp custom-apps/apps/Synology/synology.conf.example ~/.config/macuserland/synology.conf
```
