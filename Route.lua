-- Maîtrise, le calcul : la route d'une tranche (PRD Maitrise#1), portée du prototype research/montee/route.lua de l'atelier.
-- Pour chaque point de compétence, la recette au coût net espéré minimal, (composants − valeur du produit) / chance d'un
-- point ; un composant coûte son prix marginal (palier de l'HV atteint par les achats déjà prévus, ou le marchand) ou sa
-- fabrication si elle est moins chère ; un produit vaut son coût de remplacement s'il resert dans la tranche, sinon sa
-- revente au marchand (jamais l'HV). Itérations jusqu'à stabilité avec deux départs, chaque plan chiffré exactement, le
-- moins cher gardé. Toutes les données passent par le socle (Azeroth Commune).
local _, ns = ...
local lib = AzerothCommune
-- Ce que Maîtrise lit : le socle ne relève que les types auxquels un add-on a souscrit.
for _, t in ipairs({ "base des recettes", "métiers et compétences", "cours de l'HV", "marchands", "objets" }) do lib:Souscrire(t) end

local ITERATIONS, DEPART2, PROFONDEUR = 40, 21, 3

-- Les recettes d'un métier que la route peut prendre : une source connue (d'emblée, maître, patron vendu ; « inconnue »
-- couvre aussi les patrons sous réputation, de l'autre faction ou vendus en donjon, règle du générateur de la réserve),
-- sans temps de recharge, avec les seuils du client (jaune, gris). Triées par clé : un calcul se rejoue à l'identique.
local SOURCES = { ["d'emblée"] = true, ["maître"] = true, ["patron vendu"] = true }
function ns.recettesDuMetier(base, metier)
  local out = {}
  for k, r in pairs(base) do
    if r.profession == metier and SOURCES[r.source] and (r.cooldown or 0) == 0 and r.yellow and r.grey and r.grey > 1 then
      out[#out + 1] = { key = k, name = r.name, learn = r.level or 1, y = r.yellow, g = r.grey, o = r.output,
        n = math.max(1, r.made_min or 1), reag = r.reagents or {}, pattern = r.pattern_price or 0 }
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

-- La route de FROM à TO avec les recettes rs (ns.recettesDuMetier) et les prix : achat(id, qty) → coût de qty unités
-- (nil sans prix), revente(id) → prix de revente au marchand d'une unité.
-- ponytail: l'ordre dans le temps est ignoré (un produit tardif peut couvrir un besoin plus tôt), limite du PRD.
function ns.route(rs, achat, revente, FROM, TO)
  local makers = {}
  for _, r in ipairs(rs) do if r.o then makers[r.o] = makers[r.o] or {}; table.insert(makers[r.o], r) end end
  local allUses = {}
  for _, r in ipairs(rs) do for _, rq in ipairs(r.reag) do allUses[rq.id] = 1 end end
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
    local steps = {}
    for s = FROM, TO - 1 do
      local best, bk
      for _, r in ipairs(rs) do
        local p = chance(r, s)
        if p > 0 then
          local c = 0
          for _, rq in ipairs(r.reag) do
            local u = unit(rq.id, s, 0)
            if not u then c = nil; sansPrix[rq.id] = true break end
            c = c + u * rq.qty
          end
          if c then
            local v = 0
            if r.o then v = ((need[r.o] or 0) > 0 and (unit(r.o, s, 1) or 0) or revente(r.o)) * r.n end
            local k = (c - v) / p
            if not bk or k < bk then best, bk = { r = r, crafts = 1 / p }, k end
          end
        end
      end
      steps[s] = best
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
      if last and last.cle == b.r.key and last.a == s then last.a, last.fois = s + 1, last.fois + b.crafts
      else fab[#fab + 1] = { de = s, a = s + 1, cle = b.r.key, nom = b.r.name, fois = b.crafts, patron = b.r.pattern } end
    else
      local last = trous[#trous]
      if last and last.a == s then last.a = s + 1 else trous[#trous + 1] = { de = s, a = s + 1 } end
    end
  end
  for _, f in ipairs(fab) do f.fois = math.ceil(f.fois - 1e-9) end
  table.sort(bestPlan.list, function(a, b) return (a.cout or 0) > (b.cout or 0) end)
  local sp = {}
  for i in pairs(sansPrix) do sp[#sp + 1] = i end
  table.sort(sp)
  return { de = FROM, a = TO, fabrications = fab, achats = bestPlan.list, totalAchats = bestPlan.achats,
    patrons = bestPlan.patrons, total = bestPlan.achats + bestPlan.patrons, revente = bestPlan.revente, trous = trous,
    sansPrix = sp, incomplet = bestPlan.incomplet }
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
-- { de, a, fabrications = { { de, a, cle, nom, fois, patron } }, achats = { { id, qty, cout } }, totalAchats, patrons,
-- total, revente, trous = { { de, a } }, sansPrix = { id… }, incomplet, scan (date lisible du dernier scan de l'HV, nil
-- sans), sansHV (aucun cours de l'HV : marchands seuls) }, ou nil et la raison.
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
  local res = ns.route(ns.recettesDuMetier(base, metier), achat, revente, rang, curseur)
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
