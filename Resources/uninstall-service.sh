#!/bin/bash
set -euo pipefail
[[ $EUID -eq 0 && $# -eq 1 && "$1" =~ ^[0-9]+$ && "$1" -ge 500 ]] || exit 1
/bin/launchctl bootout system/fr.local.MacThermal.fans 2>/dev/null || true
/bin/rm -f /Library/LaunchDaemons/fr.local.MacThermal.fans.plist /Library/PrivilegedHelperTools/fr.local.MacThermal.FanAssist
# Leave only other users' state directories intact.
stateDirectory="/Library/Application Support/MacThermal/$1"
if [[ -d "$stateDirectory" && ! -L "$stateDirectory" ]]; then
 /bin/rm -f "$stateDirectory/request" "$stateDirectory/status"
 /bin/rmdir "$stateDirectory" 2>/dev/null || true
fi
echo 'Service de ventilation désinstallé.'
