# Custom Apps Instructions

- `install.sh` should remain idempotent and safe to run as the login user.
- Use `sudo` only inside explicit privileged install steps.
- Keep app behavior in `apps/<Name>/<Name>.sh`; keep the launcher generic.
- Store per-machine config outside Git under `~/.config/macuserland/`.
