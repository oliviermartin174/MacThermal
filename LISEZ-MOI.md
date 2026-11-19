# MacThermal 1.3

Application native Swift/AppKit pour Mac Pro 2019 Intel (MacPro7,1), macOS 12 ou ultérieur. Double-cliquer sur MacThermal.app. Les températures du CPU et des GPU s’affichent dans la barre des menus, actualisées toutes les trois secondes.

## Alertes

Menu → Régler les seuils… : un seuil indépendant pour le CPU et chaque GPU, mémorisé entre lancements. Plage 40–110 °C ; valeurs initiales CPU 75 °C, GPU 85 °C. Ce sont des seuils d’alerte modifiables, pas des limites constructeur.

Seul le composant en alerte devient rouge et gras avec ⚠︎. Une alerte sonore et une notification sont émises une fois par épisode. Autoriser les notifications dans les réglages macOS ; Concentration peut masquer les bannières. Réarmement à seuil − 5 °C.

## Renfort des ventilateurs

Le MacPro7,1 testé refuse les écritures des minimums F<n>Mn. La version 1.2 utilise des consignes temporaires F<n>Tg et le mode manuel F<n>Md=1, acceptés sur cette machine. Elle ne modifie jamais les minimums. Le renfort concerne les quatre ventilateurs du Mac, pas un pilotage indépendant de ventilateurs internes Radeon.

Une autorisation administrateur est demandée au lancement et vaut pour toute la session. L’application ne conserve pas le mot de passe. En cas de refus, températures et alertes continuent de fonctionner.

Quand un seuil est dépassé, chaque consigne est au moins égale à minimum + 20 % × (maximum − minimum), sans réduire la consigne ni la vitesse capturées en mode automatique. Sur cette machine : planchers usuels de 640 et 900/900/900 tr/min. Tant que le renfort est actif, les consignes ne sont pas abaissées. Si une température atteint le plus bas de [seuil + 10 °C] et [80 °C CPU / 95 °C GPU], l’application demande le maximum. Le renfort temporaire remplace la consigne Apple : il ne s’agit pas d’un simple relèvement du minimum sous contrôle Apple permanent.

Quand tous les composants sont redescendus à seuil − 5 °C, l’assistant remet explicitement chaque ventilateur en mode automatique Apple (F<n>Md=0), et vérifie ce mode par relecture. Il ne force pas une vitesse « standard » fixe : Apple retrouve la main sur les vitesses adaptées à l’ensemble des capteurs du Mac. Le ralentissement physique peut prendre quelques secondes.

Si un capteur devient indisponible, retour au mode automatique Apple. L’assistant contrôle lui-même le capteur CPU TC0P : si inaccessible ou à partir de 80 °C en proximité, il rend également la main à Apple, qui dispose d’autres capteurs.

## Surveillance et restauration

Un processus privilégié de surveillance distinct restaure le mode automatique si le processus qui pilote les ventilateurs s’arrête, y compris après une interruption forcée de ce dernier. Si l’application ne transmet plus son état pendant plus de 12 secondes, l’assistant arrête le pilotage et restaure le mode automatique. La fermeture normale rend également la main à Apple. Une interruption forcée simultanée des deux processus privilégiés ou une panne du SMC peut empêcher cette restauration ; un redémarrage réinitialise la régulation.

Ne pas exécuter un autre logiciel de contrôle de ventilateurs simultanément. L’assistant exige les quatre ventilateurs initialement en automatique. Une écriture refusée suspend le renfort et déclenche une tentative de retour automatique. Une restauration réellement non confirmée est signalée ; le simple refus d’écrire un minimum déjà inchangé ne produit plus de fausse demande de redémarrage.

## Capteurs

CPU : AppleSMC TC0P en priorité (proximité CPU), puis TC0D/TC0E/TC0F. La température de proximité peut être sensiblement inférieure au cœur le plus chaud. GPU : Temperature(C) du pilote Radeon, périphérique associé via l’identifiant IORegistry Metal ; ce n’est pas nécessairement le point chaud ou la mémoire vidéo. Une température inaccessible est affichée « — ».

Aucune connexion réseau ni collecte de données. Les interfaces SMC/IORegistry utilisées ne sont pas une API publique stable de température/ventilation : une évolution macOS peut nécessiter une nouvelle validation. Signature locale ad hoc, sans notarisation Apple.

## Sources, compilation et validation

Sources dans Sources/. Avec les outils de développement Apple : `./build.sh`. Compilation Intel x86_64. Diagnostic : `./MacThermal.app/Contents/MacOS/MacThermal --diagnostic`.

Tests simulés sans écriture matérielle :
```
clang -I Sources Tests/FanAssistTests.c -o /tmp/MacThermalFanTests
/tmp/MacThermalFanTests
```

Les rapports Validation-*.txt documentent les essais matériels sur ce Mac : refus des minimums, acceptation des consignes/modes, vitesses réelles et retour automatique. La validation ne vaut que pour le Mac et la version de macOS testés.

Références :
- https://github.com/hholtmann/smcFanControl/tree/master/smc-command
- https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift
- https://github.com/tatsuikeda/mac-fan-assist

Validation matérielle de la version 1.2 effectuée le 19 novembre 2026 : renfort réel, retour automatique après demande de refroidissement et retour automatique après expiration du signal applicatif validés. Les quatre modes finaux sont à 0. Les tests simulés vérifient aussi les seuils avec hystérésis et la restauration après un échec de commande.


## Autorisation MacThermal — version 1.3

La demande administrateur est exécutée directement par MacThermal avec NSAppleScript, sur une file de travail dédiée et séquentielle. Aucun processus osascript n’est lancé. Le nom affiché par macOS est MacThermal (confirmé par l’utilisateur pendant la validation). Le mot de passe reste saisi dans la fenêtre système ; l’application ne le reçoit ni ne le conserve.

L’interface et l’envoi du signal de présence continuent pendant l’autorisation et toute la session de ventilation. L’assistant de ventilation et son superviseur restent identiques à la version 1.2, avec retour au mode automatique après refroidissement, fermeture ou expiration du signal. Cette version ne crée pas de service permanent au démarrage du système.

Documentation Apple : https://developer.apple.com/documentation/foundation/nsapplescript
