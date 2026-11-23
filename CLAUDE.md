# Maîtrise

Add-on de montée de métiers : la route au moindre coût d'une tranche (du niveau actuel au curseur), aux prix de l'HV du moment. Repo `azeroth-commune/Maitrise` (privé pour l'instant). Espace de travail parent : `../` (outils, recherche, captures — pas dans ce repo). PRD : `azeroth-commune/Maitrise#1` ; prototype : `research/montee/` de l'atelier.
Déploiement : lien symbolique depuis le dossier AddOns du jeu, `/reload` suffit. Requiert le socle Azeroth Commune (ADR 0002) et Composants.
Vérifier : `luajit Maitrise/check.lua` depuis le dossier des add-ons (la tranche, socle chargé, recettes et prix en bouchons),
puis `tools/sim.sh test Maitrise` dans l'atelier (`tests/`, jamais dans la TOC).

## Agent skills

### Issue tracker

GitHub Issues de `azeroth-commune/Maitrise`, toujours avec `-R azeroth-commune/Maitrise` ; PR externes : non. See `docs/agents/issue-tracker.md`.

### Triage labels

Labels par défaut (needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix) + `prd`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context : `CONTEXT.md` + `docs/adr/` à la racine, créés au besoin. See `docs/agents/domain.md`.
