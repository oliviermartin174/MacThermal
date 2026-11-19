# Ouvrir et utiliser le projet Xcode

Ouvrir `MacThermal.xcodeproj`, choisir le schéma partagé **MacThermal**, puis la destination **My Mac**. Le projet cible Intel x86_64, comme le Mac Pro 2019 validé. Aucune dépendance tierce ni génération préalable n’est nécessaire.

## Cibles

| Cible | Rôle |
| --- | --- |
| MacThermal | Application AppKit/Swift et pont C AppleSMC |
| FanAssist | Assistant C privilégié et superviseur de restauration, intégré automatiquement dans Contents/MacOS de l’application |
| MacThermalTests | Tests XCTest des seuils, hystérésis et cas de capteurs absents ; exécution des simulations C |
| FanAssistTests | Exécutable C de simulation, intégré au bundle de tests uniquement, jamais à l’application livrée |

Les réglages **Debug** et **Release** et le schéma sont versionnés. L’Info.plist de l’application est dans `Config/Info.plist`. Le modèle partagé `Sources/ThermalModel.swift` est compilé dans l’application et dans les tests, sans lancer l’application pendant les tests.

## Lancer et tester

- **⌘R** : compiler l’application et son assistant, puis lancer. La demande administrateur système est portée par MacThermal ; elle autorise le renfort pendant la session. Refuser conserve les lectures et alertes.
- **⌘U** : tests sans droits administrateur et sans écriture dans le SMC. Avec le SDK XCTest de Xcode 26.5, la cible de tests exige macOS 14 ; l’application et l’assistant ciblent macOS 12.
- **Product > Archive** : archive Release locale, pour inspection dans Organizer. Ce n’est pas une archive signée pour distribution.

Avant ⌘R, quitter une autre instance de MacThermal par son menu pour éviter deux assistants de ventilation concurrents. Le débogueur s’attache à l’application, pas aux processus privilégiés. Arrêter l’application avec Xcode interrompt son signal de présence ; le superviseur de ventilation rend la main à Apple après expiration du délai de 12 secondes, avec un bref délai supplémentaire de restauration.

En ligne de commande :

```sh
xcodebuild -project MacThermal.xcodeproj -scheme MacThermal -destination 'platform=macOS,arch=x86_64' test
xcodebuild -project MacThermal.xcodeproj -scheme MacThermal -configuration Release -destination 'platform=macOS,arch=x86_64' archive -archivePath build/MacThermal.xcarchive
```

Les scripts `build.sh` et `test.sh` restent utilisables indépendamment de Xcode.

## Signature

Le réglage initial est **Sign to Run Locally** (signature ad hoc), sans compte Apple Developer ni certificat partagé. Pour une distribution ultérieure, sélectionner sa propre équipe et son identité de signature pour l’application et l’assistant, puis préparer la sécurité et la notarisation de la version à distribuer. Aucun Team ID, certificat ou secret n’est enregistré dans le dépôt.

Le sandbox et Hardened Runtime ne sont pas activés dans la configuration de développement actuelle. Le contrôle SMC privilégié reste une fonctionnalité de distribution directe ; la création du projet Xcode ne résout pas les obstacles Mac App Store.

Si un dossier synchronisé ajoute des attributs Finder aux produits de compilation et que codesign refuse les fichiers, utiliser un Derived Data hors de ce dossier (réglages Xcode > Locations, ou `-derivedDataPath /private/tmp/MacThermalDerivedData`). Il n’est pas nécessaire de désactiver la signature ou les protections système.

Validation réalisée le 19 novembre 2026 avec Xcode 26.5 : compilation Debug, quatre tests XCTest réussis, tests des scripts indépendants réussis, archive Release créée, signature locale de l’application et de l’assistant vérifiée. L’archive contient l’assistant de production et exclut l’exécutable de simulation ; le diagnostic CPU et des deux Radeon fonctionne depuis le binaire archivé. Aucun nouveau test matériel d’écriture n’est nécessaire pour ce changement de packaging : le code de pilotage des ventilateurs est inchangé.
