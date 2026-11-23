-- Maîtrise, le calcul : la route d'une tranche (PRD Maitrise#1), portée du prototype research/montee/route.lua de l'atelier.
-- Pour chaque point de compétence, la recette au coût net espéré minimal, (composants − valeur du produit) / chance d'un
-- point ; un composant coûte son prix marginal (palier de l'HV atteint par les achats déjà prévus, ou le marchand) ou sa
-- fabrication si elle est moins chère ; un produit vaut son coût de remplacement s'il resert dans la tranche, sinon sa
-- revente au marchand (jamais l'HV). Itérations jusqu'à stabilité avec deux départs, chaque plan chiffré exactement, le
-- moins cher gardé. Toutes les données passent par le socle (Azeroth Commune).
local _, ns = ...
local lib = AzerothCommune
-- Ce que Maîtrise lit : le socle ne relève que les types auxquels un add-on a souscrit.
-- « maîtres de métier » : la compétence demandée et le prix de chaque recette chez un maître (relevé direct, AzerothCommune#68).
-- « recettes connues » : une recette à condition (spécialisation, réputation) n'est prise que si le personnage la connaît.
for _, t in ipairs({ "base des recettes", "métiers et compétences", "cours de l'HV", "marchands", "objets", "maîtres de métier",
  "recettes connues" }) do lib:Souscrire(t) end

local ITERATIONS, DEPART2, PROFONDEUR = 40, 21, 3
-- Le temps compte aussi : un point à moins de 20 % de chance n'est pas compté pour une recette, sauf si aucune autre ne
-- le couvre (mieux la moins mauvaise qu'un trou).
local SEUIL = 0.2
local COURT = 5 -- une étape de COURT points ou moins entre deux étapes de la même recette : un aller-retour (Maitrise#17)

-- Les recettes d'un métier que la route peut prendre : une source connue (d'emblée, maître, patron vendu ; « inconnue »
-- couvre aussi les patrons sous réputation, de l'autre faction ou vendus en donjon, règle du générateur de la réserve),
-- sans temps de recharge, avec les seuils du client (jaune, gris), et sans condition d'accès (spécialisation, réputation,
-- plus enseignée : AzerothCommune#67) sauf si le personnage la connaît déjà (connues = { [clé] = true }). Le prix pour
-- l'apprendre : celui du maître relevé pour une recette de maître (AzerothCommune#72), sinon celui du patron. Triées par
-- clé : un calcul se rejoue à l'identique.
-- Patron à l'HV (Maitrise#15) : une recette « inconnue » (patron de butin ou de quête) ou « patron vendu » qui a un objet patron
-- (r.patron, du socle) est aussi prise quand prixPatron(patron) donne le prix d'achat d'UN patron au dernier scan de l'HV
-- (nil : pas en vente). Ce prix devient celui pour l'apprendre (pour un patron vendu, seulement s'il est moins cher que celui
-- du marchand) et la recette est marquée patronHV (la frise le dit). Sans prixPatron : comme avant.
-- Une recette que le personnage connaît déjà est gardée quelle que soit sa source (retirée, butin, quête…) : rien à apprendre
-- (prix 0, pas de patron à l'HV), mais ni recharge ni seuils en moins.
-- ponytail: un patron est souvent un objet unique au scan, parfois cher, pas toujours en vente : le prix est celui du scan, sans
-- règle de prudence en plus.
-- ponytail: le socle ne relève pas la spécialisation ni les réputations du personnage ; toute recette à condition qu'il ne
-- connaît pas est écartée (prudent : jamais de recette inaccessible proposée).
local SOURCES = { ["d'emblée"] = true, ["maître"] = true, ["patron vendu"] = true }
local PATRON_HV = { ["inconnue"] = true, ["patron vendu"] = true }
function ns.recettesDuMetier(base, metier, connues, prixPatron)
  local out = {}
  for k, r in pairs(base) do
    if r.profession == metier and (r.cooldown or 0) == 0 and r.yellow and r.grey and r.grey > 1
      and (not r.condition or (connues and connues[k])) then
      local connue = connues and connues[k]
      local prix = not connue and ((r.source == "maître" and r.prix_maitre) or r.pattern_price) or 0
      local hv = not connue and prixPatron and r.patron and PATRON_HV[r.source] and prixPatron(r.patron)
      local patronHV = hv and (r.source == "inconnue" or prix == 0 or hv < prix)
      if patronHV then prix = hv end
      if connue or SOURCES[r.source] or patronHV then
        out[#out + 1] = { key = k, name = r.name, learn = r.level or 1, y = r.yellow, g = r.grey, o = r.output,
          n = math.max(1, r.made_min or 1), reag = r.reagents or {}, pattern = prix, patronHV = patronHV or nil }
      end
    end
  end
  table.sort(out, function(a, b) return a.key < b.key end)
  return out
end

-- Chance d'un point à la compétence s (seuils du client) ; fabrications espérées pour ce point : 1 / p.
local function chance(r, s)
  if s < r.learn or s >= r.g then return 0 end
  if r.y == 0 or s < r.y then return 1 end
  return (r.g - s) / (r.g - r.y)
end

-- Couleur de la recette à la compétence s (seuils du client) : orange sous le jaune, jaune jusqu'au milieu entre jaune et
-- gris, vert ensuite (la chance y passe à 50 %).
local function couleur(r, s)
  if r.y == 0 or s < r.y then return "orange" end
  return s < (r.y + r.g) / 2 and "jaune" or "vert"
end

-- La fourchette d'une étape (le 10e et le 90e centile de ses fabrications) d'après la chance ps de chacun de ses points,
-- sans tirage : un point demande un nombre géométrique de fabrications (moyenne 1 / p, variance (1 − p) / p², 3e moment
-- centré (1 − p)(2 − p) / p³) ; on les additionne (cumulants) et on lit les centiles par Wilson-Hilferty (loi gamma de
-- mêmes moments), arrondis au plus près, jamais sous le nombre de points. Mesuré contre la convolution exacte (relecture
-- de la PR #14) : à une fabrication près quand tous les points sont à 20 % ou plus, à deux près avec des points de repli
-- sous 20 % (étapes de 100 à 200 fabrications). Rend bas, haut ; nil pour une étape sans aléa (que des points à 100 %).
-- ponytail: approximation (la convolution exacte coûte ~100x plus) ; l'asymétrie des étapes de 1 à 2 points reste à ±1.
local Z = 1.2815515655 -- le 90e centile de la loi normale
function ns.fourchette(ps)
  local m, v, k3, aleas = 0, 0, 0, false
  for _, p in ipairs(ps) do
    m = m + 1 / p
    if p < 1 then
      aleas = true
      v = v + (1 - p) / (p * p)
      k3 = k3 + (1 - p) * (2 - p) / (p * p * p)
    end
  end
  if not aleas then return nil end
  local sd, g = math.sqrt(v), k3 / v ^ 1.5
  -- Wilson-Hilferty : une loi gamma décalée de même moyenne, variance et asymétrie (k = 4 / g²), tenue même pour un
  -- étage très asymétrique (quelques points à 3 %) où Cornish-Fisher décroche.
  local k = 4 / (g * g)
  local function centile(z)
    local u = 1 - 1 / (9 * k) + z / (3 * math.sqrt(k))
    return math.floor(m - 2 * sd / g + (2 * sd / g) * u * u * u + 0.5)
  end
  return math.max(#ps, centile(-Z)), math.max(#ps, centile(Z))
end

-- La route de FROM à TO avec les recettes rs (ns.recettesDuMetier) et les prix : achat(id, qty) → coût de qty unités
-- (nil sans prix), revente(id) → prix de revente au marchand d'une unité.
-- ponytail: l'ordre dans le temps est ignoré (un produit tardif peut couvrir un besoin plus tôt), limite du PRD.
function ns.route(rs, achat, revente, FROM, TO)
  local makers = {}
  for _, r in ipairs(rs) do if r.o then makers[r.o] = makers[r.o] or {}; table.insert(makers[r.o], r) end end
  local allUses = {}
  for _, r in ipairs(rs) do for _, rq in ipairs(r.reag) do allUses[rq.id] = 1 end end
  -- Le prix pour apprendre une recette (maître ou patron) compte dans le choix point par point, réparti sur les points où
  -- elle peut servir dans la tranche (chance d'au moins 20 %) : sinon un patron cher pour quelques points passait devant
  -- une recette sans prix pour une économie de quelques pièces (le total, lui, le comptait déjà une fois).
  -- ponytail: répartition sur toute la plage utile ; la route peut n'en prendre qu'une partie (le total reste exact).
  local apprendre = {}
  for _, r in ipairs(rs) do
    if (r.pattern or 0) > 0 then
      local n = 0
      for s = FROM, TO - 1 do if chance(r, s) >= SEUIL then n = n + 1 end end
      apprendre[r] = r.pattern / math.max(1, n)
    end
  end
  local P, need = {}, {} -- achats et besoins de l'itération précédente
  local marg, memo, sansPrix = {}, {}, {}
  local function marginal(i) -- prix de la prochaine unité, après les P[i] déjà prévues
    local m = marg[i]
    if m == nil then
      local q = math.floor(P[i] or 0)
      local a, b = achat(i, q), achat(i, q + 1)
      m = b and (b - (a or 0)) or false
      marg[i] = m
    end
    return m or nil
  end
  local function unit(i, s, depth) -- coût d'une unité à la compétence s : acheter, ou fabriquer avec une recette apprise
    local cle = (i * 1024 + s) * 4 + depth
    local v = memo[cle]
    if v ~= nil then return v or nil end
    local best = marginal(i)
    if depth < PROFONDEUR then
      for _, r in ipairs(makers[i] or {}) do
        if r.learn <= s then
          local c = 0
          for _, rq in ipairs(r.reag) do
            local u = unit(rq.id, s, depth + 1)
            if not u then c = nil break end
            c = c + u * rq.qty
          end
          if c and (not best or c / r.n < best) then best = c / r.n end
        end
      end
    end
    memo[cle] = best or false
    return best
  end
  local bestObj, bestPlan
  for iter = 1, ITERATIONS do
    if iter == DEPART2 then need, P = allUses, {} end -- 2e départ : tout ce qu'une recette peut consommer sera réemployé
    marg, memo = {}, {}
    -- Coût net espéré d'un point à la compétence s avec la recette r (nil si elle ne donne rien ou qu'un composant n'a pas
    -- de prix) : (composants − valeur du produit) / chance, plus la part du prix pour l'apprendre.
    local function coutPoint(r, s)
      local p = chance(r, s)
      if p <= 0 then return nil end
      local c = 0
      for _, rq in ipairs(r.reag) do
        local u = unit(rq.id, s, 0)
        if not u then sansPrix[rq.id] = true return nil end
        c = c + u * rq.qty
      end
      local v = 0
      if r.o then v = ((need[r.o] or 0) > 0 and (unit(r.o, s, 1) or 0) or revente(r.o)) * r.n end
      return (c - v) / p + (apprendre[r] or 0), p, c - v -- le net d'une fabrication : composants − produit
    end
    local steps = {}
    for s = FROM, TO - 1 do
      local best, bk, repli, rk -- repli : le meilleur parmi les recettes sous SEUIL, si aucune autre ne couvre le point
      for _, r in ipairs(rs) do
        local k, p, net = coutPoint(r, s)
        if k then
          if p < SEUIL then
            if not rk or k < rk then repli, rk = { r = r, crafts = 1 / p, k = k, net = net }, k end
          elseif not bk or k < bk then best, bk = { r = r, crafts = 1 / p, k = k, net = net }, k end
        end
      end
      steps[s] = best or repli
    end
    -- Pas d'aller-retour court (Maitrise#17) : une suite de COURT points ou moins sur une recette B, entre deux suites de la
    -- même recette A, passe à A si A y donne encore ses points (chance d'au moins 20 %) et que l'économie de B est
    -- minime (moins de 20 pa, ou moins de 3 % du coût des points de la tranche). Moins de composants différents à
    -- acheter, une frise plus lisible ; le total reste chiffré exactement plus bas.
    local total = 0
    for s = FROM, TO - 1 do if steps[s] then total = total + math.max(0, steps[s].k) end end
    local change = true
    while change do
      change = false
      local s = FROM
      while s < TO do
        local b = steps[s]
        local e = s
        while e + 1 < TO and steps[e + 1] and b and steps[e + 1].r == b.r do e = e + 1 end
        local avant, apres = steps[s - 1], steps[e + 1]
        if b and avant and apres and avant.r == apres.r and avant.r ~= b.r and e - s + 1 <= COURT then
          local surcout, remplace = 0, {}
          for t = s, e do
            local k, p, net = coutPoint(avant.r, t)
            if not k or p < SEUIL then surcout = nil break end
            surcout = surcout + k - steps[t].k
            remplace[t] = { r = avant.r, crafts = 1 / p, k = k, net = net }
          end
          if surcout and (surcout < 2000 or surcout < 0.03 * total) then
            for t = s, e do steps[t] = remplace[t] end
            change = true
          end
        end
        s = e + 1
      end
    end
    -- Le flux : ce que la route consomme, ce qu'elle produit, puis fabriquer ou acheter le reste.
    local req, made = {}, {}
    for s = FROM, TO - 1 do
      local b = steps[s]
      if b then
        for _, rq in ipairs(b.r.reag) do req[rq.id] = (req[rq.id] or 0) + rq.qty * b.crafts end
        if b.r.o then made[b.r.o] = (made[b.r.o] or 0) + b.r.n * b.crafts end
      end
    end
    local newP = {}
    local function obtain(i, q, depth)
      local fromroute = math.min(q, made[i] or 0)
      made[i] = (made[i] or 0) - fromroute
      q = q - fromroute
      if q <= 0 then return end
      local buyu = marginal(i)
      local mk, mkc
      if depth < PROFONDEUR then
        for _, r in ipairs(makers[i] or {}) do
          if r.learn <= TO then
            local c = 0
            for _, rq in ipairs(r.reag) do
              local u = unit(rq.id, TO, depth + 1)
              if not u then c = nil break end
              c = c + u * rq.qty
            end
            if c and (not mkc or c / r.n < mkc) then mk, mkc = r, c / r.n end
          end
        end
      end
      if mk and (not buyu or mkc < buyu) then
        for _, rq in ipairs(mk.reag) do obtain(rq.id, rq.qty * q / mk.n, depth + 1) end
      else
        newP[i] = (newP[i] or 0) + q
      end
    end
    for i, q in pairs(req) do obtain(i, q, 0) end
    -- Le chiffrage exact de ce plan : achats palier par palier, patrons, revente de ce qui n'est pas réemployé.
    local gross, list, pats, used, incomplet = 0, {}, 0, {}, false
    for i, q in pairs(newP) do
      local n = math.ceil(q - 1e-9)
      local c = achat(i, n)
      if c then gross = gross + c else incomplet = true; sansPrix[i] = true end
      list[#list + 1] = { id = i, qty = n, cout = c }
    end
    local resale = 0
    for i, q in pairs(made) do if q > 0 then resale = resale + q * revente(i) end end
    for s = FROM, TO - 1 do
      local b = steps[s]
      if b and not used[b.r] then used[b.r] = true; pats = pats + b.r.pattern end
    end
    local obj = gross + pats - resale
    if not bestObj or obj < bestObj then
      bestObj, bestPlan = obj, { steps = steps, list = list, achats = gross, patrons = pats, revente = resale, incomplet = incomplet }
    end
    for i, q in pairs(newP) do newP[i] = 0.5 * q + 0.5 * (P[i] or q) end -- amortissement
    P, need = newP, req
  end
  -- Mise en forme : les fabrications (une ligne par suite de points sur la même recette) et les trous.
  local fab, trous = {}, {}
  for s = FROM, TO - 1 do
    local b = bestPlan.steps[s]
    if b then
      local last = fab[#fab]
      if not (last and last.cle == b.r.key and last.a == s) then
        last = { de = s, a = s, cle = b.r.key, nom = b.r.name, fois = 0, patron = b.r.pattern, patronHV = b.r.patronHV, objet = b.r.o,
          n = b.r.n, composants = b.r.reag, plages = {}, chances = {} }
        fab[#fab + 1] = last
      end
      last.a, last.fois = s + 1, last.fois + b.crafts
      last.coutNet = (last.coutNet or 0) + b.net * b.crafts
      last.chances[#last.chances + 1] = 1 / b.crafts
      local c, pl = couleur(b.r, s), last.plages
      if #pl > 0 and pl[#pl].couleur == c then pl[#pl].a = s + 1 else pl[#pl + 1] = { de = s, a = s + 1, couleur = c } end
    else
      local last = trous[#trous]
      if last and last.a == s then last.a = s + 1 else trous[#trous + 1] = { de = s, a = s + 1 } end
    end
  end
  for _, f in ipairs(fab) do
    local verts = 0
    for _, pl in ipairs(f.plages) do if pl.couleur == "vert" then verts = verts + pl.a - pl.de end end
    local bas, haut = ns.fourchette(f.chances)
    f.fourchette = bas and { bas = bas, haut = haut } or nil
    f.incertaine = verts * 2 > f.a - f.de
    f.chances = nil
    f.net = f.coutNet / f.fois -- le net par fabrication : composants − revente du produit (Maitrise#12)
    f.coutNet = nil
    f.fois = math.ceil(f.fois - 1e-9)
  end
  -- Le coût « une fois sur dix » (Maitrise#12) : le net moyen, plus pour chaque étape non orange son net par fabrication
  -- (s'il est positif) × les fabrications de plus du 90e centile. Somme des 90e centiles étape par étape : un majorant
  -- prudent (le vrai 90e centile de la somme est plus bas, les aléas des étapes se compensent un peu) ; sans aléa (étapes
  -- orange), égal au net moyen. Pas de convolution : même approximation que les fourchettes.
  local net = bestPlan.achats + bestPlan.patrons - bestPlan.revente
  local dix = net
  for _, f in ipairs(fab) do
    if f.fourchette then dix = dix + math.max(0, f.net) * math.max(0, f.fourchette.haut - f.fois) end
  end
  table.sort(bestPlan.list, function(a, b) return (a.cout or 0) > (b.cout or 0) end)
  local sp = {}
  for i in pairs(sansPrix) do sp[#sp + 1] = i end
  table.sort(sp)
  return { de = FROM, a = TO, fabrications = fab, achats = bestPlan.list, totalAchats = bestPlan.achats,
    patrons = bestPlan.patrons, total = bestPlan.achats + bestPlan.patrons, revente = bestPlan.revente, trous = trous,
    sansPrix = sp, incomplet = bestPlan.incomplet, net = net, netUneSurDix = math.floor(dix + 0.5) }
end

-- La compétence du personnage (GUID, nil = le connecté) dans ce métier, d'après le relevé du socle ; et ses métiers.
function ns.metiers(guid)
  local d = lib:Lire("métiers et compétences", guid)
  local _, fiche = next(d and d.persos or {})
  local out = {}
  for _, p in ipairs(fiche and fiche.professions or {}) do out[#out + 1] = { nom = p.name, rang = p.rank, max = p.max } end
  return out
end

-- La tranche (personnage, métier, curseur) : la route du niveau actuel au curseur, aux prix du moment (socle). Rend
-- { de, a, fabrications = { { de, a, cle (le sort de la recette), nom, fois, patron, patronHV (le patron vient de l'HV), objet (nil : enchantement), n (produits
-- par fabrication), composants = { { id, qty } }, plages = { { de, a, couleur (« orange », « jaune », « vert ») } }, fourchette
-- (le 10e et le 90e centile des fabrications : { bas =, haut = }, nil pour une étape orange), incertaine (plus de la moitié
-- des points en vert) } }, achats = { { id, qty, cout } }, totalAchats, patrons,
-- total, revente, trous = { { de, a } }, sansPrix = { id… }, incomplet, scan (date lisible du dernier scan de l'HV, nil
-- sans), sansHV (aucun cours de l'HV : marchands seuls), net (total − revente), netUneSurDix (le net au 90e centile,
-- majorant : voir ns.route), apprentissages = { { niveau, cle, nom, source (« Maître », « Patron », « Patron à l'HV »), prix
-- (nil : inconnu), objetPatron } } (les recettes à apprendre, à leur niveau ; sans les connues) } ; chaque fabrication porte
-- aussi net (composants − revente du produit, par fabrication, en cuivre) }, ou nil et la raison.
-- ponytail: le stock n'entre pas dans la route (tout acheté) ; Composants le déduit dans les Besoins du projet de
-- tranche (Maitrise#3).
function ns.tranche(guid, metier, curseur)
  local rang
  for _, m in ipairs(ns.metiers(guid)) do if m.nom == metier then rang = m.rang end end
  if not rang then return nil, ("%s : métier pas relevé pour ce personnage"):format(tostring(metier)) end
  curseur = tonumber(curseur)
  if not curseur or curseur <= rang then return nil, ("le curseur doit dépasser la compétence actuelle (%d)"):format(rang) end
  local base = lib:Lire("base des recettes")
  if not base then return nil, "base des recettes pas encore relevée" end
  local hv, lotHV = lib:Lire("cours de l'HV")
  local marchands = lib:PrixMarchands()
  local lignes = setmetatable({}, { __index = function(t, id)
    local l = hv and hv.objet(id) or false
    rawset(t, id, l)
    return l
  end })
  local objets = lib:Lire("objets") or {}
  local function achat(id, qty)
    if qty <= 0 then return 0 end
    return (lib:PrixAchat(id, qty, lignes, marchands))
  end
  local function revente(id) local o = objets[id]; return o and o.price or 0 end
  -- Les recettes que ce personnage connaît déjà dans ce métier (relevé du socle) : une recette à condition y est permise.
  local rc = lib:Lire("recettes connues", guid)
  local _, metiersPerso = next(rc and rc.persos or {})
  local connues = metiersPerso and metiersPerso[metier] and metiersPerso[metier].known
  -- Le prix d'un patron à l'HV : celui d'UN patron au dernier scan, l'HV seule (un patron de butin n'a pas de marchand).
  local function prixPatron(id) return (lib:PrixAchat(id, 1, lignes, {})) end
  local res = ns.route(ns.recettesDuMetier(base, metier, connues, prixPatron), achat, revente, rang, curseur)
  res.metier = metier
  res.scan = hv and lotHV and lotHV.scan and lotHV.scan.scanned
  res.fournisseur = hv and lotHV and lotHV.fournisseur
  res.sansHV = not hv
  return res
end

Maitrise = {
  -- La tranche d'un personnage (GUID, nil = le connecté) dans un métier, jusqu'au curseur (un niveau au-dessus de sa
  -- compétence actuelle). Voir ns.tranche pour la forme rendue.
  Tranche = function(guid, metier, curseur) return ns.tranche(guid, metier, curseur) end,
}
