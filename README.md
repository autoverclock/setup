# autoverclock/setup

Public install scripts for connecting HiveOS rigs to [autoOC](https://autoverclock.com).

## HiveOS install

On the rig (as root):

```bash
curl -fsSL https://raw.githubusercontent.com/autoverclock/setup/main/hive.sh \
  | sudo bash -s -- --api-key YOUR_API_KEY
```

The script writes `/hive-config/autooc.conf`, installs the systemd unit if needed, and starts the agent. The autoOC binary must already be at `/usr/local/bin/autooc` (manual sync during development; apt repository planned).

After install, open https://autoverclock.com to confirm the rig appears and start the benchmark from the UI.
