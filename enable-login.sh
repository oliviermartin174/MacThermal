#!/bin/bash
# Install the menu-bar application in a stable per-user location and launch it
# once at login. This does not install a privileged service or retain passwords.
set -euo pipefail
cd "$(dirname "$0")"
sourceApp="$PWD/MacThermal.app"
installedApp="$HOME/Applications/MacThermal.app"
agentPath="$HOME/Library/LaunchAgents/fr.local.MacThermal.plist"
userDomain="gui/$(id -u)"
if [[ ! -x "$sourceApp/Contents/MacOS/MacThermal" ]]; then
  echo "Compilez d’abord l’application avec ./build.sh." >&2
  exit 1
fi
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
if [[ "$sourceApp" != "$installedApp" ]]; then
  ditto --norsrc "$sourceApp" "$installedApp"
fi
# Build the property list in a fresh sibling file so re-running is safe.
agentTemporary=$(mktemp "$HOME/Library/LaunchAgents/.MacThermal.XXXXXX")
trap 'rm -f "$agentTemporary"' EXIT
/usr/bin/plutil -create xml1 "$agentTemporary"
/usr/bin/plutil -insert Label -string fr.local.MacThermal "$agentTemporary"
/usr/bin/plutil -insert ProgramArguments -json '["/usr/bin/open","-g"]' "$agentTemporary"
/usr/bin/plutil -insert ProgramArguments.2 -string "$installedApp" "$agentTemporary"
/usr/bin/plutil -insert RunAtLoad -bool true "$agentTemporary"
/usr/bin/plutil -insert LimitLoadToSessionType -string Aqua "$agentTemporary"
/usr/bin/plutil -insert ProcessType -string Interactive "$agentTemporary"
chmod 644 "$agentTemporary"
mv "$agentTemporary" "$agentPath"
launchctl bootout "$userDomain/fr.local.MacThermal" 2>/dev/null || true
launchctl enable "$userDomain/fr.local.MacThermal"
launchctl bootstrap "$userDomain" "$agentPath"
echo "MacThermal démarrera à l’ouverture de session : $installedApp"
