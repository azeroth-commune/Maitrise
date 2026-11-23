-- Vérification hors jeu (non chargée par la TOC) : luajit Maitrise/check.lua, depuis le dossier des add-ons.
-- Le socle Azeroth Commune est chargé avant, comme dans le jeu : ses SavedVariables servent de données (métiers du perso,
-- cours de l'HV, marchands, objets) et sa réserve des recettes (privée, acns.recettesClassic) est celle de chaque scénario.
-- Tout passe par la fonction publique Maitrise.Tranche.
local noop = function() end
local stubMT = { __index = function() return noop end }
CreateFrame = function() return setmetatable({}, stubMT) end
SlashCmdList, StaticPopupDialogs, UISpecialFrames = {}, {}, {}
C_Timer = { After = noop, NewTicker = noop }
C_Item = { GetItemInfo = noop, GetItemIconByID = noop }
date, time = os.date, os.time
GetTime = function() return 0 end
UnitFactionGroup = function() return "Alliance" end
geterrorhandler = function() return function(e) error(e, 0) end end
local MOI = "Player-6942-0000000E"
UnitGUID = function(u) if u == "player" then return MOI end end
AzerothCommuneDB, AzerothCommuneItems, AzerothCommuneMarket = { recipes = {}, chars = {}, lots = {} }, { items = {} }, {}
local acns = {}
for f in io.open("AzerothCommune/AzerothCommune.toc"):read("*a"):gmatch("([%w_]+)%.lua") do
  if f ~= "VendorData" and f ~= "RecettesClassic" and f ~= "CatalogueObjets" then assert(loadfile("AzerothCommune/" .. f .. ".lua"))("AzerothCommune", acns) end
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
-- recharge } } (métier « Forge »), paliers de l'HV { [id] = { { prix, qté }, … } }, marchands { [id] = prix }, revente
-- au marchand { [id] = prix }, compétence actuelle du perso connecté.
local function scenario(t)
  local r = {}
  for k, x in pairs(t.recettes) do
    r[k] = { x[1], 1, 1, "Forge", x[2], x[3], x[4], x[5], x[6], x[7] or "maître", "source externe", x[8] or 0, x[9] or 0 }
  end
  acns.recettesClassic = r
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
  AzerothCommuneDB.chars = { [MOI] = { nom = "Moi Dupont", professions = { { name = "Forge", rank = t.rang, max = 300 } } } }
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

-- Règle des 20 % (Maitrise#9) : Gros (7 minerais, jaune dès 10, gris à 40) et Fin (1 minerai, jaune dès 10, gris à 30).
-- À 28, Fin ne donne qu'un point sur 10 (10 minerais le point) contre 0,6 pour Gros (11,7 le point) : sans la règle, Fin
-- gagne ; avec, Gros couvre le point. Sans Gros, Fin reste (pas de trou).
local R20 = { [1] = { 5001, "Fin", { M, 1 }, 1, 10, 30 }, [2] = { 5002, "Gros", { M, 7 }, 1, 20, 40 } }
res = scenario({ rang = 28, curseur = 29, marchands = { [M] = 10 }, recettes = R20 })
assert(#res.fabrications == 1 and res.fabrications[1].nom == "Gros", "point sous 20 % évité : " .. noms(res))
res = scenario({ rang = 28, curseur = 29, marchands = { [M] = 10 }, recettes = { [1] = R20[1] } })
assert(#res.fabrications == 1 and res.fabrications[1].nom == "Fin" and #res.trous == 0, "seule recette gardée : " .. noms(res))
-- Un point juste au-dessus de 20 % reste à la moins chère : à 26, Fin donne 0,2 (50 minerais le point) contre 0,7 pour Gros.
res = scenario({ rang = 25, curseur = 26, marchands = { [M] = 10 }, recettes = R20 })
assert(res.fabrications[1].nom == "Fin", "à 25 % la règle ne joue pas : " .. noms(res))
print("Maîtrise : règle des 20 % (évité si une autre recette couvre, gardé sinon) OK")

-- La tranche tenue (Maitrise#3) : créer, une seule par perso et métier, avance ou retard, recalculer, finir.
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
-- Avance ou retard : à 5, la route prévoyait 4 des 9 fabrications ; aucune faite = en avance.
rang(5)
assert(ns.trancheEtat("Forge").texte == "Forge 5 / 10 · en avance (4)", ns.trancheEtat("Forge").texte)
ns.trancheCompter(999) -- pas une recette de la tranche
assert(t.faites == 0, "un autre sort ne compte pas")
for i = 1, 4 do ns.trancheCompter(1) end
assert(ns.trancheEtat("Forge").texte == "Forge 5 / 10 · dans les temps")
ns.trancheCompter(1)
assert(ns.trancheEtat("Forge").texte == "Forge 5 / 10 · en retard (1)", ns.trancheEtat("Forge").texte)
-- Recalculer : depuis 5 au même curseur, les choix de case restent, le décompte repart.
Composants.Choix(p, M, "acheter")
local r2 = assert(ns.trancheRecalculer("Forge"))
assert(r2.de == 5 and r2.a == 10 and p.lines[1].fois == 5 and p.choix[M] == "acheter", "recalcul : lignes neuves, choix gardés")
assert(t ~= ns.trancheDe("Forge") and ns.trancheDe("Forge").faites == 0 and ns.trancheDe("Forge").de == 5)
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
print("Maîtrise : tranche tenue (créer, une par métier, avance/retard, recalcul garde les choix, fin, abandon) OK")
