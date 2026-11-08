# ReaSkii Picker 0.1.1-alpha

Navigateur FX indépendant pour REAPER, écrit en Lua avec ReaImGui. Ce n'est ni un patch de Plugin Picker, ni une fenêtre qui pilote sa DLL. Aucun pseudocode de décompilation n'est inclus dans l'implémentation.

## Contrat

- Ouverture avec focus dans la recherche.
- Une saisie recherche parmi tous les FX connus de cette installation REAPER, indépendamment de la catégorie sélectionnée. Les résultats globaux et All FX sont affichés en liste compacte virtualisée, jamais en cartes sans captures.
- Entrée ou clic dans la recherche globale insère directement un FX sur la première piste sélectionnée. L'insertion crée un point Undo et ferme le navigateur.
- Sans recherche, la collection et ses catégories restent une grille de vignettes. Images plus grandes, noms sur deux lignes, espacements et contrôles repris d'après la référence visuelle fournie.
- La barre ne montre que les dossiers racines. Dynamics, SFXs et Tools ouvrent de vrais menus de sous-dossiers; la sélection filtre la grille et le fil d'Ariane indique le dossier choisi. Les niveaux supplémentaires sont imbriqués.
- Add Plugin dans l'en-tête ou au clic droit sur le fond/une carte ouvre un catalogue en liste, puis une étape de choix des catégories. Confirmer ajoute à la collection sans insérer sur la piste; Cancel n'écrit rien. Une entrée peut rester non classée et une entrée existante n'est pas dupliquée.
- Clic droit sur une carte ou ligne : ajout à une catégorie, retrait d'une affectation, choix d'une vignette pour une carte enregistrée.
- Settings donne accès à la création de catégories et au rafraîchissement du catalogue. Les catégories et sous-catégories importées sont conservées.
- Aucun besoin d'ajouter un FX à la collection pour l'utiliser.

## Installation manuelle de cette alpha

Prérequis : REAPER récent, ReaImGui 0.10 ou supérieur installé complètement par ReaPack (extension et shim Lua). Tests complets sous REAPER 7.85 Linux / ReaImGui 0.10.0.5. L'alpha initiale a aussi été installée et démarrée sur REAPER Windows 7.81 / ReaImGui 0.10.0.2; les preuves de chaque mise à jour Windows sont distinctes des tests Linux.

1. Extraire le dossier complet dans le dossier de ressources REAPER, sous `Scripts/ReaSkiiPicker`.
2. Dans Actions, charger `ReaSkii_Picker.lua` comme nouveau ReaScript dans la section Main.
3. Lui attribuer un raccourci distinct de Picker pendant les essais.
4. Exécuter l'action. La même action ferme puis rouvre le navigateur.

Le point d'entrée est testé comme action indépendante, pas seulement avec dofile dans une fixture.

## Données et préservation

Au premier lancement seulement, si `PluginPicker/categories.json` existe dans les ressources REAPER, ses catégories et `PluginPicker/plugins.json` sont lus et validés. La nouvelle bibliothèque est enregistrée dans `ReaSkiiPicker/library.json`, en dehors du dossier de scripts.

Les identifiants, affectations, sous-catégories et ordres présents sont conservés. Les vignettes existantes sont référencées en lecture seule dans `PluginPicker/previews`. La suppression ou le déplacement de ce dossier fait donc disparaître les images, pas la collection. Aucune capture automatique ni ouverture de tous les plugins pour faire des captures.

Les écritures suivantes concernent uniquement notre bibliothèque. Chaque remplacement réussi conserve l'ancienne version sous `library.json.bak`. Un fichier existant illisible provoque un refus, pas un réimport destructif. Le mécanisme temporaire/backup ne garantit pas la résistance à toute coupure de courant; sur Windows, une interruption entre les renommages peut nécessiter de restaurer le .bak manuellement.

Ni la DLL, ni la licence, ni les JSON de Picker ne sont modifiés. Aucun fichier personnel de Picker ou de REAPER n'est livré dans l'archive.

## Limites de cette première tranche

- Ce n'est pas encore une reproduction visuelle à l'identique de Picker. La passe 0.1.1 utilise la capture comparative d'Arthur pour rapprocher la mise en page, les menus et les proportions; elle ne prétend pas réimplémenter toutes les fonctions de l'original.
- Pas de réorganisation graphique des cartes, renommage/suppression de catégorie ou capture automatique.
- Pas encore de prise en charge des FX chains, FX de prise, insertion sur plusieurs pistes ou FX d'entrée.
- Le catalogue est celui de `EnumInstalledFX`, pas un scan de tous les fichiers du disque. Rescan relit cette liste; il ne lance pas un scan VST complet.
- Insertion via le nom documenté de TrackFX_AddByName. Les noms ambigus sont refusés plutôt que résolus arbitrairement. CLAP/VST3/Waves réels sur Windows restent à tester.
- Une carte importée mais absente de l'installation de test reste visible et non insérable. Sous Linux, les plugins Windows d'Arthur ne sont pas chargés.
- Recherche insensible à la casse ASCII et par mots littéraux; pas encore de normalisation Unicode avancée.
- Import initial uniquement : les changements ultérieurs dans Picker ne sont pas resynchronisés automatiquement.
- Fenêtre ReaImGui indépendante du thème REAPER. Pas de dépendance à ReaSkii comme thème.

## Sources

- `src/model.lua` : recherche, collection et catégories; sans dépendance REAPER.
- `src/store.lua` : import JSON et sauvegarde indépendante.
- `src/host.lua` : catalogue REAPER, insertion et Undo.
- `src/ui.lua` : interface ReaImGui.
- `ReaSkii_Picker.lua` : action Toggle et cycle de vie.
- `vendor/json.lua` : bibliothèque JSON de rxi, MIT, notice dans `vendor/json-LICENSE`.

## Vérification

Les tests de développement utilisent une copie portable de REAPER sous Xvfb, avec configuration et chemins de plugins isolés. Aucun projet utilisateur n'est ouvert et aucun plugin commercial n'est exécuté pendant les tests Linux.

`tests/run.py` exécute les tests Lua et vérifie la syntaxe de chaque fichier. `--native` exerce catalogue, insertion et Undo dans REAPER. `--toggle` charge le véritable point d'entrée dans la liste d'actions, puis le ferme et le rouvre. `tests/gui_test.py` utilise de vrais événements souris/clavier et les rectangles produits par le rendu courant; ses captures ne sont pas des maquettes.

Les chemins locaux des outils et données de test dans les runners sont propres au poste de développement. Ils ne sont utilisés par aucun fichier runtime.

Projet local expérimental, sans publication. Chaque candidat vérifié est installé séparément de Picker dans le REAPER d'Arthur, après sauvegarde de la version précédente et conservation de sa bibliothèque.
