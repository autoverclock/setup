# autoverclock/setup

Public install scripts for connecting HiveOS rigs to [Autoverclock](https://autoverclock.com).

## HiveOS install

On the rig (as root):

```bash
curl -fsSL https://raw.githubusercontent.com/autoverclock/setup/main/hive.sh \
  | sudo bash -s -- --api-key YOUR_API_KEY
```

The script writes `/hive-config/autoc.conf`, installs the systemd unit if needed, and starts the agent. The Autoverclock binary must already be at `/usr/local/bin/autoc` (manual sync during development; apt repository planned).

After install, open https://autoverclock.com to confirm the rig appears and start the benchmark from the UI.
