-- Vérification hors jeu (non chargée par la TOC) : luajit Maitrise/check.lua, depuis le dossier des add-ons.
-- Le socle Azeroth Commune est chargé avant, comme dans le jeu : ses SavedVariables servent de données (métiers du perso,
-- cours de l'HV, marchands, objets) et sa réserve des recettes (privée, acns.recettesReserve) est celle de chaque scénario.
-- Tout passe par la fonction publique Maitrise.Tranche.
local noop = function() end
local stubMT = { __index = function() return noop end }
CreateFrame = function() return setmetatable({}, stubMT) end
SlashCmdList, StaticPopupDialogs, UISpecialFrames = {}, {}, {}
C_Timer = { After = noop, NewTicker = noop }
C_Item = { GetItemInfo = noop, GetItemIconByID = noop }
date, time = os.date, os.time
GetTime = function() return 0 end
GetCoinTextureString = function(c) return c .. "c" end
UnitFactionGroup = function() return "Alliance" end
geterrorhandler = function() return function(e) error(e, 0) end end
local MOI = "Player-6942-0000000E"
UnitGUID = function(u) if u == "player" then return MOI end end
AzerothCommuneDB, AzerothCommuneItems, AzerothCommuneMarket = { recipes = {}, chars = {}, lots = {} }, { items = {} }, {}
local acns = {}
for f in io.open("AzerothCommune/AzerothCommune.toc"):read("*a"):gmatch("([%w_]+)%.lua") do
  if f ~= "VendorData" and f ~= "RecettesReserve" and f ~= "CatalogueObjets" then assert(loadfile("AzerothCommune/" .. f .. ".lua"))("AzerothCommune", acns) end
end
-- Composants (dépôt voisin, chargé avant Maîtrise comme dans le jeu) : la tranche y tient un projet.
local cns = {}
for f in io.open("Composants/Composants.toc"):read("*a"):gmatch("([%w_]+)%.lua") do assert(loadfile("Composants/" .. f .. ".lua"))("Composants", cns) end
assert(Composants and Composants.Tenir, "le global Composants posé")
local ns = {}
for f in io.open("Maitrise/Maitrise.toc"):read("*a"):gmatch("([%w_]+)%.lua") do assert(loadfile("Maitrise/" .. f .. ".lua"))("Maitrise", ns) end
assert(Maitrise and Maitrise.Tranche, "le global Maitrise posé")

local M, B, TIGE = 2770, 2840, 2841 -- minerai, barre, tige
-- Un scénario : recettes de la réserve { clé = { objet, nom, { composant, qté, … }, apprendre, jaune, gris, source, patron,
-- recharge, condition, objet patron } } (métier « Forge »), paliers de l'HV { [id] = { { prix, qté }, … } }, marchands { [id] = prix }, revente
-- au marchand { [id] = prix }, compétence actuelle du perso connecté.
local function scenario(t)
  local r = {}
  for k, x in pairs(t.recettes) do
    r[k] = { x[1], 1, 1, "Forge", x[2], x[3], x[4], x[5], x[6], x[7] or "maître", "source externe", x[8] or 0, x[9] or 0, x[10], x[11],
      t.marchandsPatron and t.marchandsPatron[k], nil, nil, t.temps and t.temps[k], t.outils and t.outils[k] }
  end
  acns.recettesReserve, acns.recettesOutils = r, t.tableOutils
  local items = {}
  for id, paliers in pairs(t.hv or {}) do
    local tiers = {}
    for _, p in ipairs(paliers) do tiers[#tiers + 1] = { price = p[1], qty = p[2] } end
    items[id] = { tiers = tiers }
  end
  AzerothCommuneMarket = next(items) and { ["6942-Alliance"] = { scanned = "22/11 21:00", time = os.time(), items = items } } or {}
  local v = {}
  for id, prix in pairs(t.marchands or {}) do v[#v + 1] = { id = id, price = prix, stack = 1 } end
  AzerothCommuneDB.vendors = { [1] = { items = v } }
  AzerothCommuneItems.items = {}
  for id, prix in pairs(t.revente or {}) do AzerothCommuneItems.items[id] = { name = "#" .. id, price = prix } end
  AzerothCommuneDB.chars = { [MOI] = { nom = "Moi Dupont", professions = { { name = "Forge", rank = t.rang, max = t.max or 300 } },
    recipes = t.connues and { Forge = { rank = t.rang, max = 300, known = t.connues } } or nil } }
  AzerothCommuneDB.chars[MOI].bags = t.sacs
  AzerothCommuneDB.chars[MOI].character = t.niveau and { level = t.niveau }
  AzerothCommuneDB.trainers = t.maitres
  if t.refus then return Maitrise.Tranche(nil, "Forge", t.curseur) end
  return assert(Maitrise.Tranche(nil, "Forge", t.curseur))
end
local function achat(res, id)
  for _, a in ipairs(res.achats) do if a.id == id then return a end end
end
local function noms(res)
  local t = {}
  for _, f in ipairs(res.fabrications) do t[#t + 1] = ("%s %d-%d x%d"):format(f.nom, f.de, f.a, f.fois) end
  return table.concat(t, ", ")
end

-- La recette la moins chère par point : Lame (2 minerais) contre Bouclier (3), toujours orange de 1 à 10.
local res = scenario({ rang = 1, curseur = 10, marchands = { [M] = 10 }, recettes = {
  [1] = { 5001, "Lame", { M, 2 }, 1, 10, 20 },
  [2] = { 5002, "Bouclier", { M, 3 }, 1, 10, 20 } } })
assert(#res.fabrications == 1 and res.fabrications[1].nom == "Lame" and res.fabrications[1].fois == 9, noms(res))
assert(res.total == 180 and res.revente == 0 and #res.trous == 0, "9 lames, 18 minerais : " .. res.total)
assert(res.sansHV and res.scan == nil, "aucun cours de l'HV : marchands seuls, signalé")

-- La revente au marchand est déduite : le Bouclier se revend 25, son coût net (30 − 25) bat la Lame (20).
res = scenario({ rang = 1, curseur = 10, marchands = { [M] = 10 }, revente = { [5002] = 25 }, recettes = {
  [1] = { 5001, "Lame", { M, 2 }, 1, 10, 20 },
  [2] = { 5002, "Bouclier", { M, 3 }, 1, 10, 20 } } })
assert(res.fabrications[1].nom == "Bouclier" and res.total == 270 and res.revente == 9 * 25, noms(res) .. " " .. res.revente)

-- Fabriquer bat acheter : la barre au marchand 100, fondue d'un minerai à 10 (Fondre, gris dès 2) : on achète le minerai.
res = scenario({ rang = 5, curseur = 10, marchands = { [M] = 10, [B] = 100 }, recettes = {
  [1] = { 5001, "Lame", { B, 1 }, 1, 10, 20 },
  [3] = { B, "Fondre", { M, 1 }, 1, 1, 2 } } })
assert(not achat(res, B) and achat(res, M).qty == 5 and res.total == 50, "barres fondues, pas achetées : " .. res.total)

-- Un intermédiaire fabriqué resert : les tiges faites pour monter de 1 à 10 servent à la Grille de 10 à 20, pas rachetées.
res = scenario({ rang = 1, curseur = 20, marchands = { [M] = 10, [TIGE] = 100 }, revente = { [TIGE] = 1 }, recettes = {
  [4] = { TIGE, "Tige", { M, 1 }, 1, 5, 10 },
  [5] = { 5005, "Grille", { TIGE, 1 }, 10, 20, 30 } } })
assert(res.fabrications[1].nom == "Tige" and res.fabrications[#res.fabrications].nom == "Grille", noms(res))
assert(not achat(res, TIGE) and res.revente > 0, "tiges réemployées, le surplus revendu")

-- Un palier plus cher est atteint quand la quantité monte : 5 minerais à 10, puis à 30.
res = scenario({ rang = 1, curseur = 11, hv = { [M] = { { 10, 5 }, { 30, 100 } } }, recettes = {
  [1] = { 5001, "Lame", { M, 1 }, 1, 20, 30 } } })
assert(achat(res, M).qty == 10 and res.total == 5 * 10 + 5 * 30, "paliers de l'HV : " .. res.total)
assert(not res.sansHV and res.scan == "22/11 21:00", "date du scan de l'HV")

-- Les recettes à recharge ou de source inconnue sont exclues ; un patron vendu compte une fois dans le total.
res = scenario({ rang = 1, curseur = 10, marchands = { [M] = 10 }, recettes = {
  [6] = { 5006, "Inconnue", { M, 1 }, 1, 10, 20, "inconnue" },
  [7] = { 5007, "Lunaire", { M, 1 }, 1, 10, 20, "patron vendu", 0, 3600 },
  [8] = { 5008, "Patron", { M, 2 }, 1, 10, 20, "patron vendu", 500 } } })
assert(#res.fabrications == 1 and res.fabrications[1].nom == "Patron", noms(res))
assert(res.patrons == 500 and res.total == 9 * 2 * 10 + 500, "patron compté une fois : " .. res.total)

-- Patron à l'HV (Maitrise#15) : une recette « inconnue » dont le patron (7001) est à l'HV est prise, au prix d'UN patron
-- (palier de 1) ; sans le patron à l'HV, ou sans objet patron, ou avec une condition, elle est écartée. Un patron vendu moins cher
-- à l'HV que chez le marchand prend le prix de l'HV, plus cher il garde celui du marchand.
local RH = { [1] = { 5001, "Lame", { M, 4 }, 1, 10, 20 }, [9] = { 5009, "Butin", { M, 1 }, 1, 10, 20, "inconnue", nil, nil, nil, 7001 } }
res = scenario({ rang = 1, curseur = 10, marchands = { [M] = 10 }, recettes = RH })
assert(res.fabrications[1].nom == "Lame" and not res.fabrications[1].patronHV, "patron pas à l'HV : écartée : " .. noms(res))
res = scenario({ rang = 1, curseur = 10, marchands = { [M] = 10 }, recettes = RH, hv = { [7001] = { { 100, 1 }, { 900, 1 } } } })
assert(res.fabrications[1].nom == "Butin" and res.fabrications[1].patronHV and res.fabrications[1].patron == 100
  and res.patrons == 100 and res.total == 9 * 10 + 100, "patron à l'HV compté (un seul, premier palier) : " .. res.total .. " " .. noms(res))
RH[9][11] = nil
res = scenario({ rang = 1, curseur = 10, marchands = { [M] = 10 }, recettes = RH, hv = { [7001] = { { 100, 1 } } } })
assert(res.fabrications[1].nom == "Lame", "sans objet patron : écartée : " .. noms(res))
RH[9][11], RH[9][10] = 7001, "réputation : Aube d'argent"
res = scenario({ rang = 1, curseur = 10, marchands = { [M] = 10 }, recettes = RH, hv = { [7001] = { { 100, 1 } } } })
assert(res.fabrications[1].nom == "Lame", "patron à l'HV mais condition : écartée : " .. noms(res))
local RV = { [1] = { 5001, "Lame", { M, 8 }, 1, 10, 20 }, [9] = { 5009, "Vendu", { M, 1 }, 1, 10, 20, "patron vendu", 500, nil, nil, 7001 } }
res = scenario({ rang = 1, curseur = 10, marchands = { [M] = 10 }, recettes = RV, hv = { [7001] = { { 100, 1 } } } })
assert(res.fabrications[1].patronHV and res.patrons == 100, "patron vendu moins cher à l'HV : prix de l'HV : " .. noms(res))
res = scenario({ rang = 1, curseur = 10, marchands = { [M] = 10 }, recettes = RV, hv = { [7001] = { { 800, 1 } } } })
assert(not res.fabrications[1].patronHV and res.patrons == 500, "patron vendu plus cher à l'HV : prix du marchand : " .. noms(res))
res = scenario({ rang = 1, curseur = 10, marchands = { [M] = 10 }, recettes = RV })
assert(res.patrons == 500 and not res.fabrications[1].patronHV, "patron vendu, pas à l'HV : prix du marchand : " .. noms(res))
-- Un patron vendu à prix inconnu (Maitrise#21) n'est pas gratuit : écarté, sauf si son patron est à l'HV.
RV[9][8] = nil
res = scenario({ rang = 1, curseur = 10, marchands = { [M] = 10 }, recettes = RV })
assert(res.fabrications[1].nom == "Lame" and res.patrons == 0, "patron vendu à prix inconnu : écarté : " .. noms(res))
res = scenario({ rang = 1, curseur = 10, marchands = { [M] = 10 }, recettes = RV, hv = { [7001] = { { 100, 1 } } } })
assert(res.fabrications[1].nom == "Vendu" and res.fabrications[1].patronHV and res.patrons == 100,
  "patron vendu à prix inconnu mais à l'HV : prix de l'HV : " .. noms(res))
RV[9][8] = 500
-- Une recette déjà connue est gardée quelle que soit sa source, apprise pour 0 et sans patron à l'HV.
res = scenario({ rang = 1, curseur = 10, marchands = { [M] = 10 }, recettes = RH, connues = { [9] = true }, hv = { [7001] = { { 100, 1 } } } })
assert(res.fabrications[1].nom == "Butin" and not res.fabrications[1].patronHV and res.patrons == 0 and res.total == 9 * 10,
  "recette inconnue de source mais déjà connue : prix 0, pas de patron à l'HV : " .. res.total .. " " .. noms(res))
RH[9][7] = "retirée"
res = scenario({ rang = 1, curseur = 10, marchands = { [M] = 10 }, recettes = RH, connues = { [9] = true } })
assert(res.fabrications[1].nom == "Butin" and res.patrons == 0, "recette retirée mais connue : gardée : " .. noms(res))
res = scenario({ rang = 1, curseur = 10, marchands = { [M] = 10 }, recettes = RH })
assert(res.fabrications[1].nom == "Lame", "recette retirée pas connue : écartée : " .. noms(res))
print("Maîtrise : patron à l'HV OK")

-- Un trou : aucune recette ne donne de point de 20 à 25.
res = scenario({ rang = 1, curseur = 25, marchands = { [M] = 10 }, recettes = {
  [1] = { 5001, "Lame", { M, 1 }, 1, 10, 20 } } })
assert(#res.trous == 1 and res.trous[1].de == 20 and res.trous[1].a == 25, "trou de 20 à 25")

-- Un composant sans prix écarte la recette et se signale.
res = scenario({ rang = 1, curseur = 5, marchands = { [M] = 10 }, recettes = {
  [1] = { 5001, "Lame", { M, 1 }, 1, 10, 20 },
  [9] = { 5009, "Mystère", { 9999, 1 }, 1, 10, 20 } } })
assert(res.fabrications[1].nom == "Lame" and res.sansPrix[1] == 9999, "composant sans prix signalé")

-- Le curseur : au-dessus de la compétence actuelle, n'importe quel niveau ; un métier pas relevé se dit.
local pas, pourquoi = Maitrise.Tranche(nil, "Forge", 1) -- compétence actuelle : 1
assert(pas == nil and pourquoi:find("dépasser", 1, true), tostring(pourquoi))
pas, pourquoi = Maitrise.Tranche(nil, "Couture", 100)
assert(pas == nil and pourquoi:find("pas relevé", 1, true), tostring(pourquoi))
print("Maîtrise : tranche (moins chère, revente, fabriquer, réemploi, paliers, exclusions, trous, sans prix) OK")

-- Temps de fabrication (AzerothCommune#70) : par étape, fabrications × temps d'incantation ; le total est leur somme.
-- Outils (AzerothCommune#71) : chacun à sa première étape, « a » d'après les sacs relevés par le socle ; sacs pas relevés : nil.
local OUTILS = { [162] = { "Marteau de forgeron", { 5956, 260811 } }, [373] = { "Bâtonnet runique en cuivre", { 6218 } } }
local function tigeGrille(sacs)
  return scenario({ rang = 1, curseur = 20, marchands = { [M] = 10, [TIGE] = 100 }, revente = { [TIGE] = 1 }, recettes = {
    [4] = { TIGE, "Tige", { M, 1 }, 1, 5, 10 },
    [5] = { 5005, "Grille", { TIGE, 1 }, 10, 20, 30 } }, temps = { [4] = 3, [5] = 5.5 }, outils = { [4] = { 162 }, [5] = { 162, 373 } },
    tableOutils = OUTILS, sacs = sacs })
end
res = tigeGrille({ Backpack = { size = 16, items = { { id = 260811, count = 1 } } } })
local somme = 0
for _, f in ipairs(res.fabrications) do
  assert(f.temps == f.fois * (f.nom == "Tige" and 3 or 5.5), f.nom .. " : " .. tostring(f.temps))
  somme = somme + f.temps
end
assert(res.temps == somme and somme > 0, "le total est la somme des étapes : " .. tostring(res.temps))
assert(#res.outils == 2 and res.outils[1].nom == "Marteau de forgeron" and res.outils[1].niveau == 1 and res.outils[1].a == true,
  "le couteau de l'armée gnome dans les sacs : le marteau, on l'a")
assert(res.outils[2].nom == "Bâtonnet runique en cuivre" and res.outils[2].niveau == res.fabrications[#res.fabrications].de
  and res.outils[2].a == false, "le bâtonnet manque, au niveau de la Grille")
local manque = {}
for _, e in ipairs(ns.etapesFrise(res)) do if e.outil then manque[#manque + 1] = e end end
assert(#manque == 1 and manque[1].nom == "Bâtonnet runique en cuivre" and manque[1].de == res.outils[2].niveau, "une ligne Outil, pour celui qui manque")
res = tigeGrille(nil)
assert(res.outils[1].a == nil, "sacs pas relevés : on ne devine pas")
acns.recettesOutils = nil
print("Maîtrise : temps de fabrication et outils OK")

-- Règle des 20 % (Maitrise#9) : Gros (7 minerais, jaune dès 20, gris à 40) et Fin (1 minerai, jaune dès 10, gris à 30).
-- À 28, Fin ne donne qu'un point sur 10 (10 minerais le point) contre 0,6 pour Gros (11,7 le point) : sans la règle, Fin
-- gagne ; avec, Gros couvre le point. Sans Gros, Fin reste (pas de trou).
local R20 = { [1] = { 5001, "Fin", { M, 1 }, 1, 10, 30 }, [2] = { 5002, "Gros", { M, 7 }, 1, 20, 40 } }
res = scenario({ rang = 28, curseur = 29, marchands = { [M] = 10 }, recettes = R20 })
assert(#res.fabrications == 1 and res.fabrications[1].nom == "Gros", "point sous 20 % évité : " .. noms(res))
res = scenario({ rang = 28, curseur = 29, marchands = { [M] = 10 }, recettes = { [1] = R20[1] } })
assert(#res.fabrications == 1 and res.fabrications[1].nom == "Fin" and #res.trous == 0, "seule recette gardée : " .. noms(res))
-- Un point à 20 % tout juste reste à la moins chère : à 26, Fin donne 0,2 (5 minerais le point) contre 0,7 pour Gros (10).
res = scenario({ rang = 26, curseur = 27, marchands = { [M] = 10 }, recettes = R20 })
assert(res.fabrications[1].nom == "Fin", "à 20 % la règle ne joue pas : " .. noms(res))
print("Maîtrise : règle des 20 % (évité si une autre recette couvre, gardé sinon) OK")

-- Conditions d'accès (AzerothCommune#67) : une recette à spécialisation n'est prise que si le personnage la connaît ; le prix
-- du maître relevé (AzerothCommune#72) compte pour une recette de maître. « Tribal » (1 minerai) contre « Lame » (2).
local RC = { [1] = { 5001, "Lame", { M, 2 }, 1, 10, 20 }, [2] = { 5002, "Tribal", { M, 1 }, 1, 10, 20, nil, nil, nil, "spécialisation : travail du cuir tribal" } }
res = scenario({ rang = 1, curseur = 10, marchands = { [M] = 10 }, recettes = RC })
assert(res.fabrications[1].nom == "Lame", "recette à condition, pas connue : écartée : " .. noms(res))
res = scenario({ rang = 1, curseur = 10, marchands = { [M] = 10 }, recettes = RC, connues = { [2] = true } })
assert(res.fabrications[1].nom == "Tribal", "recette à condition déjà connue : permise : " .. noms(res))
-- Le maître vend « Lame » 500 : la Lame coûte 9 × 20 + 500 = 680, le Bouclier (3 minerais, sans prix) 270 : il gagne.
local RM = { [1] = { 5001, "Lame", { M, 2 }, 1, 10, 20 }, [3] = { 5003, "Bouclier", { M, 3 }, 1, 10, 20 } }
res = scenario({ rang = 1, curseur = 10, marchands = { [M] = 10 }, recettes = RM })
assert(res.fabrications[1].nom == "Lame", "sans maître relevé : la Lame : " .. noms(res))
res = scenario({ rang = 1, curseur = 10, marchands = { [M] = 10 }, recettes = RM,
  maitres = { [1] = { services = { { name = "Lame", skill = "Forge", skill_rank = 1, cost = 500 } } } } })
assert(res.fabrications[1].nom == "Bouclier" and res.patrons == 0, "le prix du maître compte : " .. noms(res))
AzerothCommuneDB.trainers = nil
print("Maîtrise : conditions d'accès et prix du maître OK")

-- Pas d'aller-retour court (Maitrise#17) : « Clou » (de 5 à 7) coupe « Lame » (de 1 à 10). Économie minime (10 pc le point) :
-- la Lame tout du long ; grosse économie (19 pa le point) : le Clou reste.
local CLOU = 2776
local RA = { [1] = { 5001, "Lame", { M, 2 }, 1, 10, 20 }, [4] = { 5004, "Clou", { CLOU, 1 }, 5, 7, 8 } }
res = scenario({ rang = 1, curseur = 10, marchands = { [M] = 1000, [CLOU] = 1990 }, recettes = RA })
assert(#res.fabrications == 1 and res.fabrications[1].nom == "Lame", "économie minime : pas d'aller-retour : " .. noms(res))
res = scenario({ rang = 1, curseur = 10, marchands = { [M] = 1000, [CLOU] = 100 }, recettes = RA })
assert(#res.fabrications == 3 and res.fabrications[2].nom == "Clou", "grosse économie : le Clou reste : " .. noms(res))
print("Maîtrise : pas d'aller-retour court OK")

-- Plages de couleur et fourchettes (Maitrise#11), seuils du client : orange sous le jaune, vert au milieu jaune/gris.
-- « Orange » 1-10-20 → 10 orange ; « Longue » (jaune 10, gris 50) : de 10 à 30 jaune, de 30 à 50 vert.
local function etape(r, nom) for _, f in ipairs(r.fabrications) do if f.nom == nom then return f end end end
res = scenario({ rang = 1, curseur = 10, marchands = { [M] = 10 }, recettes = { [1] = { 5001, "Orange", { M, 1 }, 1, 10, 20 } } })
local o = res.fabrications[1]
assert(o.fourchette == nil and not o.incertaine, "étape orange : pas de fourchette")
assert(#o.plages == 1 and o.plages[1].couleur == "orange" and o.plages[1].de == 1 and o.plages[1].a == 10)
local LONGUE = { [1] = { 5001, "Longue", { M, 1 }, 1, 10, 50 } }
res = scenario({ rang = 5, curseur = 50, marchands = { [M] = 10 }, recettes = LONGUE })
local l = etape(res, "Longue")
local pl = l.plages
assert(#pl == 3 and pl[1].couleur == "orange" and pl[1].a == 10 and pl[2].couleur == "jaune" and pl[2].a == 30
  and pl[3].couleur == "vert" and pl[3].de == 30 and pl[3].a == 50, "plages : orange, jaune, vert (30 = milieu)")
assert(l.fourchette and l.fourchette.bas <= l.fois and l.fois <= l.fourchette.haut, "la fourchette encadre la moyenne")
-- Surtout vert : incertaine, plus large qu'une étape jaune de même longueur (20 points).
res = scenario({ rang = 30, curseur = 50, marchands = { [M] = 10 }, recettes = LONGUE })
local vert = etape(res, "Longue")
assert(vert.incertaine and #vert.plages == 1 and vert.plages[1].couleur == "vert", "étape verte incertaine")
res = scenario({ rang = 10, curseur = 30, marchands = { [M] = 10 }, recettes = LONGUE })
local jaune = etape(res, "Longue")
assert(not jaune.incertaine and jaune.plages[1].couleur == "jaune", "étape jaune sûre")
assert(vert.fourchette.haut - vert.fourchette.bas > jaune.fourchette.haut - jaune.fourchette.bas, "le vert est plus large")
-- Contre la convolution exacte des lois géométriques (la sonde research/montee/variance.lua tire au sort, 10 000 fois) :
-- à une fabrication près, ici 20 points verts (de 50 % à 10 %).
local ps = {}
for s = 30, 49 do ps[#ps + 1] = (50 - s) / 40 end
local bas, haut = ns.fourchette(ps)
local d = { [0] = 1 }
for _, p in ipairs(ps) do
  local nd = {}
  for k, v in pairs(d) do local w = p for j = 1, 600 do nd[k + j] = (nd[k + j] or 0) + v * w; w = w * (1 - p); if w < 1e-12 then break end end end
  d = nd
end
local c, eb, eh = 0
for k = 0, 1000 do c = c + (d[k] or 0); if not eb and c >= 0.1 then eb = k end; if not eh and c >= 0.9 then eh = k end end
assert(math.abs(bas - eb) <= 1 and math.abs(haut - eh) <= 1, ("fourchette %d-%d, exacte %d-%d"):format(bas, haut, eb, eh))
print("Maîtrise : plages de couleur et fourchettes OK")

-- Le résumé (Maitrise#12) : le coût « une fois sur dix » dépasse le net moyen dès qu'une étape n'est pas orange (somme des
-- 90e centiles étape par étape, un majorant) et l'égale quand tout est orange ; le net par fabrication de chaque étape.
res = scenario({ rang = 1, curseur = 10, marchands = { [M] = 10 }, recettes = { [1] = { 5001, "Orange", { M, 1 }, 1, 10, 20 } } })
assert(res.net == res.total - res.revente and res.netUneSurDix == res.net, "tout orange : une fois sur dix = le net moyen")
res = scenario({ rang = 5, curseur = 50, marchands = { [M] = 10 }, recettes = LONGUE })
assert(res.netUneSurDix > res.net, "étape non orange : une fois sur dix au-dessus du net moyen")
assert(etape(res, "Longue").net == 10, "net par fabrication : un minerai à 10 : " .. etape(res, "Longue").net)
-- Net par fabrication = composants − revente du produit au marchand (le produit 5002 revendu 4 : 10 − 4).
res = scenario({ rang = 1, curseur = 10, marchands = { [M] = 10 }, revente = { [5002] = 4 }, recettes = { [1] = { 5002, "Lame", { M, 1 }, 1, 10, 20 } } })
assert(res.fabrications[1].net == 6, "net 10 − 4 : " .. res.fabrications[1].net)
print("Maîtrise : résumé (une fois sur dix, net par fabrication) OK")

-- Les apprentissages (Maitrise#13) : « A » (maître, 500) de 1 à 10, « B » (patron vendu, 300) à partir de 10, « C » (connue) ;
-- chaque recette à apprendre, à son niveau, avec sa source et son prix ; la connue n'a pas de ligne.
local RP = { [1] = { 5001, "A", { M, 3 }, 1, 10, 20 }, [2] = { 5002, "B", { M, 1 }, 10, 20, 30, "patron vendu", 300 } }
local MAITRE = { [1] = { services = { { name = "A", skill = "Forge", skill_rank = 1, cost = 500 } } } }
res = scenario({ rang = 1, curseur = 30, marchands = { [M] = 10 }, recettes = RP, maitres = MAITRE })
local ap = res.apprentissages
assert(#ap == 2, #ap)
assert(ap[1].nom == "A" and ap[1].niveau == 1 and ap[1].source == "Maître" and ap[1].prix == 500, "A : maître, 500 : " .. tostring(ap[1].prix))
assert(ap[2].nom == "B" and ap[2].niveau == 10 and ap[2].source == "Patron" and ap[2].prix == 300, "B : patron, 300, au niveau 10 : " .. ap[2].niveau)
assert(res.patrons == 800, "le total compte les deux : " .. res.patrons)
res = scenario({ rang = 1, curseur = 30, marchands = { [M] = 10 }, recettes = RP, maitres = MAITRE, connues = { [2] = true } })
assert(#res.apprentissages == 1 and res.apprentissages[1].nom == "A", "B connue : pas de ligne")
res = scenario({ rang = 1, curseur = 30, marchands = { [M] = 10 }, recettes = RP })
assert(res.apprentissages[1].nom == "A" and res.apprentissages[1].prix == nil, "maître sans prix relevé : prix inconnu")
-- Un patron à l'HV : source « Patron à l'HV », l'objet patron pour la bulle et les clics.
res = scenario({ rang = 1, curseur = 10, marchands = { [M] = 10 }, hv = { [7001] = { { 100, 1 } } },
  recettes = { [1] = RH[1], [9] = { 5009, "Butin", { M, 1 }, 1, 10, 20, "inconnue", nil, nil, nil, 7001 } } })
assert(res.apprentissages[1].nom == "Butin" and res.apprentissages[1].source == "Patron à l'HV" and res.apprentissages[1].prix == 100
  and res.apprentissages[1].objetPatron == 7001, "patron à l'HV")
-- Un maître relevé qui enseigne gratis : prix 0 connu, pas « prix inconnu » (relecture de la PR #19).
res = scenario({ rang = 1, curseur = 10, marchands = { [M] = 10 }, recettes = { [1] = { 5001, "Lame", { M, 2 }, 1, 10, 20 } },
  maitres = { [1] = { services = { { name = "Lame", skill = "Forge", skill_rank = 1, cost = 0 } } } } })
AzerothCommuneDB.trainers = nil
assert(res.apprentissages[1] and res.apprentissages[1].prix == 0, "prix de maître relevé à 0 : connu")
print("Maîtrise : apprentissages (niveau, source, prix, connues exclues) OK")

-- Le curseur plafonné par le rang que le personnage peut débloquer à son niveau (Maitrise#4) : Compagnon au niveau 10,
-- Expert au 20, Artisan au 35 ; la raison est rendue. Niveau pas relevé : pas de plafond deviné (300).
local LAME = { [1] = { 5001, "Lame", { M, 1 }, 1, 400, 401, "d'emblée" } } -- orange de 1 à 400, connue d'emblée
res = scenario({ rang = 140, max = 150, niveau = 25, curseur = 260, marchands = { [M] = 10 }, recettes = LAME })
assert(res.a == 225 and res.plafond == 225 and res.raisonPlafond == "225 max : Artisan au niveau 35", res.a .. " " .. tostring(res.raisonPlafond))
res = scenario({ rang = 140, max = 150, niveau = 35, curseur = 260, marchands = { [M] = 10 }, recettes = LAME })
assert(res.a == 260 and res.raisonPlafond == nil, "niveau 35 : pas de plafond sous 300")
res = scenario({ rang = 140, max = 150, curseur = 260, marchands = { [M] = 10 }, recettes = LAME })
assert(res.a == 260, "niveau pas relevé : rien de deviné")
pas, pourquoi = scenario({ rang = 75, max = 75, niveau = 8, curseur = 80, marchands = { [M] = 10 }, recettes = LAME, refus = true })
assert(pas == nil and pourquoi == "75 max : Compagnon au niveau 10", tostring(pourquoi))
assert(select(2, ns.plafondDe()) == "75 max : Compagnon au niveau 10" and ns.plafondDe() == 75)

-- Les rangs à apprendre (Maitrise#4) : de 60 (plafond 75) à 160, Compagnon (dès 60, le maître l'enseigne à 50) et Expert (à 125),
-- au prix relevé chez le maître (le moins cher ; un service du métier sans objet, à la compétence du rang) ; compté dans le total.
local MAITRES_RANG = { [1] = { services = {
  { name = "Forge de compagnon", skill = "Forge", skill_rank = 50, cost = 500 },
  { name = "Minage de compagnon", skill = "Minage", skill_rank = 50, cost = 1 },
  { name = "Gilet de compagnon", skill = "Forge", skill_rank = 50, cost = 2, item = 2957 } } },
  [2] = { services = { { name = "Forge de compagnon", skill = "Forge", skill_rank = 50, cost = 450 } } } }
res = scenario({ rang = 60, max = 75, niveau = 25, curseur = 160, marchands = { [M] = 10 }, recettes = LAME, maitres = MAITRES_RANG })
local rangs = {}
for _, a in ipairs(res.apprentissages) do if a.rang then rangs[#rangs + 1] = a end end
assert(#rangs == 2 and rangs[1].nom == "Compagnon (150)" and rangs[1].rang == 150 and rangs[1].niveau == 60 and rangs[1].source == "Maître"
  and rangs[1].prix == 450, "Compagnon à 60, 450 : " .. tostring(rangs[1] and rangs[1].prix))
assert(rangs[2].nom == "Expert (225)" and rangs[2].niveau == 125 and rangs[2].prix == nil, "Expert à 125, pas relevé : prix inconnu")
assert(res.patrons == 450 and res.total == res.totalAchats + 450 and res.net == res.total - res.revente, "le prix du rang compte : " .. res.patrons)
local fr = {}
for _, e in ipairs(ns.etapesFrise(res)) do if e.apprendre then fr[#fr + 1] = e.de .. " " .. e.nom end end
assert(table.concat(fr, ", ") == "60 Compagnon (150), 125 Expert (225)", "à leur place dans la frise : " .. table.concat(fr, ", "))
local tr = assert(ns.trancheCreer("Forge", res))
assert(tr.etapes[1].rang == 150 and tr.etapes[1].apprendre, "le rang gardé avec la tranche (panneau)")
Composants.Supprimer(select(2, ns.trancheDe("Forge")).id)
assert(ns.trancheDe("Forge") == nil)
res = scenario({ rang = 60, max = 150, niveau = 25, curseur = 140, marchands = { [M] = 10 }, recettes = LAME, maitres = MAITRES_RANG })
assert(#res.apprentissages == 0 and res.patrons == 0, "rang déjà appris (plafond relevé à 150) : rien à apprendre")
AzerothCommuneDB.trainers = nil
-- Les patrons comptent dans le total (le prix des recettes à apprendre aussi) : B, patron vendu à 300, et le maître de A à 500.
res = scenario({ rang = 1, curseur = 30, marchands = { [M] = 10 }, recettes = RP, maitres = MAITRE })
assert(res.patrons == 800 and res.total == res.totalAchats + 800, "patrons comptés dans le total : " .. res.total)
AzerothCommuneDB.trainers = nil

-- Coché tout seul (Maitrise#4) : un apprentissage est fait quand le socle voit la recette connue, ou le plafond du rang.
res = scenario({ rang = 1, curseur = 30, marchands = { [M] = 10 }, recettes = RP, connues = {} })
local B = res.apprentissages[2]
assert(B.nom == "B" and not ns.appris(B, "Forge"), "B pas encore apprise")
AzerothCommuneDB.chars[MOI].recipes.Forge.known[2] = true -- le socle relève B connue (fenêtre de métier, connexion)
assert(ns.appris(B, "Forge"), "B vue connue par le socle : cochée")
AzerothCommuneDB.chars[MOI].professions[1].max = 75
assert(not ns.appris({ rang = 150 }, "Forge"), "Compagnon pas encore : plafond 75")
AzerothCommuneDB.chars[MOI].professions[1].max = 150
assert(ns.appris({ rang = 150 }, "Forge"), "Compagnon appris : plafond relevé à 150")

-- Où apprendre (Maitrise#4, AzerothCommune#80) : les marchands du patron, les maîtres du métier pour un rang ou une recette de
-- maître, ceux de la faction du joueur ou des deux ; rien pour un patron à l'HV.
acns.recettesPNJ = { [11] = { "Vayn", 1453, 45, 60, "Alliance" }, [12] = { "Grak", 1454, 10, 20, "Horde" }, [13] = { "Neutre", 1446, 5, 5 } }
acns.recettesMaitres = { Forge = { 11, 12 } }
res = scenario({ rang = 1, curseur = 30, marchands = { [M] = 10 }, recettes = RP, maitres = MAITRE, marchandsPatron = { [2] = { 12, 300, 13, 300 } } })
local ouB = ns.endroits(res.apprentissages[2], "Forge")
assert(#ouB == 1 and ouB[1].nom == "Neutre" and ouB[1].carte == 1446, "patron vendu : son marchand de la faction ou des deux")
local ouA = ns.endroits(res.apprentissages[1], "Forge")
assert(#ouA == 1 and ouA[1].nom == "Vayn" and ouA[1].x == 45, "maître : ceux du métier, de la faction")
assert(#ns.endroits({ rang = 150, source = "Maître" }, "Forge") == 1 and #ns.endroits({ patronHV = true, cle = 2 }, "Forge") == 0)
acns.recettesPNJ, acns.recettesMaitres = nil, nil
AzerothCommuneDB.trainers = nil
print("Maîtrise : à apprendre (rangs, prix, endroits, coché par le socle) et curseur plafonné par le niveau OK")

-- La tranche tenue (Maitrise#3) : créer, une seule par perso et métier, progression, recalculer, finir.
local function rang(r) AzerothCommuneDB.chars[MOI].professions[1].rank = r end
res = scenario({ rang = 1, curseur = 10, marchands = { [M] = 10 }, recettes = { [1] = { 5001, "Lame", { M, 2 }, 1, 10, 20 } } })
local t = assert(ns.trancheCreer("Forge", res))
local _, p = ns.trancheDe("Forge")
assert(p.tenu == "Maîtrise : Forge de 1 à 10" and p.name == "Maîtrise : Forge de 1 à 10", "raison et nom : " .. tostring(p.tenu))
assert(#p.lines == 1 and p.lines[1].recette == 1 and p.lines[1].fois == 9 and not p.lines[1].id, "une ligne fabrication")
assert(ns.trancheCreer("Forge", res))
local _, p2 = ns.trancheDe("Forge")
assert(p2 == p and #Composants.Projets() == 1, "au plus une tranche par perso et métier : le projet est repris")
assert(select(2, ns.trancheDe("Forge")) == p and ns.trancheDe("Couture") == nil)
-- La progression : « <métier> <compétence> / <curseur> », rien d'autre (ni avance, ni retard, ni décompte).
rang(5)
assert(ns.trancheEtat("Forge").texte == "Forge 5 / 10", ns.trancheEtat("Forge").texte)
assert(ns.trancheCompter == nil and t.faites == nil, "plus de décompte des fabrications")
-- Une tranche gardée par une version plus ancienne (faites, sans etapes) se lit sans erreur.
t.faites, t.etapes = 3, nil
assert(ns.trancheEtat("Forge").texte == "Forge 5 / 10")
-- Recalculer : depuis 5 au même curseur, les choix de case restent.
Composants.Choix(p, M, "acheter")
local r2 = assert(ns.trancheRecalculer("Forge"))
assert(r2.de == 5 and r2.a == 10 and p.lines[1].fois == 5 and p.choix[M] == "acheter", "recalcul : lignes neuves, choix gardés")
assert(t ~= ns.trancheDe("Forge") and ns.trancheDe("Forge").faites == nil and ns.trancheDe("Forge").de == 5)
assert(p.tenu == "Maîtrise : Forge de 5 à 10", p.tenu)
-- Reprendre plus haut : même projet, nouveau curseur.
assert(ns.trancheRecalculer("Forge", 8) and p.tenu == "Maîtrise : Forge de 5 à 8" and p.name == p.tenu, "le nom suit les niveaux")
-- Finir : à la compétence du curseur, le projet est lâché, la tranche oubliée, le projet reste.
rang(8)
assert(ns.trancheEtat("Forge") == nil and p.tenu == nil and ns.trancheDe("Forge") == nil, "tranche terminée")
assert(Composants.Projet(p.id), "le projet reste dans Composants")
-- Abandonner ; un projet supprimé dans Composants fait oublier la tranche.
rang(5)
assert(ns.trancheCreer("Forge", scenario({ rang = 5, curseur = 10, marchands = { [M] = 10 }, recettes = { [1] = { 5001, "Lame", { M, 2 }, 1, 10, 20 } } })))
ns.trancheAbandonner("Forge")
assert(ns.trancheDe("Forge") == nil and Composants.Projet(p.id))
-- Une route calculée à une autre compétence (périmée) ne fait pas de tranche ; sans route non plus.
local pas, pourquoi = ns.trancheCreer("Forge", res)
assert(pas == nil and pourquoi:find("Calculer", 1, true), "route périmée refusée : " .. tostring(pourquoi))
assert(ns.trancheCreer("Forge", nil) == nil, "sans route : refusé")
res = scenario({ rang = 5, curseur = 10, marchands = { [M] = 10 }, recettes = { [1] = { 5001, "Lame", { M, 2 }, 1, 10, 20 } } })
assert(ns.trancheCreer("Forge", res))
local _, p3 = ns.trancheDe("Forge")
Composants.Supprimer(p3.id)
assert(ns.trancheDe("Forge") == nil, "projet supprimé : tranche oubliée")
-- Fin sur le signal du socle (AzerothCommune#69) : un gain de compétence relu et signalé termine la tranche, sans fenêtre.
rang(5)
assert(ns.trancheCreer("Forge", scenario({ rang = 5, curseur = 10, marchands = { [M] = 10 }, recettes = { [1] = { 5001, "Lame", { M, 2 }, 1, 10, 20 } } })))
local _, p4 = ns.trancheDe("Forge")
rang(10)
AzerothCommune:Signaler("métiers et compétences")
assert(MaitriseDB.tranches[UnitGUID("player")].Forge == nil and p4.tenu == nil, "tranche terminée au signal, sans rien lire d'autre")
print("Maîtrise : tranche tenue (créer, une par métier, progression, recalcul garde les choix, fin, abandon) OK")

-- Un autre de mes personnages (Maitrise#5) : sa tranche part de sa compétence relevée, son curseur est plafonné par son
-- niveau, elle est tenue à son nom (au plus une par personnage et par métier, à côté de celle du connecté).
local AUTRE = "Player-6942-000000AB"
res = scenario({ rang = 5, curseur = 10, marchands = { [M] = 10 }, recettes = LAME })
assert(ns.trancheCreer("Forge", res))
AzerothCommuneDB.chars[AUTRE] = { nom = "Riwanon Kerys", professions = { { name = "Forge", rank = 49, max = 75 } },
  character = { level = 19, faction = "Horde" } }
local ra = assert(Maitrise.Tranche(AUTRE, "Forge", 200))
assert(ra.de == 49 and ra.a == 150 and ra.raisonPlafond == "150 max : Expert au niveau 20" and ra.guid == AUTRE,
  "de sa compétence, plafonnée par son niveau : " .. ra.de .. "-" .. ra.a)
assert(ns.plafondDe(AUTRE) == 150 and ns.plafondDe() == 300, "chacun son plafond")
local ta = assert(ns.trancheCreer("Forge", ra))
local _, pa = ns.trancheDe("Forge", AUTRE)
local _, pm = ns.trancheDe("Forge")
assert(pa and pm and pa ~= pm and pa.tenu == "Maîtrise : Riwanon, Forge de 49 à 150" and pm.tenu == "Maîtrise : Forge de 5 à 10",
  "deux tranches, une par personnage : " .. tostring(pa and pa.tenu))
assert(MaitriseDB.tranches[AUTRE].Forge == ta and ns.trancheEtat("Forge", AUTRE).texte == "Riwanon, Forge 49 / 150")
assert(ns.trancheCreer("Forge", ra) and select(2, ns.trancheDe("Forge", AUTRE)) == pa, "repris, pas un autre projet")
-- Sa faction pour les endroits : les maîtres de la Horde.
acns.recettesPNJ, acns.recettesMaitres = { [11] = { "Vayn", 1453, 45, 60, "Alliance" }, [12] = { "Grak", 1454, 10, 20, "Horde" } }, { Forge = { 11, 12 } }
assert(ns.endroits({ rang = 150 }, "Forge", AUTRE)[1].nom == "Grak" and ns.endroits({ rang = 150 }, "Forge")[1].nom == "Vayn")
acns.recettesPNJ, acns.recettesMaitres = nil, nil
Composants.Supprimer(pa.id); Composants.Supprimer(pm.id)
assert(ns.trancheDe("Forge", AUTRE) == nil and ns.trancheDe("Forge") == nil)
AzerothCommuneDB.chars[AUTRE] = nil
print("Maîtrise : un autre de mes personnages (sa compétence, son plafond, sa tranche, sa faction) OK")

-- Le panneau de la fenêtre de métier : la tranche garde les lignes de la frise (sans l'objectif), le panneau les place à la
-- compétence. RP : « A » (maître, 1, jaune 10, gris 20) de 1 à 10, « B » (patron vendu, 10, jaune 20, gris 30) de 10 à 30.
rang(1)
res = scenario({ rang = 1, curseur = 30, marchands = { [M] = 10 }, recettes = RP, maitres = MAITRE })
t = assert(ns.trancheCreer("Forge", res))
local function sorte(e) return e.apprendre and ("Apprendre " .. e.nom) or e.trou and "trou" or (e.nom .. " " .. e.de .. "-" .. e.a) end
local vu = {}
for _, e in ipairs(t.etapes) do vu[#vu + 1] = sorte(e) end
assert(table.concat(vu, ", ") == "Apprendre A, A 1-10, Apprendre B, B 10-30", table.concat(vu, ", "))
local frise = ns.etapesFrise(res)
assert(#frise == #t.etapes + 1 and frise[#frise].fin, "la frise : les mêmes lignes, puis l'objectif")
assert(t.etapes[2].fois == 9 and t.etapes[2].objet == 5001 and t.etapes[2].cle == 1 and t.etapes[3].prix == 300
  and t.etapes[3].source == "Patron" and not t.etapes[2].composants, "ce qui est gardé : niveaux, fois, objet, prix, source ; pas les composants")
local base = AzerothCommune:Lire("base des recettes")
local connues = { [1] = true }
local function lp(s) return ns.lignesPanneau(t.etapes, s, base, function(e) return connues[e.cle] end) end
local function resume(ls)
  local o = {}
  for _, l in ipairs(ls) do o[#o + 1] = l.etat .. ":" .. tostring(l.couleur) end
  return table.concat(o, " ")
end
-- À 5 : A en cours (orange), B pas encore à portée (apprise à 10 : pas de couleur), son apprentissage à venir.
assert(resume(lp(5)) == "passee:nil courante:orange avenir:nil avenir:nil", resume(lp(5)))
-- À 12 : A passée (jaune à 12), B à apprendre maintenant et en cours (orange sous son jaune).
assert(resume(lp(12)) == "passee:nil passee:jaune courante:nil courante:orange", resume(lp(12)))
-- À 25 : A grise, B verte ; B apprise : son apprentissage passe.
connues[2] = true
assert(resume(lp(25)) == "passee:nil passee:gris passee:nil courante:vert", resume(lp(25)))
local ls = lp(25)
assert(ls[1].nom == "Apprendre A" and ls[1].droite == AzerothCommune.ArgentCourt(500), ls[1].droite)
assert(ls[4].nom == "B" and ls[4].droite == ("10–30 ×%d"):format(t.etapes[4].fois), ls[4].droite)
-- Un trou : sa ligne, ses niveaux, sans couleur.
ns.trancheAbandonner("Forge")
res = scenario({ rang = 1, curseur = 25, marchands = { [M] = 10 }, recettes = { [1] = { 5001, "Lame", { M, 1 }, 1, 10, 20 } } })
t = assert(ns.trancheCreer("Forge", res))
ls = ns.lignesPanneau(t.etapes, 22, base, function() return true end)
assert(#ls == 3 and ls[3].etape.trou and ls[3].nom == "Aucune recette connue" and ls[3].droite == "20–25" and ls[3].etat == "courante"
  and ls[3].couleur == nil and ls[2].couleur == "gris", resume(ls))
assert(ls[1].droite == "prix ?", "maître sans prix relevé : " .. ls[1].droite)
ns.trancheAbandonner("Forge")
print("Maîtrise : panneau de la fenêtre de métier (étapes gardées, en cours, passées, couleur à la compétence, apprentissages, trous) OK")
