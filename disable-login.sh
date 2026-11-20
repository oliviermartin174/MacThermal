#!/bin/bash
# Remove only this user's automatic-login registration; keep the application.
set -euo pipefail
agentPath="$HOME/Library/LaunchAgents/fr.local.MacThermal.plist"
launchctl bootout "gui/$(id -u)/fr.local.MacThermal" 2>/dev/null || true
if [[ -f "$agentPath" ]]; then
  label=$(/usr/bin/plutil -extract Label raw "$agentPath")
  if [[ "$label" != fr.local.MacThermal ]]; then
    echo "Fichier inattendu : aucune suppression." >&2; exit 1
  fi
  rm "$agentPath"
fi
echo "Démarrage automatique MacThermal désactivé."
