# Relay GNOME Shell extension

Install or update the development copy from the repository root:

```bash
app/linux/gnome-shell/install-relay-extension.sh
```

The installer validates the UUID, copies physical files to
`~/.local/share/gnome-shell/extensions/relay@foresight.app`, removes stale files
from older copies, enables the extension, and attempts GNOME Shell's supported
extension reload path.

GNOME Shell 46 on Wayland does not discover a newly installed local extension
inside an already-running session. On the first installation, follow the
installer's single logout/login instruction. Once the current Shell knows the
UUID, rerunning the same command reloads ordinary source updates without
restarting GNOME Shell.
