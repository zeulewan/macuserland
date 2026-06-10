# Sidecar Instructions

- `SidecarLauncher.swift` uses private macOS APIs; keep comments clear around version-specific workarounds.
- Keep the Dock script as a thin wrapper around `~/bin/SidecarLauncher toggle`.
- Do not commit device names or Apple ID details.
