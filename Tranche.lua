-- Maîtrise, la tranche tenue (Maitrise#3) : une tranche en cours est un projet de Composants qu'elle tient (lignes
-- fabrication, raison « Maîtrise : <métier> de X à Y »). Ici : le stockage, créer, recalculer, finir, la progression
-- (compétence / curseur : rien d'autre, ni avance ni décompte des fabrications). Pas de fenêtre : testable seule (check.lua).
-- MaitriseDB.tranches[guid][métier] = { projet (identité Composants), de (compétence à la création ou au dernier calcul),
-- a (le curseur) } ; une tranche gardée par une version plus ancienne porte encore faites et etapes (ignorés).
-- Au plus une par personnage et par métier ; celle d'un autre de mes personnages se prépare depuis le connecté (Maitrise#5). Rien ne se recalcule seul (pas d'état deviné) : seul un clic le fait.
local _, ns = ...

local function db()
  MaitriseDB = MaitriseDB or {}
  MaitriseDB.tranches = MaitriseDB.tranches or {}
  return MaitriseDB
end

-- Le prénom d'un autre de mes personnages (Maitrise#5), nil pour le connecté.
function ns.prenomAutre(guid)
  if not guid or guid == UnitGUID("player") then return nil end
  local p = AzerothCommune.Personnage(guid)
  return p and p.nom and p.nom:match("^(%S+)") or guid
end

-- La raison (et le nom) du projet ; pour un autre de mes personnages, son prénom devant (« Maîtrise : Riwanon, Forge de 49 à
-- 59 ») : on voit dans Composants pour qui on achète.
local function raison(metier, de, a, guid)
  local qui = ns.prenomAutre(guid)
  return ("Maîtrise : %s%s de %d à %d"):format(qui and (qui .. ", ") or "", metier, de, a)
end

-- La tranche (GUID, nil = le connecté) d'un métier et son projet ; un projet supprimé dans Composants : tranche oubliée.
function ns.trancheDe(metier, guid)
  guid = guid or UnitGUID("player")
  local t = (db().tranches[guid] or {})[metier]
  if not t then return nil end
  local p = Composants.Projet(t.projet)
  if not p then db().tranches[guid][metier] = nil return nil end
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
-- l'apprentissage d'abord), les outils qui manquent ({ de = niveau, outil, nom, objets, inconnu : sacs pas relevés },
-- AzerothCommune#71) comme eux, puis l'objectif ({ de = res.a, fin }). La frise de la fenêtre les montre.
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
  -- Un outil qui manque (AzerothCommune#71) : une ligne « Outil » au niveau de sa première étape, comme un apprentissage.
  for _, o in ipairs(res.outils or {}) do
    if not o.a then etapes[#etapes + 1] = { de = o.niveau, outil = true, nom = o.nom, objets = o.objets, inconnu = o.a == nil } end
  end
  for i, e in ipairs(etapes) do e.ordre = i end
  table.sort(etapes, function(x, y)
    if x.de ~= y.de then return x.de < y.de end
    local ax, ay = x.apprendre or x.outil or false, y.apprendre or y.outil or false
    if ax ~= ay then return ax end
    return x.ordre < y.ordre
  end)
  etapes[#etapes + 1] = { de = res.a, fin = true }
  return etapes
end

-- Tient le projet p avec la route res, au curseur : met la tranche (du personnage de la route, res.guid) à jour. Rend la tranche.
local function tenir(p, metier, res, curseur)
  -- Le nom du projet porte les niveaux, comme sa raison (colonne des projets de Composants), et les suit au recalcul.
  Composants.Renommer(p, raison(metier, res.de, curseur, res.guid))
  Composants.Tenir(p, raison(metier, res.de, curseur, res.guid), lignes(res))
  local g = res.guid
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
  for _, m in ipairs(ns.metiers(res.guid)) do if m.nom == metier then rang = m.rang end end
  if res.metier ~= metier or res.de ~= rang then return nil, "ta compétence a changé depuis le calcul : refais Calculer" end
  if #res.fabrications == 0 then return nil, "aucune recette à fabriquer sur cette tranche" end
  local _, p = ns.trancheDe(metier, res.guid)
  p = p or Composants.NouveauProjet({ name = raison(metier, res.de, res.a, res.guid) })
  return tenir(p, metier, res, res.a)
end

-- Recalcule depuis la compétence réelle jusqu'à curseur (nil = le même curseur), aux prix du moment ; les choix de case
-- du projet restent (Composants). guid : le personnage (nil = le connecté). Rend la nouvelle route, ou nil et la raison.
function ns.trancheRecalculer(metier, curseur, guid)
  local t, p = ns.trancheDe(metier, guid)
  if not t then return nil, "pas de tranche en cours pour ce métier" end
  curseur = curseur or t.a
  local res, err = ns.tranche(guid, metier, curseur)
  if not res then return nil, err end
  if #res.fabrications == 0 then return nil, "aucune recette à fabriquer sur cette tranche" end
  tenir(p, metier, res, res.a) -- le curseur, ramené au plafond du personnage s'il le dépassait
  return res
end

-- Abandonne : le projet est lâché (il reste dans Composants, ordinaire) et la tranche oubliée.
function ns.trancheAbandonner(metier, guid)
  guid = guid or UnitGUID("player")
  local t, p = ns.trancheDe(metier, guid)
  if not t then return end
  Composants.Tenir(p, nil)
  db().tranches[guid][metier] = nil
end

-- L'état de la tranche du personnage (GUID, nil = le connecté) : { tranche, rang, a, texte « <métier> <compétence> /
-- <curseur> », le prénom devant pour un autre personnage }, ou nil sans tranche.
-- Lit la compétence par le socle seulement (celle d'un autre personnage : son dernier relevé) ; au curseur atteint, la
-- tranche se termine (projet lâché, une ligne au chat) et on rend nil.
function ns.trancheEtat(metier, guid)
  local t = ns.trancheDe(metier, guid)
  if not t then return nil end
  local rang
  for _, m in ipairs(ns.metiers(guid)) do if m.nom == metier then rang = m.rang end end
  if not rang then return nil end -- métier pas relevé : on ne devine rien
  if rang >= t.a then
    ns.trancheAbandonner(metier, guid)
    print(("|cffffd100Maîtrise :|r tranche %s terminée (%d)."):format(metier, t.a))
    return nil
  end
  local qui = ns.prenomAutre(guid)
  return { tranche = t, rang = rang, a = t.a, texte = ("%s%s %d / %d"):format(qui and (qui .. ", ") or "", metier, rang, t.a) }
end

-- Le socle relit les métiers sur un gain de compétence et le signale (AzerothCommune#69) : chaque tranche du connecté est
-- relue aussitôt et se termine au curseur atteint, fenêtre de Maîtrise ouverte ou non.
function ns.tranchesSuivre()
  for metier in pairs(db().tranches[UnitGUID("player")] or {}) do ns.trancheEtat(metier) end
end
AzerothCommune:QuandReleve("métiers et compétences", function() ns.tranchesSuivre() end)
