# Belt Capacity Helper

**Ever wondered how many assemblers a single belt can actually feed?**

A quality-of-life mod for Factorio 2.0 and 2.1. Open the machine, press
**Alt + N**, and read the number for every belt tier you own — no external
calculator, no configuration.

- Reads the **live entity**, so modules, beacons, quality and productivity are
  already baked into the numbers — nothing is recomputed by hand.
- Discovers belt tiers from the **runtime prototypes**, so every modded belt
  shows up (Space Age, Bob's, Nullius, Ultimate Belts, …) with no hardcoded
  vanilla values.
- Per-ingredient **lane selector** (one lane or a full belt) so the table
  matches how your bus is actually wired.
- **Belt stacking** aware, including the per-item stack size cap, with an
  optional planning mode behind a padlock.
- English and French.

**License:** MIT · **Factorio:** 2.0 and 2.1

The text to paste into the mod portal lives in
[`docs/mod-portal-description.md`](docs/mod-portal-description.md) — same content
as this README's intro, but with absolute image URLs, which the portal requires.

*La documentation ci-dessous est en français.*

---

## Principe

Le mod lit **l'entité réelle**, jamais le prototype de recette. `crafting_speed`
et `productivity_bonus` renvoient déjà les valeurs finales, donc modules,
beacons, qualité, tier de machine et recherches sont pris en compte
automatiquement — rien n'est recalculé à la main.

Les tiers de tapis sont découverts au runtime via `prototypes.get_entity_filtered`.
Aucune valeur vanilla n'est codée en dur : n'importe quel mod qui déclare un
`transport-belt` apparaît dans le tableau (Space Age, Bob's, Nullius, Ultimate
Belts…).

## Utilisation

1. Ouvrir une machine de fabrication (assembleur, four, silo).
2. **Alt + N** — ou le bouton dans la barre de raccourcis.

Le raccourci est rebindable dans **Options → Contrôles → Mods**.

`Alt + B` et `Ctrl + B` sont pris par le vanilla (blueprint, bibliothèque de
blueprints). `N` a été retenu parce que Factorio interprète les `key_sequence`
en **positions physiques QWERTY** : sur un clavier AZERTY, un `W` déclaré tombe
sur la touche marquée `Z`. `N` occupe la même position sur les deux
dispositions, donc la touche appuyée est bien celle qui est écrite.

La fenêtre s'ancre à droite pour laisser le GUI de la machine visible.

### Lecture du tableau

- Une **colonne par ingrédient solide**, une **ligne par tier de tapis**.
- Les deux **icônes de lanes** sous chaque ingrédient disent comment il arrive :
  une seule lane, ou le tapis complet. Celle qui est active est enfoncée, un
  clic sélectionne directement l'autre.
- Le sélecteur **Empilage** (`×1 ×2 ×4 …`) en en-tête simule un niveau
  d'empilage. Le **cadenas** de la barre de titre choisit sa portée :
  - **fermé** (défaut) — bornes = ta recherche réelle, tous les chiffres sont
    atteignables ;
  - **ouvert** — mode planification, tu peux monter jusqu'à ×16 même sans la
    recherche. Les niveaux non recherchés sont teintés, et un bandeau
    « ⚠ Mode planification » reste affiché au-dessus du tableau.

  Refermer le cadenas ramène immédiatement à ton niveau réel.
- La colonne **Machines** est le minimum de la ligne : ce que ta configuration
  tient réellement à ce tier.
- L'**ingrédient limitant** est signalé sous le tableau.
- Les **fluides** sont listés en unités/s, sans traduction en tapis (le débit
  d'un tuyau dépend de sa longueur, c'est un autre calcul).

La configuration de lanes est mémorisée **par joueur et par recette** : tu
retrouves ton réglage en réouvrant la même recette. Le bouton de reset dans la
barre de titre remet tout à 2 lanes.

## Réglages (par joueur)

| Réglage | Défaut | Effet |
|---|---|---|
| Ouverture automatique | off | Ouvre la fenêtre dès qu'une machine est ouverte |
| Tapis débloqués uniquement | on | Masque les tiers non recherchés — utile avec les mods à 8-10 tiers |
| Débits de fluides | on | Affiche les lignes fluides |

## Calculs

```
débit d'une lane  = belt_speed × 60 ticks × 4 cases/tile
empilage          = min(1 + force.belt_stack_size_bonus, item.stack_size)
crafts/s          = crafting_speed / recipe.energy
conso/s           = amount × crafts/s               (la productivité ne la réduit pas)
prod/s            = (ignoré + boostable × (1 + productivité)) × crafts/s
machines          = (débit_lane × lanes × empilage) / conso/s
```

### Empilage sur tapis

L'empilage (Space Age, ou des mods comme `stack-inserters`) est lu depuis
`force.belt_stack_size_bonus`, donc n'importe quelle source de ce bonus est
prise en compte sans code spécifique.

Le plafond par objet compte : un objet dont la `stack_size` vaut 1 ne s'empile
**jamais**, même avec la recherche à fond. Son tooltip le signale, car sa
colonne paraît sinon anormalement basse sans raison visible.

L'ingrédient limitant se calcule en **cases de tapis par seconde**, pas en
objets par seconde — un objet non empilable peut brider la ligne même s'il en
faut peu.

`ignored_by_productivity` est respecté : les recettes de recyclage ne créent pas
d'items gratuits.

## Développement

Installé dans `~/.factorio/mods/BeltCapacityHelper` par lien symbolique, donc
toute modification ici est prise en compte au prochain lancement.

```bash
make test     # vérif syntaxe + validation des locales + tests de calcul
make icons    # régénère les icônes et la vignette du portail
make package  # les deux zips distribuables (Factorio 2.0 et 2.1)
make clean    # supprime build/
```

### Versionnement et double cible

Le code est identique pour Factorio 2.0 et 2.1 : seul `info.json` change
(`factorio_version` et le plancher de dépendance `base`). `make package` dérive
donc **deux archives d'une même source**.

Le **minor encode le canal de jeu** :

| Minor | Canal | Exemple |
|---|---|---|
| pair (0, 2, 4…) | Factorio 2.0 — c'est la version canonique dans `info.json` | `0.2.0` |
| impair (1, 3, 5…) | Factorio 2.1 — dérivé automatiquement en minor + 1 | `0.3.0` |

- Un **correctif** bump le patch des deux côtés : `0.2.0 → 0.2.1` et
  `0.3.0 → 0.3.1`. Le patch reste donc libre sur chaque canal.
- Une **feature** doit avancer le minor canonique **d'au moins 2**
  (`0.2.x → 0.4.x`), sinon le 2.1 dérivé (`0.5.x`) réutiliserait un minor impair
  déjà publié (`0.3.x`).

`make package` refuse un minor canonique impair, qui casserait la convention
silencieusement. Quand le support de 2.0 sera abandonné, il suffira de retirer
la cible correspondante dans `tests/make_package.py` et le mod reprendra un
versionnement continu.

Même schéma que `smart-train-combinator`.

Les icônes du raccourci et des sélecteurs sont générées par script
(`tests/make_icons.py`) plutôt que dessinées à la main : deux variantes pour le
raccourci, car les chevrons de flux deviennent illisibles en 24 px et le petit
format garde seulement la silhouette et la séparation des lanes.

`thumbnail.png` (144 × 144, la taille attendue par le portail de mods) est
dérivé de `assets/thumbnail-source.png` par le même script — l'original pleine
résolution reste versionné pour pouvoir régénérer la vignette.

Les tests stubbent l'API Factorio et vérifient les débits vanilla connus
(7.5 / 15 / 22.5 / 30 items/s par lane) ainsi que la productivité, les
probabilités, les plages `amount_min`/`amount_max` et les gardes.

## Limites connues

- Les fours affichent la dernière recette fondue ; un four neuf n'a pas encore
  de recette, la fenêtre ne s'ouvre pas.
- Les valeurs se rafraîchissent une fois par seconde (modules changés, beacon
  construit, recherche terminée).
