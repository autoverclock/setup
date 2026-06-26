#!/usr/bin/env bash
# Install and configure the Autoverclock agent on a HiveOS rig.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/autoverclock/setup/refs/heads/master/hive.sh \
#     | sudo bash -s -- --api-key YOUR_API_KEY
#
# Requires /usr/local/bin/autoc to already be present (manual sync during dev;
# apt repository later).
set -euo pipefail

CONF="/hive-config/autoc.conf"
SERVICE="/etc/systemd/system/autoc.service"
BINARY="/usr/local/bin/autoc"
TOTAL_STEPS=5

# --- presentation ---

C_RESET='\033[0m'
C_BOLD='\033[1m'
C_CYAN='\033[0;36m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'

print_logo() {
  printf '%b\n' "${C_CYAN}${C_BOLD}"
  cat <<'LOGO'
     _         _  ____ ___  ____
    / \  _   _| |_|  _ \__ \/ ___|
   / _ \| | | | __| | | | ) \___ \
  / ___ \ |_| | |_| |_| |/ / ___) |
 /_/   \_\__,_|\__|____//_/ |____/
LOGO
  printf '%b\n' "  Automatic GPU overclock tuning${C_RESET}"
  printf '%b\n' "  ${C_CYAN}https://autoverclock.com${C_RESET}"
  echo
}

step() {
  printf '%b[%s/%s]%b %s\n' "${C_GREEN}${C_BOLD}" "$1" "$TOTAL_STEPS" "${C_RESET}" "$2"
}

die() {
  printf '%berror:%b %s\n' "${C_YELLOW}" "${C_RESET}" "$1" >&2
  exit 1
}

# --- root check ---

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo bash "$0" "$@"
fi

# --- args ---

API_KEY=""
LABEL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-key)
      API_KEY="${2:-}"
      shift 2
      ;;
    --label)
      LABEL="${2:-}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: hive.sh --api-key KEY [--label NAME]"
      exit 0
      ;;
    *)
      die "unknown argument: $1 (try --help)"
      ;;
  esac
done

if [[ -z "$API_KEY" ]]; then
  if [[ -t 0 ]]; then
    read -r -p "Enter your Autoverclock API key: " API_KEY
  fi
fi
[[ -n "$API_KEY" ]] || die "--api-key is required (get one at https://autoverclock.com)"

print_logo

step 1 "Checking environment"

[[ -d /hive-config ]] || mkdir -p /hive-config
[[ -x "$BINARY" ]] || die "Autoverclock binary not found at $BINARY — install it first"

step 2 "Writing configuration"

TUNABLE_BLOCK='# Max seconds to wait for live hashrate after a miner restart.
MINER_SPINUP_MAX_SEC=60
# Stabilization period excluded from measurement windows.
WARMUP_SEC=90
# Baseline measurement duration (post-warmup seconds only).
BASELINE_WINDOW_SEC=300'

has_key() {
  local key="$1"
  [[ -f "$CONF" ]] && grep -qE "^[[:space:]]*${key}=" "$CONF"
}

ensure_tunable_block() {
  if [[ ! -f "$CONF" ]]; then
    printf '%s\n\n%s\n' "$TUNABLE_BLOCK" >> "$CONF"
    return
  fi
  if has_key MINER_SPINUP_MAX_SEC || has_key WARMUP_SEC || has_key BASELINE_WINDOW_SEC; then
    return
  fi
  printf '\n%s\n' "$TUNABLE_BLOCK" >> "$CONF"
}

if [[ ! -f "$CONF" ]]; then
  cat > "$CONF" <<EOF
API_KEY="${API_KEY}"
${TUNABLE_BLOCK}
EOF
else
  if grep -qE '^[[:space:]]*API_KEY=' "$CONF"; then
    sed -i "s|^[[:space:]]*API_KEY=.*|API_KEY=\"${API_KEY}\"|" "$CONF"
  else
    sed -i "1i API_KEY=\"${API_KEY}\"" "$CONF"
  fi
  ensure_tunable_block
fi

chmod 0600 "$CONF"

step 3 "Installing systemd service"

# TODO: replace manual binary sync with apt repository install when available.
# Match client/scripts/install.sh + systemd/autoc.service (known-good on HiveOS).
UNIT_TMP="$(mktemp)"
trap 'rm -f "$UNIT_TMP"' EXIT
cat > "$UNIT_TMP" <<'UNIT'
[Unit]
Description=Autoverclock client agent
# Do NOT order After=hive.service: HiveOS declares hive.service
# After=multi-user.target, so any multi-user unit ordered after it
# creates an ordering cycle and systemd silently drops the unit from
# boot. The agent instead waits for fresh miner stats at startup and
# retries via Restart=always.
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/autoc
Restart=always
RestartSec=10
# Hive's CLI tools resolve config paths (NVIDIA_OC_CONF, RIG_CONF, ...)
# from /etc/environment; without it nvidia-oc exits 0 without applying
# anything. PATH must include the Hive tool directories for the same
# reason.
EnvironmentFile=/etc/environment
Environment=PATH=/hive/bin:/hive/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# The agent restarts the miner via Hive's `miner` command, which leaves
# the miner process inside this unit's cgroup. Default (control-group)
# kill mode would SIGKILL the miner on every agent stop/upgrade; only
# the agent itself should die.
KillMode=process

[Install]
WantedBy=multi-user.target
UNIT
install -m 0644 "$UNIT_TMP" "$SERVICE"

step 4 "Enabling Autoverclock service"

systemctl daemon-reload
systemctl enable autoc
systemctl restart autoc

step 5 "Done"

echo
systemctl status autoc --no-pager -l | head -15 || true
echo
printf '%b%s%b\n' "${C_GREEN}${C_BOLD}" "Autoverclock is installed and running." "${C_RESET}"
echo
echo "Next steps:"
echo "  1. Start your miner on the rig from HiveOS (flightsheet + Start)."
echo "     The agent waits for live hashrate before registering — it will"
echo "     not start the miner for you on a new install."
echo "  2. Open https://autoverclock.com and confirm your rig appears."
echo "  3. Start baseline measurement from the web UI when you are ready."
if [[ -n "$LABEL" ]]; then
  echo
  echo "  (Label hint: ${LABEL} — set a rig label in the web UI if desired.)"
fi
echo
