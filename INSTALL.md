# Installation et releases

## Télécharger le bon fichier

**Methode recommandee : l'installateur autonome `ReaSkiiPicker-<version>-setup.lua`.**

1. Telecharger ce fichier unique, par exemple dans Telechargements. Ne pas le deplacer dans les dossiers REAPER.
2. Dans REAPER : **Actions > Show action list > New action > Load ReaScript**, choisir ce fichier.
3. Executer l'action d'installation une fois. Tous les modules sont inclus : l'installateur detecte le dossier REAPER du profil courant, installe l'arborescence et enregistre l'action `ReaSkii_Picker.lua`.
4. Repondre Oui pour ouvrir le navigateur. Ensuite, utiliser l'action `ReaSkii_Picker.lua` ; l'action d'installation peut etre retiree de la liste.

Aucun droit administrateur ni Python n'est requis. ReaImGui 0.10 ou superieur reste un prerequis ; s'il manque, l'installateur l'indique avant de modifier les fichiers. Les anciennes versions sont sauvegardees, les classements et images restent a leur place. Un point d'entree 0.1.1 connu place directement dans `Scripts` est remplace par un lanceur de compatibilite pour conserver son raccourci. Un script different est laisse intact.

Le ZIP ci-dessous reste une alternative pour une installation manuelle avancee.

Dans les Releases du dépôt privé, télécharger l'asset `ReaSkiiPicker-<version>-install.zip`.
Ne pas utiliser les liens « Source code (zip/tar.gz) » que GitHub ajoute automatiquement : ils contiennent le projet de développement.

Le ZIP d'installation contient uniquement les modules exécutés dans REAPER et la notice légale de la bibliothèque JSON. Pas de tests, Python, outils de build, données personnelles, DLL de Picker ou fichiers d'activation.

## Où l'extraire

Dans REAPER, ouvrir **Options > Show REAPER resource path in explorer/finder**.
Extraire le dossier `ReaSkiiPicker` de l'archive dans le sous-dossier `Scripts`.
Sur le poste Windows d'Arthur, le résultat pour la 0.1.1-alpha est :

```text
C:\Users\Arthur\AppData\Roaming\REAPER\Scripts\ReaSkiiPicker\
├── ReaSkii_Picker.lua
├── src\
│   ├── host.lua
│   ├── model.lua
│   ├── store.lua
│   └── ui.lua
└── vendor\
    ├── json.lua
    └── json-LICENSE
```

Conserver cette arborescence. Ne pas déplacer les modules à côté du point d'entrée.

## Prérequis et lancement

- REAPER récent et **ReaImGui 0.10 ou supérieur**, installé complètement via ReaPack (extension et shim Lua).
- Aucun Python ni outil Git n'est nécessaire pour utiliser le navigateur.
- Dans **Actions > Show action list > New action > Load ReaScript**, sélectionner `Scripts/ReaSkiiPicker/ReaSkii_Picker.lua`.
- Attribuer un raccourci si souhaité. La même action ouvre et ferme la fenêtre.
- Seul ce fichier d'entrée est à charger dans les Actions, pas les fichiers de `src`.

La 0.1.1-alpha ne contient pas encore la nouvelle commande de capture automatique, dont la validation Windows reste incomplète. Une version ultérieure peut ajouter un module `src/screenshot.lua` et demander js_ReaScriptAPI pour cette fonction ; elle ne doit pas être publiée comme vérifiée avant les tests natifs.

## Mettre à jour sans perdre les classements

1. Fermer uniquement la fenêtre ReaSkii Picker et sauvegarder son ancien dossier de scripts à part.
2. Remplacer `Scripts/ReaSkiiPicker` avec le dossier du nouveau ZIP.
3. Relancer la même action. Ne pas créer une deuxième action si le chemin est inchangé.

**Ne jamais remplacer ni supprimer `REAPER/ReaSkiiPicker/library.json`** lors d'une mise à jour : il contient les classements, hors du dossier du programme. Conserver aussi sa sauvegarde `.bak` et les éventuelles images sous `REAPER/ReaSkiiPicker/previews`.

Les images importées de l'ancien Picker restent référencées dans `REAPER/PluginPicker/previews` : conserver ce dossier si ces images sont utilisées. Aucun remplacement de la DLL ni des fichiers d'activation du Picker acheté n'est nécessaire.

## Procédure de publication pour le développement

À chaque version **validée**, publier une release dans le dépôt privé avec un ZIP d'installation minimal, en plus de l'installation vérifiée chez Arthur. Ne pas publier une fonctionnalité expérimentale en mélangeant les changements non validés avec une version stable de l'alpha.

Le packager prend exclusivement un commit Git, jamais les modifications non committées :

```sh
python scripts/runtime_release.py --ref HEAD
```

Après les tests, l'installation vérifiée et le push du commit :

```sh
python scripts/runtime_release.py --ref HEAD --publish --verification-report qa/package-report.json
```

La publication exige que chaque fichier runtime soit identique au candidat testé et que le rapport de déploiement corresponde à son archive. Elle genere aussi l'installateur autonome depuis les memes fichiers. Elle vérifie la confidentialité du dépôt, le commit du tag, la liste des assets et les SHA256 des deux assets retéléchargés depuis GitHub. Les preuves QA et données du poste restent locales.
