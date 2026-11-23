-- Maîtrise, la tranche tenue (Maitrise#3) : une tranche en cours est un projet de Composants qu'elle tient (lignes
-- fabrication, raison « Maîtrise : <métier> de X à Y »). Ici : le stockage, créer, recalculer, finir, la progression
-- (compétence / curseur : rien d'autre, ni avance ni décompte des fabrications). Pas de fenêtre : testable seule (check.lua).
-- MaitriseDB.tranches[guid][métier] = { projet (identité Composants), de (compétence à la création ou au dernier calcul),
-- a (le curseur), etapes (les lignes de la frise de la route tenue, pour le panneau de la fenêtre de métier : voir
-- ns.etapesFrise, sans l'objectif) } ; une tranche gardée par une version plus ancienne porte encore faites (ignoré) et
-- pas toujours etapes.
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

-- Les lignes de la frise d'une route res (ns.tranche), dans l'ordre : ses fabrications, ses trous ({ de, a, trou }) et ses
-- apprentissages ({ de = niveau, apprendre, … }) à leur niveau, avant l'étape qui les demande (même niveau :
-- l'apprentissage d'abord), puis l'objectif ({ de = res.a, fin }). La frise de la fenêtre et le panneau les montrent.
function ns.etapesFrise(res)
  local etapes = {}
  for _, f in ipairs(res.fabrications) do etapes[#etapes + 1] = f end
  for _, t in ipairs(res.trous) do etapes[#etapes + 1] = { de = t.de, a = t.a, trou = true } end
  for _, a in ipairs(res.apprentissages) do
    local l = {}
    for k, v in pairs(a) do l[k] = v end
    l.de, l.apprendre = a.niveau, true
    etapes[#etapes + 1] = l
  end
  for i, e in ipairs(etapes) do e.ordre = i end
  table.sort(etapes, function(x, y)
    if x.de ~= y.de then return x.de < y.de end
    if (x.apprendre or false) ~= (y.apprendre or false) then return x.apprendre or false end
    return x.ordre < y.ordre
  end)
  etapes[#etapes + 1] = { de = res.a, fin = true }
  return etapes
end

-- Ce que la tranche garde de chaque ligne de la frise (le panneau la redessine sans recalculer).
local GARDE = { "de", "a", "cle", "nom", "fois", "objet", "fourchette", "trou", "apprendre", "source", "prix", "objetPatron" }

-- Tient le projet p avec la route res, au curseur : met la tranche (GUID du connecté) à jour. Rend la tranche.
local function tenir(p, metier, res, curseur)
  -- Le nom du projet porte les niveaux, comme sa raison (liste « Projets » de Composants), et les suit au recalcul.
  Composants.Renommer(p, raison(metier, res.de, curseur))
  Composants.Tenir(p, raison(metier, res.de, curseur), lignes(res))
  local g = UnitGUID("player")
  db().tranches[g] = db().tranches[g] or {}
  local etapes = {}
  for _, e in ipairs(ns.etapesFrise(res)) do
    if not e.fin then
      local l = {}
      for _, k in ipairs(GARDE) do l[k] = e[k] end
      etapes[#etapes + 1] = l
    end
  end
  local t = { projet = p.id, de = res.de, a = curseur, etapes = etapes }
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
