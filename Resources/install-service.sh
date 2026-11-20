#!/bin/bash
set -euo pipefail
[[ $EUID -eq 0 && $# -eq 1 && "$1" =~ ^[0-9]+$ && "$1" -ge 500 ]] || exit 1
sessionUid="$1"
/usr/bin/id -un "$sessionUid" >/dev/null
resourceDirectory=$(cd "$(dirname "$0")" && pwd)
helperSource="$resourceDirectory/../MacOS/FanAssist"
[[ -x "$helperSource" ]] || exit 2
helperDestination=/Library/PrivilegedHelperTools/fr.local.MacThermal.FanAssist
stateRoot='/Library/Application Support/MacThermal'
stateDirectory="$stateRoot/$sessionUid"
daemonPlist=/Library/LaunchDaemons/fr.local.MacThermal.fans.plist
for path in /Library/PrivilegedHelperTools "$helperDestination" "$stateRoot" "$stateDirectory" "$daemonPlist"; do
 [[ ! -L "$path" ]] || { echo "Lien symbolique inattendu : installation arrêtée." >&2; exit 3; }
done
/bin/launchctl bootout system/fr.local.MacThermal.fans 2>/dev/null || true
/usr/bin/install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools "$stateRoot" "$stateDirectory"
/usr/bin/install -o root -g wheel -m 755 "$helperSource" "$helperDestination"
for name in request status; do
 [[ ! -L "$stateDirectory/$name" ]] || exit 3
 /usr/bin/install -o "$sessionUid" -g staff -m 600 /dev/null "$stateDirectory/$name"
done
printf 0 > "$stateDirectory/request"
printf waiting > "$stateDirectory/status"
/usr/bin/touch -t 200001010000 "$stateDirectory/request"
plistTemporary=$(/usr/bin/mktemp /Library/LaunchDaemons/.MacThermal.XXXXXX)
trap '/bin/rm -f "$plistTemporary"' EXIT
/bin/cat > "$plistTemporary" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>fr.local.MacThermal.fans</string>
<key>ProgramArguments</key><array><string>$helperDestination</string><string>--service</string><string>$sessionUid</string></array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>15</integer>
<key>ExitTimeOut</key><integer>20</integer>
<key>ProcessType</key><string>Background</string>
</dict></plist>
PLIST
/usr/bin/plutil -lint "$plistTemporary" >/dev/null
/usr/bin/install -o root -g wheel -m 644 "$plistTemporary" "$daemonPlist"
/bin/launchctl enable system/fr.local.MacThermal.fans
/bin/launchctl bootstrap system "$daemonPlist"
echo 'Service MacThermal installé.'
