-- Maîtrise, la tranche tenue (Maitrise#3) : une tranche en cours est un projet de Composants qu'elle tient (lignes
-- fabrication, raison « Maîtrise : <métier> de X à Y »). Ici : le stockage, créer, recalculer, finir, la progression
-- (compétence / curseur : rien d'autre, ni avance ni décompte des fabrications). Pas de fenêtre : testable seule (check.lua).
-- MaitriseDB.tranches[guid][métier] = { projet (identité Composants), de (compétence à la création ou au dernier calcul),
-- a (le curseur) } ; une tranche gardée par une version plus ancienne porte encore faites et etapes, ignorés.
-- Au plus une par personnage et par métier. Rien ne se recalcule seul (pas d'état deviné) : seul un clic le fait.
local _, ns = ...

local function db()
  MaitriseDB = MaitriseDB or {}
  MaitriseDB.tranches = MaitriseDB.tranches or {}
  return MaitriseDB
end

local function raison(metier, de, a) return ("Maîtrise : %s de %d à %d"):format(metier, de, a) end

-- La tranche (GUID, nil = le connecté) d'un métier et son projet ; un projet supprimé dans Composants : tranche oubliée.
function ns.trancheDe(metier, guid)
  local t = (db().tranches[guid or UnitGUID("player")] or {})[metier]
  if not t then return nil end
  local p = Composants.Projet(t.projet)
  if not p then db().tranches[guid or UnitGUID("player")][metier] = nil return nil end
  return t, p
end

-- Les lignes fabrication d'une route : une par recette (les étapes de la même recette s'additionnent).
local function lignes(res)
  local out, rang = {}, {}
  for _, f in ipairs(res.fabrications) do
    local l = rang[f.cle]
    if l then l.fois = l.fois + f.fois
    else l = { recette = f.cle, fois = math.max(1, math.floor(f.fois)) }; rang[f.cle] = l; out[#out + 1] = l end
  end
  return out
end

-- Tient le projet p avec la route res, au curseur : met la tranche (GUID du connecté) à jour. Rend la tranche.
local function tenir(p, metier, res, curseur)
  -- Le nom du projet porte les niveaux, comme sa raison (liste « Projets » de Composants), et les suit au recalcul.
  Composants.Renommer(p, raison(metier, res.de, curseur))
  Composants.Tenir(p, raison(metier, res.de, curseur), lignes(res))
  local g = UnitGUID("player")
  db().tranches[g] = db().tranches[g] or {}
  local t = { projet = p.id, de = res.de, a = curseur }
  db().tranches[g][metier] = t
  return t
end

-- Crée la tranche du métier d'après la route res (ns.tranche) : un projet « Maîtrise : <métier> de X à Y » tenu ; celui de la
-- tranche déjà là est repris. Rend la tranche, ou nil et la raison.
function ns.trancheCreer(metier, res)
  if not res then return nil, "calcule d'abord la tranche (Calculer)" end
  -- Une route calculée avant un gain de compétence (ou avant la fin d'une tranche) ne fait pas de tranche : elle partirait
  -- du mauvais niveau, ou serait déjà finie.
  local rang
  for _, m in ipairs(ns.metiers()) do if m.nom == metier then rang = m.rang end end
  if res.metier ~= metier or res.de ~= rang then return nil, "ta compétence a changé depuis le calcul : refais Calculer" end
  if #res.fabrications == 0 then return nil, "aucune recette à fabriquer sur cette tranche" end
  local _, p = ns.trancheDe(metier)
  p = p or Composants.NouveauProjet({ name = raison(metier, res.de, res.a) })
  return tenir(p, metier, res, res.a)
end

-- Recalcule depuis la compétence réelle jusqu'à curseur (nil = le même curseur), aux prix du moment ; les choix de case
-- du projet restent (Composants). Rend la nouvelle route, ou nil et la raison.
function ns.trancheRecalculer(metier, curseur)
  local t, p = ns.trancheDe(metier)
  if not t then return nil, "pas de tranche en cours pour ce métier" end
  curseur = curseur or t.a
  local res, err = ns.tranche(nil, metier, curseur)
  if not res then return nil, err end
  if #res.fabrications == 0 then return nil, "aucune recette à fabriquer sur cette tranche" end
  tenir(p, metier, res, curseur)
  return res
end

-- Abandonne : le projet est lâché (il reste dans Composants, ordinaire) et la tranche oubliée.
function ns.trancheAbandonner(metier)
  local t, p = ns.trancheDe(metier)
  if not t then return end
  Composants.Tenir(p, nil)
  db().tranches[UnitGUID("player")][metier] = nil
end

-- L'état de la tranche : { tranche, rang, a, texte « <métier> <compétence> / <curseur> » }, ou nil sans tranche.
-- Lit la compétence par le socle seulement ; au curseur atteint, la tranche se termine (projet lâché, une ligne au chat)
-- et on rend nil.
-- ponytail: le socle relit les métiers toutes les 60 s et ne le signale pas : la fin peut se voir avec une minute de retard.
function ns.trancheEtat(metier)
  local t = ns.trancheDe(metier)
  if not t then return nil end
  local rang
  for _, m in ipairs(ns.metiers()) do if m.nom == metier then rang = m.rang end end
  if not rang then return nil end -- métier pas relevé : on ne devine rien
  if rang >= t.a then
    ns.trancheAbandonner(metier)
    print(("|cffffd100Maîtrise :|r tranche %s terminée (%d)."):format(metier, t.a))
    return nil
  end
  return { tranche = t, rang = rang, a = t.a, texte = ("%s %d / %d"):format(metier, rang, t.a) }
end
