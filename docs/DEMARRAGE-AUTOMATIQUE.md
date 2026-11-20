# Démarrage automatique et service de ventilation

Deux composants ont des rôles distincts :

- Un LaunchAgent lance l’application de barre des menus à l’ouverture de la session graphique. Il utilise la copie stable `~/Applications/MacThermal.app`.
- Un LaunchDaemon système lance l’assistant de ventilation au démarrage du Mac. Son installation demande une seule autorisation administrateur dans MacThermal. Les lancements suivants ne redemandent pas le mot de passe.

Avant l’ouverture de session, et après fermeture de l’application, la régulation Apple reste responsable de la ventilation. La surveillance CPU/GPU avec seuils personnalisés commence à l’ouverture de session ; le service ne remplace pas la régulation Apple en l’absence de mesures récentes.

## Installer

Compiler avec Xcode ou `./build.sh`, puis exécuter `./enable-login.sh` pour copier l’application et enregistrer son lancement à l’ouverture de session. Dans le menu MacThermal, choisir l’installation du service. Accepter la demande administrateur portée par MacThermal.

Pour déclencher l’installation dès le lancement de la copie stable :

```sh
open -g "$HOME/Applications/MacThermal.app" --args --install-service
```

Quitter d’abord toute instance déjà ouverte avant de transmettre cette option de lancement. Une mise à jour de l’assistant installé nécessite de refaire l’installation autorisée du service ; une simple recompilation de l’application ne remplace pas le binaire protégé.

## Fichiers installés

- Application : `~/Applications/MacThermal.app`.
- Démarrage de l’interface : `~/Library/LaunchAgents/fr.local.MacThermal.plist`.
- Service : `/Library/LaunchDaemons/fr.local.MacThermal.fans.plist`.
- Assistant protégé : `/Library/PrivilegedHelperTools/fr.local.MacThermal.FanAssist`.
- Communication de session : `/Library/Application Support/MacThermal/<uid>/request` et `status`.

L’assistant, sa configuration et les répertoires de communication sont possédés par root et non modifiables par l’utilisateur ordinaire. Les deux fichiers de session sont accessibles uniquement à l’utilisateur configuré. L’assistant n’accepte ni commande shell, ni programme à lancer, ni chemin fourni à chaque requête : l’utilisateur configuré transmet seulement trois états bornés (standard, renfort, maximal). Il n’y a ni conservation de mot de passe ni modification de sudoers, setuid ou des protections macOS.

Le service cible un seul utilisateur installé par Mac. Avant une installation pour un autre utilisateur, désinstaller celle en place ; la nouvelle installation remplace la configuration système unique.

## Retour automatique

Quand tous les composants sont sous leur seuil moins 5 °C, les quatre modes sont remis à automatique par lecture de confirmation. Une absence de capteur ou un CPU de proximité trop chaud rend la main à Apple. Un superviseur distinct restaure également le mode automatique en cas de panne du pilote de ventilation. Si l’application ne transmet plus son état depuis 12 secondes, la session est arrêtée et le service reste en attente ; la restauration peut ajouter quelques secondes de délai.

Après un redémarrage du processus du service, le mode automatique est rétabli avant d’accepter une nouvelle session. Ne pas utiliser simultanément un autre utilitaire qui pilote les ventilateurs. Une panne persistante d’accès au SMC peut toujours empêcher de confirmer la restauration.

## Désactiver et désinstaller

`./disable-login.sh` désactive seulement le lancement automatique de l’interface, sans supprimer l’application. Quitter MacThermal si nécessaire pour interrompre sa session de ventilation.

Pour supprimer aussi le service système, dans Terminal :

```sh
sudo /bin/bash "$HOME/Applications/MacThermal.app/Contents/Resources/uninstall-service.sh" "$(id -u)"
```

Cette désinstallation autorisée arrête le service avec sa restauration normale et supprime uniquement ses fichiers système connus. Elle conserve l’application et les préférences de seuils. Contrôler la ventilation après une désinstallation interrompue ou un échec du SMC.

## Vérifier

```sh
launchctl print "gui/$(id -u)/fr.local.MacThermal"
launchctl print system/fr.local.MacThermal.fans
```

L’installation charge les deux composants immédiatement. Un redémarrage réel de macOS n’est pas nécessaire aux tests d’installation, et n’est pas effectué automatiquement. Les essais matériels sont résumés dans `Validation-service.txt`.
