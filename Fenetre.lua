-- Maîtrise, la fenêtre (/maitrise) : le joueur vient y faire deux choses — choisir un métier et jusqu'où le monter ce
-- soir, puis lire la route (quelle recette, combien de fois) et ce qu'elle coûte. Un menu des métiers (de tous mes personnages), un curseur, un
-- bouton Calculer (rien ne se recalcule tout seul) ; deux onglets : la Route (une frise) et les Achats (skill ui-addon).
local _, ns = ...
local lib = AzerothCommune

-- La montée des métiers de récolte et de la Pêche ne s'achète pas (hors du PRD).
local RECOLTE = { ["Minage"] = true, ["Herboristerie"] = true, ["Dépeçage"] = true, ["Pêche"] = true }
local nomsDeSession = {}
local frame, metierB, curseurE, plafondT, calculB, etatB, resume, tabAchats, vues, frise
local HAUT = 204 -- sous l'en-tête (réglages, résumé de la tranche) : le haut de la frise et du tableau des achats
local choix -- le métier choisi
local perso -- le personnage choisi (GUID, nil = le connecté) : un autre de mes personnages se prépare d'ici (Maitrise#5)
local res -- la dernière tranche calculée

local function metiers(guid)
  local out = {}
  for _, m in ipairs(ns.metiers(guid)) do if not RECOLTE[m.nom] then out[#out + 1] = m end end
  return out
end
local function rangDe(nom, guid)
  for _, m in ipairs(metiers(guid)) do if m.nom == nom then return m.rang end end
end
-- Mes autres personnages que le socle connaît (« métiers et compétences »), qui ont un métier à monter, par prénom.
local function autres()
  local d = lib:Lire("métiers et compétences", "tous")
  local out, moi = {}, UnitGUID("player")
  for g in pairs(d and d.persos or {}) do
    if g ~= moi and #metiers(g) > 0 then out[#out + 1] = { guid = g, prenom = ns.prenomAutre(g) } end
  end
  table.sort(out, function(a, b) return a.prenom < b.prenom end)
  return out
end

local function nomObjet(id) return lib.NomObjet(id, lib:Lire("objets") or {}, nomsDeSession) end
local COL_ACHATS = {
  { key = "nom", title = "Objet", w = 240, get = function(a) return nomObjet(a.id) end, asc = true },
  { key = "qty", title = "Quantité", w = 70, align = "RIGHT", get = function(a) return a.qty end },
  { key = "cout", title = "Coût", w = 90, align = "RIGHT", get = function(a) return a.cout end, fmt = lib.ArgentCourt },
}

-- La frise de la route : les étapes de haut en bas sur l'axe des points de compétence, une par suite de points sur la même
-- recette, les trous à leur place, l'objectif au bout. Pas proportionnelle aux points : une étape d'un point se lit
-- aussi bien qu'une de cinquante, le niveau de départ est écrit sur l'axe. L'icône est le vrai objet produit (le sort
-- pour un enchantement) : survol = la bulle du jeu ; les clics d'un objet comme partout dans le jeu
-- (HandleModifiedItemClick, clics gauche et droit) : Maj+clic = le lien dans le chat, Ctrl+clic = la cabine d'essayage,
-- Ctrl+clic droit = dans le Brouillon de Composants (qui intercepte ce clic partout).
-- Le trait de l'axe à côté d'une étape a la couleur de sa recette (orange, jaune, vert d'après les seuils du client),
-- coupé aux changements de couleur, en proportion des points ; sous l'étape : sa fourchette (8 fois sur 10), « incertaine »
-- quand elle est surtout verte.
-- ponytail: verticale seulement ; une frise horizontale en option si l'envie vient.
local ETAPE_H, AXE_X, ICONE = 46, 44, 34
local TRAIT_L = 8 -- largeur du trait coloré de l'axe (retour de Virgile : plus large, plus lisible)
local COULEURS = { orange = { 1, 0.5, 0.15 }, jaune = { 1, 0.82, 0 }, vert = { 0.25, 0.8, 0.25 } }
-- Une durée en clair : « 45 s », « 12 min », « 1 h 05 » (AzerothCommune#70).
local function duree(s)
  s = math.floor(s + 0.5)
  if s < 60 then return s .. " s" end
  if s < 3600 then return math.floor(s / 60 + 0.5) .. " min" end
  return ("%d h %02d"):format(math.floor(s / 3600), math.floor(s % 3600 / 60))
end
-- Les outils d'une étape (AzerothCommune#71) : « Marteau de forgeron : tu l'as » en vert, sinon en orange.
local function texteOutils(e)
  local t = {}
  for _, o in ipairs(e.outils or {}) do
    t[#t + 1] = o.a and ("|cff40c040%s : tu l'as|r"):format(o.nom) or ("|cffff9933%s : à avoir|r"):format(o.nom)
  end
  return #t > 0 and (" · " .. table.concat(t, " · ")) or ""
end
-- Le détail d'une étape : « de 25 à 85 · 13 à 18 fabrications (15 en moyenne) · incertaine », un nombre simple pour une
-- étape orange (une fabrication = un point).
local function detailEtape(e)
  local fab
  if e.fourchette and e.fourchette.bas < e.fourchette.haut then
    fab = ("%d à %d fabrications (%d en moyenne)"):format(e.fourchette.bas, e.fourchette.haut, e.fois)
  else fab = ("%d fabrication(s)"):format(e.fois) end
  -- Le net par objet (Maitrise#12) : composants moins revente au marchand du produit, par fabrication. Le patron n'est pas
  -- répété ici : il a sa ligne « Apprendre » (Maitrise#13).
  local net = e.net >= 0 and ("net " .. lib.ArgentCourt(math.floor(e.net + 0.5))) or ("gain " .. lib.ArgentCourt(math.floor(-e.net + 0.5)))
  return ("de %d à %d · %s%s · %s · %s par objet%s"):format(e.de, e.a, fab, e.incertaine and " · |cffff9933incertaine|r" or "",
    e.temps and duree(e.temps) or "temps inconnu", net, texteOutils(e))
end
-- Une ligne d'apprentissage : « Apprendre X — Maître · 25 pa ».
local function texteApprendre(e)
  return ("Apprendre %s — %s · %s"):format(e.nom, e.source, e.prix and lib.ArgentCourt(e.prix) or "prix inconnu")
end
-- Un PNJ où apprendre (ns.endroits) : « Vayn Moongaze, Pitons-du-Tonnerre (45, 60) », la zone d'après la carte du jeu.
function ns.lieu(m)
  local i = m.carte and C_Map and C_Map.GetMapInfo(m.carte)
  local pos = m.x and m.y and (" (%d, %d)"):format(math.floor(m.x + 0.5), math.floor(m.y + 0.5)) or ""
  return (m.nom or ("PNJ " .. tostring(m.pnj))) .. (i and i.name and (", " .. i.name .. pos) or "")
end
local function continent(carte)
  local i = carte and C_Map.GetMapInfo(carte)
  while i and (i.mapType or 0) > 2 and (i.parentMapID or 0) > 0 do i = C_Map.GetMapInfo(i.parentMapID) end
  return i and i.mapID
end
-- Le PNJ le plus commode : dans la zone du joueur, sinon sur son continent, sinon le premier placé.
-- ponytail: pas de distance ; deux PNJ sur le même continent, le premier de la liste.
function ns.meilleurEndroit(liste)
  local ici = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  local c, best = continent(ici), nil
  for _, m in ipairs(liste) do
    if m.carte then
      if m.carte == ici then return m end
      if not best or (continent(m.carte) == c and continent(best.carte) ~= c) then best = m end
    end
  end
  return best or liste[1]
end
-- Clic sur un apprentissage : un point sur la carte du monde (le point suivi du jeu) chez le PNJ le plus commode, et son
-- nom au chat ; un patron à l'HV : « à l'hôtel des ventes ».
function ns.surCarte(e, metier, guid)
  local m = ns.meilleurEndroit(ns.endroits(e, metier, guid))
  if not m then
    print("|cffffd100Maîtrise :|r " .. (e.patronHV and "le patron s'achète à l'hôtel des ventes." or "on ne sait pas où l'apprendre."))
    return
  end
  if m.carte and m.x and m.y and C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(m.carte) then
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(m.carte, m.x / 100, m.y / 100))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    print("|cffffd100Maîtrise :|r point sur la carte : " .. ns.lieu(m))
  else
    print("|cffffd100Maîtrise :|r " .. ns.lieu(m))
  end
end
-- Le lien d'un objet : celui du jeu (chargé par la bulle au survol), sinon un lien fait à la main, que Composants lit
-- aussi bien (il ne regarde que « item:<id> »).
local function lienObjet(id)
  local o = (lib:Lire("objets") or {})[id]
  return (o and o.link) or select(2, C_Item.GetItemInfo(id))
    or ("|cffffffff|Hitem:%d::::::::::::::::|h[%s]|h|r"):format(id, nomObjet(id))
end
local function lienSort(id) return (C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(id)) or (GetSpellLink and GetSpellLink(id)) end
local function iconeSort(id) return (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or (GetSpellTexture and GetSpellTexture(id)) end

local function bulle(self)
  local e = self:GetParent().etape
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  if e.outil then
    if e.objets[1] then GameTooltip:SetItemByID(e.objets[1]) else GameTooltip:SetText(e.nom) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("Outil : %s, à avoir dans tes sacs pour cette étape"):format(e.nom), 1, 0.6, 0.2, true)
    GameTooltip:AddLine("Maj+clic : le lien dans le chat", 0.6, 0.6, 0.6)
    GameTooltip:Show()
    return
  end
  if e.apprendre then
    if e.objetPatron then GameTooltip:SetItemByID(e.objetPatron) elseif e.cle then GameTooltip:SetSpellByID(e.cle) else GameTooltip:SetText(e.nom) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(texteApprendre(e), 0.95, 0.65, 0.25)
    if ns.appris(e, res.metier, res.guid) then GameTooltip:AddLine("Appris (vu par Azeroth Commune)", 0.25, 0.8, 0.25) end
    local ou = ns.endroits(e, res.metier, res.guid)
    for i = 1, math.min(3, #ou) do GameTooltip:AddLine(ns.lieu(ou[i]), 0.8, 0.8, 0.8) end
    if #ou > 3 then GameTooltip:AddLine(("et %d autres"):format(#ou - 3), 0.8, 0.8, 0.8) end
    GameTooltip:AddLine(#ou > 0 and "Clic : un point sur la carte (ta zone, ton continent d'abord)" or (e.patronHV and "À l'hôtel des ventes" or "Où l'apprendre : inconnu"), 0.6, 0.6, 0.6)
    if e.cle or e.objetPatron then GameTooltip:AddLine("Maj+clic : le lien dans le chat", 0.6, 0.6, 0.6) end
    if e.objetPatron then GameTooltip:AddLine("Ctrl+clic droit : dans le Brouillon de Composants", 0.6, 0.6, 0.6) end
    GameTooltip:Show()
    return
  end
  if e.objet then GameTooltip:SetItemByID(e.objet) else GameTooltip:SetSpellByID(e.cle) end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(("De %d à %d : %d fabrication(s)"):format(e.de, e.a, e.fois), 1, 0.82, 0)
  for _, c in ipairs(e.composants) do GameTooltip:AddLine(("%d × %s"):format(c.qty * e.fois, nomObjet(c.id)), 0.8, 0.8, 0.8) end
  GameTooltip:AddLine("Maj+clic : le lien dans le chat", 0.6, 0.6, 0.6)
  if e.objet then GameTooltip:AddLine("Ctrl+clic droit : dans le Brouillon de Composants", 0.6, 0.6, 0.6) end
  GameTooltip:Show()
end
local function clic(self, bouton)
  local e = self:GetParent().etape
  if e.apprendre and bouton == "LeftButton" and not IsModifierKeyDown() then ns.surCarte(e, res.metier, res.guid) return end
  -- Un patron (ligne « Apprendre ») ou le produit d'une étape : les clics d'un objet ; sinon (maître, enchantement) le sort.
  local id = e.objetPatron or e.objet or (e.outil and e.objets[1])
  if id then
    HandleModifiedItemClick(lienObjet(id))
  elseif e.cle and IsModifiedClick("CHATLINK") then
    local l = lienSort(e.cle)
    if l then ChatEdit_InsertLink(l) end
  end
end

local function construireFrise(parent)
  frise = { etapes = {}, largeur = 600 }
  frise.scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  frise.scroll:SetPoint("TOPLEFT", 14, -HAUT)
  frise.scroll:SetPoint("BOTTOMRIGHT", -32, 14)
  frise.contenu = CreateFrame("Frame", nil, frise.scroll)
  frise.contenu:SetSize(frise.largeur, 1)
  frise.scroll:SetScrollChild(frise.contenu)
  frise.axe = frise.contenu:CreateTexture(nil, "BACKGROUND")
  frise.axe:SetColorTexture(0.66, 0.56, 1, 0.35)
  frise.axe:SetPoint("TOPLEFT", AXE_X - 1, -ETAPE_H / 2)
  frise.axe:SetWidth(2)
end

local function cadreEtape(i)
  local r = frise.etapes[i]
  if r then return r end
  r = CreateFrame("Frame", nil, frise.contenu)
  r:SetSize(frise.largeur, ETAPE_H)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * ETAPE_H)
  r.niveau = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  r.niveau:SetPoint("RIGHT", r, "LEFT", AXE_X - 10, 0)
  -- Un tiret qui part du trait vers l'étape (pas un point coloré sur l'axe : il brouillait les couleurs des recettes).
  r.point = r:CreateTexture(nil, "ARTWORK")
  r.point:SetSize(ICONE / 2 - TRAIT_L / 2 + 4, 2)
  r.point:SetPoint("LEFT", r, "LEFT", AXE_X + TRAIT_L / 2, 0)
  r.traits = {}
  r.icone = CreateFrame("Button", nil, r)
  r.icone:SetSize(ICONE, ICONE)
  r.icone:SetPoint("LEFT", AXE_X + 14, 0)
  r.icone.tex = r.icone:CreateTexture(nil, "ARTWORK")
  r.icone.tex:SetAllPoints()
  r.icone:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  r.icone:SetScript("OnEnter", bulle)
  r.icone:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r.icone:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.icone:SetScript("OnClick", clic)
  -- Un apprentissage fait (vu par le socle) : coché sur sa propre icône.
  r.coche = r.icone:CreateTexture(nil, "OVERLAY")
  r.coche:SetSize(20, 20)
  r.coche:SetPoint("BOTTOMRIGHT", 4, -4)
  r.coche:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
  r.nom = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.nom:SetPoint("TOPLEFT", AXE_X + 14 + ICONE + 10, -7)
  r.nom:SetPoint("RIGHT", -6, 0)
  r.nom:SetJustifyH("LEFT")
  r.nom:SetWordWrap(false)
  r.detail = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  r.detail:SetPoint("TOPLEFT", r.nom, "BOTTOMLEFT", 0, -4)
  r.detail:SetPoint("RIGHT", -6, 0)
  r.detail:SetJustifyH("LEFT")
  r.detail:SetWordWrap(false)
  frise.etapes[i] = r
  return r
end

-- Les traits de l'axe de l'étape sur la hauteur de sa ligne, un par plage de couleur, au prorata des points.
local function traitsEtape(r, e)
  local n, y = (e.a or 0) - e.de, 0
  for i, pl in ipairs(e.plages or {}) do
    local t = r.traits[i]
    if not t then
      t = r:CreateTexture(nil, "ARTWORK", nil, -1) -- sous le rond de l'étape
      t:SetWidth(TRAIT_L)
      r.traits[i] = t
    end
    local h = ETAPE_H * (pl.a - pl.de) / n
    local c = COULEURS[pl.couleur]
    t:SetColorTexture(c[1], c[2], c[3], 1)
    t:ClearAllPoints()
    t:SetPoint("TOP", r, "TOPLEFT", AXE_X, -(ETAPE_H / 2 + y))
    t:SetHeight(h)
    t:Show()
    y = y + h
  end
  for i = #(e.plages or {}) + 1, #r.traits do r.traits[i]:Hide() end
end

-- Une ligne d'apprentissage, cochée quand le socle voit le rang ou la recette appris (relu à chaque majBouton, pas deviné) ;
-- sinon où l'apprendre (le PNJ le plus commode, ns.endroits).
local function dessinerApprendre(r, e)
  local fait = ns.appris(e, res.metier, res.guid)
  r.coche:SetShown(fait)
  r.icone.tex:SetDesaturated(fait)
  if fait then
    r.nom:SetText("|cff40c040Appris : " .. e.nom .. "|r")
    r.detail:SetText("vu par Azeroth Commune")
    return
  end
  r.nom:SetText("|cfff2a640" .. texteApprendre(e) .. "|r")
  local m = ns.meilleurEndroit(ns.endroits(e, res.metier, res.guid))
  r.detail:SetText("à apprendre avant l'étape suivante" .. (m and (" · " .. ns.lieu(m)) or e.patronHV and " · à l'hôtel des ventes" or ""))
end
local function cocher()
  for _, r in ipairs(frise.etapes) do if r.etape and r.etape.apprendre and r:IsShown() then dessinerApprendre(r, r.etape) end end
end

local function dessinerFrise()
  local etapes = res and ns.etapesFrise(res) or {}
  for i, e in ipairs(etapes) do
    local r = cadreEtape(i)
    r.etape = e
    r.niveau:SetText((e.apprendre or e.outil) and "" or e.de) -- une ligne « Apprendre » garde sa place sur l'axe, sans répéter le niveau
    r.icone:SetShown(not e.trou and not e.fin)
    r.coche:Hide()
    r.icone.tex:SetDesaturated(false)
    traitsEtape(r, e)
    if e.outil then
      r.point:SetColorTexture(0.85, 0.85, 0.85, 0.7)
      r.icone.tex:SetTexture(e.objets[1] and C_Item.GetItemIconByID(e.objets[1]) or "Interface\\Icons\\INV_Misc_QuestionMark")
      r.nom:SetText("|cffff9933Outil : " .. e.nom .. "|r")
      r.detail:SetText(e.inconnu and "sacs pas encore relevés : à avoir pour l'étape suivante" or "à avoir dans tes sacs pour l'étape suivante")
    elseif e.apprendre then
      r.point:SetColorTexture(0.85, 0.85, 0.85, 0.7) -- un tiret neutre, comme une étape : l'axe garde les couleurs des recettes
      r.icone.tex:SetTexture("Interface\\Icons\\INV_Misc_Book_11")
      dessinerApprendre(r, e)
    elseif e.trou then
      r.point:SetColorTexture(0.9, 0.3, 0.3, 1)
      r.nom:SetText("|cffff9933Aucune recette de source connue|r")
      r.detail:SetText(("de %d à %d"):format(e.de, e.a))
    elseif e.fin then
      r.point:SetColorTexture(0.35, 0.8, 0.45, 1)
      r.nom:SetText("Objectif : " .. e.de)
      r.detail:SetText("")
    else
      r.point:SetColorTexture(0.85, 0.85, 0.85, 0.7)
      r.icone.tex:SetTexture(e.objet and C_Item.GetItemIconByID(e.objet) or iconeSort(e.cle) or "Interface\\Icons\\INV_Misc_QuestionMark")
      r.nom:SetText(e.nom or "?")
      r.detail:SetText(detailEtape(e))
    end
    r:Show()
  end
  for i = #etapes + 1, #frise.etapes do frise.etapes[i]:Hide(); frise.etapes[i].etape = nil end
  frise.contenu:SetHeight(math.max(1, #etapes * ETAPE_H))
  frise.axe:SetHeight(math.max(1, (#etapes - 1) * ETAPE_H))
  frise.axe:SetShown(#etapes > 1)
  frise.scroll:SetVerticalScroll(0)
end

local function onglet(i)
  PanelTemplates_SetTab(frame, i)
  for k, v in ipairs(vues) do v:SetShown(k == i) end
end

-- Le résumé sous les réglages (Maitrise#12) : en-tête de la tranche, puis deux colonnes de postes (composants, ventes au
-- marchand, maître et patrons | net, net une fois sur dix, temps de fabrication), puis les avertissements (HV pas scanné, composants sans
-- prix en rouge, trous en orange). Le total net = composants + maître et patrons − ventes au marchand.
local function postes(r)
  local inconnus = 0
  for _, a in ipairs(r.apprentissages or {}) do if a.prix == nil then inconnus = inconnus + 1 end end
  local appr = lib.ArgentCourt(r.patrons) .. (inconnus > 0 and (" + %d prix inconnu%s"):format(inconnus, inconnus > 1 and "s" or "") or "")
  return ("Composants : %s\nVentes au marchand : %s\nMaître et patrons : %s"):format(lib.ArgentCourt(r.totalAchats),
      lib.ArgentCourt(r.revente), appr),
    ("|cffffd100Total net : %s|r\nJusqu'à %s une fois sur dix\nTemps de fabrication : %s"):format(lib.ArgentCourt(r.net),
      lib.ArgentCourt(r.netUneSurDix), duree(r.temps or 0) .. (r.tempsIncomplet and " et des temps inconnus" or ""))
end
-- La frise et le tableau des achats démarrent juste sous la dernière ligne de l'en-tête : sans avertissement, pas de vide
-- réservé (retour de Virgile, captures du 23/11). haut = hauteur des avertissements écrits (0 sans).
local function placerContenu(haut)
  local y = 150 + haut + 8
  frise.scroll:ClearAllPoints()
  frise.scroll:SetPoint("TOPLEFT", 14, -y)
  frise.scroll:SetPoint("BOTTOMRIGHT", -32, 14)
  if tabAchats.header then
    tabAchats.header:ClearAllPoints()
    tabAchats.header:SetPoint("TOPLEFT", 14, -(y + 4))
  end
end
local function ecrireResume()
  if not res then
    resume.titre:SetText("Choisis un métier et jusqu'où le monter, puis Calculer.")
    resume.gauche:SetText(""); resume.droite:SetText(""); resume.avert:SetText("")
    return
  end
  local prix
  if res.sansHV then prix = "|cffe64d4dHV pas scanné : prix des marchands seulement.|r"
  else prix = "prix : " .. (res.scan and ("scan de l'HV du " .. res.scan) or ("cours de " .. tostring(res.fournisseur or "l'HV"))) end
  local qui = ns.prenomAutre(res.guid)
  resume.titre:SetText(("|cffffd100%s%s, de %d à %d|r · %s"):format(qui and (qui .. " · ") or "", res.metier, res.de, res.a, prix))
  local g, d = postes(res)
  resume.gauche:SetText(g)
  resume.droite:SetText(d)
  local l = {}
  if #res.sansPrix > 0 then
    l[#l + 1] = ("|cffe64d4d%d composant(s) sans prix : les recettes qui en ont besoin sont écartées.|r"):format(#res.sansPrix)
  end
  if not res.connuesLues and #(res.apprentissages or {}) > 0 then
    l[#l + 1] = "|cffff9933Recettes connues pas encore relevées : toutes celles de la route sont listées à apprendre.|r"
  end
  if #res.trous > 0 then
    local t = {}
    for _, h in ipairs(res.trous) do t[#t + 1] = ("%d – %d"):format(h.de, h.a) end
    l[#l + 1] = "|cffff9933Aucune recette de source connue de " .. table.concat(t, ", ") .. ".|r"
  end
  resume.avert:SetText(table.concat(l, "\n"))
  placerContenu(#l > 0 and (resume.avert:GetStringHeight() + 6) or 0)
end
local function afficher(r)
  res = r
  dessinerFrise()
  tabAchats:SetData(res.achats)
  ecrireResume()
end

-- Deux rôles séparés (retour de Virgile sur la PR #14) : Calculer calcule et affiche, sans jamais toucher au projet ; le
-- bouton du projet enregistre la route affichée dans le projet de Composants (« En faire un projet » sans tranche,
-- « Mettre à jour le projet » avec), grisé tant qu'aucune route n'est calculée pour ce métier. La progression de la
-- tranche (compétence sur le curseur) est dans le titre de la fenêtre. Relu à l'ouverture, à chaque gain de compétence
-- (signal du socle, AzerothCommune#69) et toutes les 5 s tant que la fenêtre est ouverte, par le socle seulement (jamais
-- GetProfessions) ; au curseur atteint, la tranche se termine.
local function majBouton()
  if not (frame and frame:IsShown() and choix) then return end
  local e = ns.trancheEtat(choix, perso)
  frame.title:SetText(e and ("Maîtrise · tranche %s"):format(e.texte) or "Maîtrise")
  etatB:SetText(e and "Mettre à jour le projet" or "En faire un projet")
  etatB:SetEnabled(res ~= nil and res.metier == choix and res.guid == (perso or UnitGUID("player")))
  if res then cocher() end
end

local function bulleTranche(self)
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
  local t = choix and ns.trancheDe(choix, perso)
  if t then
    GameTooltip:AddLine("Mettre à jour le projet", 1, 0.82, 0)
    GameTooltip:AddLine(("Le projet tient aujourd'hui %s de %d à %d ; il prend la route affichée."):format(choix, t.de, t.a), 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine("Clic droit : ouvrir le projet, ou abandonner la tranche", 0.6, 0.6, 0.6)
  else
    GameTooltip:AddLine("En faire un projet", 1, 0.82, 0)
    GameTooltip:AddLine("Un projet Composants tenu avec la route affichée : les besoins de cette tranche seulement.", 0.8, 0.8, 0.8, true)
  end
  GameTooltip:Show()
end

-- Clic : la route affichée devient la tranche (créée, ou le même projet mis à jour : choix de case gardés), Maîtrise se
-- ferme et le projet s'ouvre dans Composants, en Préparer (Composants s'en charge ; Maîtrise ne sert qu'à choisir,
-- Maitrise#30). Clic droit, avec une tranche : ouvrir le projet, ou abandonner la tranche.
local function clicTranche(_, bouton)
  if not choix then return end
  local t = ns.trancheDe(choix, perso)
  if t and bouton == "RightButton" then
    MenuUtil.CreateContextMenu(etatB, function(_, root)
      root:CreateButton("Ouvrir le projet", function() Composants.Ouvrir(t.projet) end)
      root:CreateButton("Abandonner la tranche", function() ns.trancheAbandonner(choix, perso); majBouton() end)
    end)
    return
  end
  local nouvelle, err = ns.trancheCreer(choix, res)
  if not nouvelle then print("|cffffd100Maîtrise :|r " .. err)
  else frame:Hide(); Composants.Ouvrir(nouvelle.projet) end
  majBouton()
end

local function calculer()
  if not choix then return end
  local r, err = ns.tranche(perso, choix, tonumber(curseurE:GetText()))
  if not r then print("|cffffd100Maîtrise :|r " .. err) return end
  curseurE:SetText(tostring(r.a)) -- ramené au plafond du personnage s'il le dépassait
  afficher(r)
  majBouton()
end

-- Choisit le métier nom du personnage guid (nil = le connecté).
local function choisir(nom, guid)
  choix, perso, res = nom, guid, nil
  if metierB then metierB:GenerateMenu() end -- choisi sans passer par le menu (à l'ouverture) : son texte suit
  local rang = rangDe(nom, guid) or 0
  local t = ns.trancheDe(nom, guid)
  local plafond, raison = ns.plafondDe(guid)
  curseurE:SetText(tostring(t and math.min(t.a, plafond) or math.min(rang + 10, plafond)))
  plafondT:SetText(raison or "")
  dessinerFrise()
  tabAchats:SetData({})
  ecrireResume()
  majBouton()
end

local function construire()
  frame = lib.Fenetre("MaitriseFrame", "Maîtrise", 660, 520)
  metierB = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
  metierB:SetWidth(220) -- « Riwanon · Travail du cuir (49) »
  metierB:SetPoint("TOPLEFT", 14, -40)
  metierB:SetupMenu(function(_, root)
    local liste = metiers()
    if #liste == 0 then root:CreateTitle("Aucun métier relevé (ouvre une fenêtre de métier)") end
    local function radio(texte, nom, guid)
      root:CreateRadio(texte, function() return choix == nom and perso == guid end, function() choisir(nom, guid) end)
    end
    for _, m in ipairs(liste) do radio(("%s (%d)"):format(m.nom, m.rang), m.nom, nil) end
    -- Mes autres personnages (Maitrise#5) : « Riwanon · Forge (49) », d'après le dernier relevé de chacun.
    local a = autres()
    if #a > 0 then root:CreateDivider(); root:CreateTitle("Mes autres personnages") end
    for _, p in ipairs(a) do
      for _, m in ipairs(metiers(p.guid)) do radio(("%s · %s (%d)"):format(p.prenom, m.nom, m.rang), m.nom, p.guid) end
    end
  end)
  local jusque = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  jusque:SetPoint("LEFT", metierB, "RIGHT", 14, 0)
  jusque:SetText("jusqu'à")
  curseurE = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  curseurE:SetSize(40, 20)
  curseurE:SetPoint("LEFT", jusque, "RIGHT", 10, 0)
  curseurE:SetAutoFocus(false)
  curseurE:SetNumeric(true)
  curseurE:SetMaxLetters(3)
  curseurE:SetScript("OnEnterPressed", function(self) self:ClearFocus(); calculer() end)
  -- Le plafond du curseur au niveau du personnage (Maitrise#4), écrit sous lui : « 225 max : Artisan au niveau 35 ».
  plafondT = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  plafondT:SetPoint("TOPLEFT", curseurE, "BOTTOMLEFT", -4, -3)
  calculB = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  calculB:SetSize(100, 22)
  calculB:SetPoint("LEFT", curseurE, "RIGHT", 12, 0)
  calculB:SetText("Calculer")
  calculB:SetScript("OnClick", calculer)
  etatB = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  etatB:SetSize(200, 22)
  etatB:SetPoint("LEFT", calculB, "RIGHT", 8, 0)
  etatB:SetText("En faire un projet")
  etatB:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  etatB:SetScript("OnClick", clicTranche)
  etatB:SetScript("OnEnter", bulleTranche)
  etatB:SetScript("OnLeave", function() GameTooltip:Hide() end)
  C_Timer.NewTicker(5, majBouton)
  lib:QuandReleve("métiers et compétences", majBouton)
  resume = {}
  local function texte(nom, x, y, droite)
    local t = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("TOPLEFT", x, y)
    if droite then t:SetPoint("RIGHT", -16, 0) end
    t:SetJustifyH("LEFT")
    t:SetSpacing(3)
    resume[nom] = t
  end
  texte("titre", 16, -84, true)
  texte("gauche", 16, -102)
  resume.gauche:SetWidth(280) -- une largeur pour chaque colonne : sans elle, la ligne la plus longue est coupée
  texte("droite", 300, -102, true)
  texte("avert", 16, -150, true)

  vues = {}
  for i = 1, 2 do
    vues[i] = CreateFrame("Frame", nil, frame)
    vues[i]:SetAllPoints()
  end
  construireFrise(vues[1])
  tabAchats = lib.Tableau(vues[2], COL_ACHATS, { name = "achats", sort = "cout", top = HAUT + 4, bottom = 14 })
  frame.Tabs = {}
  for i, nom in ipairs({ "Route", "Achats" }) do
    local t = CreateFrame("Button", nil, frame, "PanelTabButtonTemplate")
    t:SetID(i)
    t:SetText(nom)
    t:SetScript("OnClick", function() onglet(i) end)
    frame.Tabs[i] = t
  end
  frame.Tabs[1]:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 10, 2)
  PanelTemplates_SetNumTabs(frame, 2)
end

-- Ouvre la fenêtre ; sans métier choisi, le premier du personnage connecté.
function ns.ouvrir()
  if not frame then construire() end
  frame:Show()
  onglet(1)
  if not choix then -- le personnage connecté par défaut
    local premier = metiers()[1]
    if premier then choisir(premier.nom) else ecrireResume() end
  end
  majBouton()
  metierB:GenerateMenu() -- le menu affiche le métier coché (les métiers ont pu changer depuis la dernière ouverture)
end

SLASH_MAITRISE1 = "/maitrise"
SlashCmdList.MAITRISE = function() ns.ouvrir() end
lib.Regrouper({ nom = "Maîtrise", dossier = "Maitrise", icone = "Interface\\Icons\\INV_Misc_Book_11", ouvrir = ns.ouvrir })
