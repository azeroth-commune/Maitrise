-- Maîtrise, la fenêtre (/maitrise) : le joueur vient y faire deux choses — choisir un métier et jusqu'où le monter ce
-- soir, puis lire la route (quelle recette, combien de fois) et ce qu'elle coûte. Un menu des métiers, un curseur, un
-- bouton Calculer (rien ne se recalcule tout seul) ; deux onglets : la Route (une frise) et les Achats (skill ui-addon).
local _, ns = ...
local lib = AzerothCommune

-- La montée des métiers de récolte et de la Pêche ne s'achète pas (hors du PRD).
local RECOLTE = { ["Minage"] = true, ["Herboristerie"] = true, ["Dépeçage"] = true, ["Pêche"] = true }
local nomsDeSession = {}
local frame, metierB, curseurE, calculB, etatB, resume, tabAchats, vues, frise
local choix -- le métier choisi
local res -- la dernière tranche calculée

local function metiers()
  local out = {}
  for _, m in ipairs(ns.metiers()) do if not RECOLTE[m.nom] then out[#out + 1] = m end end
  return out
end
local function rangDe(nom)
  for _, m in ipairs(metiers()) do if m.nom == nom then return m.rang end end
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
local COULEURS = { orange = { 1, 0.5, 0.15 }, jaune = { 1, 0.82, 0 }, vert = { 0.25, 0.8, 0.25 } }
-- Le détail d'une étape : « de 25 à 85 · 13 à 18 fabrications (15 en moyenne) · incertaine », un nombre simple pour une
-- étape orange (une fabrication = un point).
local function detailEtape(e)
  local fab
  if e.fourchette and e.fourchette.bas < e.fourchette.haut then
    fab = ("%d à %d fabrications (%d en moyenne)"):format(e.fourchette.bas, e.fourchette.haut, e.fois)
  else fab = ("%d fabrication(s)"):format(e.fois) end
  return ("de %d à %d · %s%s%s"):format(e.de, e.a, fab, e.incertaine and " · |cffff9933incertaine|r" or "",
    e.patron > 0 and (" · patron " .. lib.ArgentCourt(e.patron)) or "")
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
  if e.objet then GameTooltip:SetItemByID(e.objet) else GameTooltip:SetSpellByID(e.cle) end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(("De %d à %d : %d fabrication(s)"):format(e.de, e.a, e.fois), 1, 0.82, 0)
  for _, c in ipairs(e.composants) do GameTooltip:AddLine(("%d × %s"):format(c.qty * e.fois, nomObjet(c.id)), 0.8, 0.8, 0.8) end
  if e.patron > 0 then GameTooltip:AddLine("Patron à acheter : " .. lib.Argent(e.patron), 0.95, 0.65, 0.25) end
  GameTooltip:AddLine("Maj+clic : le lien dans le chat", 0.6, 0.6, 0.6)
  if e.objet then GameTooltip:AddLine("Ctrl+clic droit : dans le Brouillon de Composants", 0.6, 0.6, 0.6) end
  GameTooltip:Show()
end
local function clic(self)
  local e = self:GetParent().etape
  if e.objet then
    local l = lienObjet(e.objet)
    if l then HandleModifiedItemClick(l) end
  elseif IsModifiedClick("CHATLINK") then
    local l = lienSort(e.cle)
    if l then ChatEdit_InsertLink(l) end
  end
end

local function construireFrise(parent)
  frise = { etapes = {}, largeur = 500 }
  frise.scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  frise.scroll:SetPoint("TOPLEFT", 14, -124)
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
  r.point = r:CreateTexture(nil, "ARTWORK")
  r.point:SetSize(10, 10)
  r.point:SetPoint("CENTER", r, "LEFT", AXE_X, 0)
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
  r.nom = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.nom:SetPoint("TOPLEFT", AXE_X + 14 + ICONE + 10, -7)
  r.nom:SetPoint("RIGHT", -6, 0)
  r.nom:SetJustifyH("LEFT")
  r.nom:SetWordWrap(false)
  r.detail = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  r.detail:SetPoint("TOPLEFT", r.nom, "BOTTOMLEFT", 0, -4)
  r.detail:SetPoint("RIGHT", -6, 0)
  r.detail:SetJustifyH("LEFT")
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
      t:SetWidth(4)
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

local function dessinerFrise()
  local etapes = {}
  if res then
    for _, f in ipairs(res.fabrications) do etapes[#etapes + 1] = f end
    for _, t in ipairs(res.trous) do etapes[#etapes + 1] = { de = t.de, a = t.a, trou = true } end
    table.sort(etapes, function(x, y) return x.de < y.de end)
    etapes[#etapes + 1] = { de = res.a, fin = true }
  end
  for i, e in ipairs(etapes) do
    local r = cadreEtape(i)
    r.etape = e
    r.niveau:SetText(e.de)
    r.icone:SetShown(not e.trou and not e.fin)
    traitsEtape(r, e)
    if e.trou then
      r.point:SetColorTexture(0.9, 0.3, 0.3, 1)
      r.nom:SetText("|cffff9933Aucune recette de source connue|r")
      r.detail:SetText(("de %d à %d"):format(e.de, e.a))
    elseif e.fin then
      r.point:SetColorTexture(0.35, 0.8, 0.45, 1)
      r.nom:SetText("Objectif : " .. e.de)
      r.detail:SetText("")
    else
      r.point:SetColorTexture(0.66, 0.56, 1, 1)
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

-- Le résumé sous les réglages : le coût, la date des prix et ce qui manque (avertissements en rouge, trous en orange).
local function ecrireResume()
  if not res then resume:SetText("Choisis un métier et jusqu'où le monter, puis Calculer.") return end
  local l = { ("|cffffd100%s, de %d à %d|r   achats %s%s · revente au marchand %s · net %s"):format(res.metier, res.de, res.a,
    lib.ArgentCourt(res.totalAchats), res.patrons > 0 and (" + patrons " .. lib.ArgentCourt(res.patrons)) or "",
    lib.ArgentCourt(res.revente), lib.ArgentCourt(res.total - res.revente)) }
  if res.sansHV then l[#l + 1] = "|cffe64d4dHV pas scanné : prix des marchands seulement.|r"
  else l[#l + 1] = "Prix : " .. (res.scan and ("scan de l'HV du " .. res.scan) or ("cours de " .. tostring(res.fournisseur or "l'HV"))) end
  if #res.sansPrix > 0 then
    l[#l + 1] = ("|cffe64d4d%d composant(s) sans prix : les recettes qui en ont besoin sont écartées.|r"):format(#res.sansPrix)
  end
  if #res.trous > 0 then
    local t = {}
    for _, h in ipairs(res.trous) do t[#t + 1] = ("%d – %d"):format(h.de, h.a) end
    l[#l + 1] = "|cffff9933Aucune recette de source connue de " .. table.concat(t, ", ") .. ".|r"
  end
  resume:SetText(table.concat(l, "\n"))
end

local function afficher(r)
  res = r
  dessinerFrise()
  tabAchats:SetData(res.achats)
  ecrireResume()
end

-- Le bouton de la tranche (règle « info cliquable ») : sans tranche, « En faire un projet » ; avec, son état (compétence
-- sur le curseur : la progression, rien d'autre). Relu à l'ouverture et toutes les 5 s tant que la fenêtre est ouverte,
-- par le socle seulement (jamais GetProfessions).
local function majBouton()
  if not (frame and frame:IsShown() and choix) then return end
  local e = ns.trancheEtat(choix)
  if e then etatB:SetText(e.texte); etatB:Enable()
  else etatB:SetText("En faire un projet"); etatB:SetEnabled(res ~= nil and res.metier == choix) end
end

local function bulleTranche(self)
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
  local t = choix and ns.trancheDe(choix)
  if t then
    GameTooltip:AddLine("Tranche en cours", 1, 0.82, 0)
    GameTooltip:AddLine(("%s : de %d à %d."):format(choix, t.de, t.a), 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Clic : recalculer depuis ta compétence jusqu'au même curseur", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Clic droit : reprendre plus haut, ou abandonner", 0.6, 0.6, 0.6)
  else
    GameTooltip:AddLine("Un projet Composants tenu : les besoins de cette tranche seulement.", 0.8, 0.8, 0.8)
  end
  GameTooltip:Show()
end

local function recalculer(curseur)
  local r, err = ns.trancheRecalculer(choix, curseur)
  if not r then print("|cffffd100Maîtrise :|r " .. err) return end
  curseurE:SetText(tostring(r.a))
  afficher(r)
  majBouton()
end

local function clicTranche(_, bouton)
  if not choix then return end
  local t = ns.trancheDe(choix)
  if not t then
    local t, err = ns.trancheCreer(choix, res)
    if not t then print("|cffffd100Maîtrise :|r " .. err)
    else Composants.Ouvrir(t.projet) end -- le projet créé s'ouvre dans Composants
  elseif bouton == "RightButton" then
    MenuUtil.CreateContextMenu(etatB, function(_, root)
      root:CreateButton("Ouvrir le projet", function() Composants.Ouvrir(t.projet) end)
      local c = tonumber(curseurE:GetText())
      -- Sans curseur saisi (ou le même), pas de « Reprendre » : le clic gauche recalcule déjà jusqu'au même curseur.
      if c and c ~= t.a then root:CreateButton(("Reprendre jusqu'à %d"):format(c), function() recalculer(c) end) end
      root:CreateButton("Abandonner la tranche", function() ns.trancheAbandonner(choix); majBouton() end)
    end)
  else
    recalculer()
  end
  majBouton()
end

local function calculer()
  if not choix then return end
  local r, err = ns.tranche(nil, choix, tonumber(curseurE:GetText()))
  if not r then print("|cffffd100Maîtrise :|r " .. err) return end
  afficher(r)
  majBouton()
end

local function choisir(nom)
  choix, res = nom, nil
  if metierB then metierB:GenerateMenu() end -- choisi sans passer par le menu (à l'ouverture) : son texte suit
  local rang = rangDe(nom) or 0
  local t = ns.trancheDe(nom)
  curseurE:SetText(tostring(t and t.a or math.min(rang + 10, 300)))
  dessinerFrise()
  tabAchats:SetData({})
  ecrireResume()
  majBouton()
end

local function construire()
  frame = lib.Fenetre("MaitriseFrame", "Maîtrise", 660, 460)
  metierB = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
  metierB:SetWidth(180)
  metierB:SetPoint("TOPLEFT", 14, -40)
  metierB:SetupMenu(function(_, root)
    local liste = metiers()
    if #liste == 0 then root:CreateTitle("Aucun métier relevé (ouvre une fenêtre de métier)") end
    for _, m in ipairs(liste) do
      root:CreateRadio(("%s (%d)"):format(m.nom, m.rang), function(n) return choix == n end, choisir, m.nom)
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
  calculB = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  calculB:SetSize(100, 22)
  calculB:SetPoint("LEFT", curseurE, "RIGHT", 12, 0)
  calculB:SetText("Calculer")
  calculB:SetScript("OnClick", calculer)
  etatB = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  etatB:SetSize(240, 22)
  etatB:SetPoint("LEFT", calculB, "RIGHT", 8, 0)
  etatB:SetText("En faire un projet")
  etatB:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  etatB:SetScript("OnClick", clicTranche)
  etatB:SetScript("OnEnter", bulleTranche)
  etatB:SetScript("OnLeave", function() GameTooltip:Hide() end)
  C_Timer.NewTicker(5, majBouton)
  resume = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  resume:SetPoint("TOPLEFT", 16, -72)
  resume:SetPoint("RIGHT", -16, 0)
  resume:SetJustifyH("LEFT")
  resume:SetSpacing(3)

  vues = {}
  for i = 1, 2 do
    vues[i] = CreateFrame("Frame", nil, frame)
    vues[i]:SetAllPoints()
  end
  construireFrise(vues[1])
  tabAchats = lib.Tableau(vues[2], COL_ACHATS, { name = "achats", sort = "cout", top = 128, bottom = 14 })
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
  if not choix then
    local premier = metiers()[1]
    if premier then choisir(premier.nom) else ecrireResume() end
  end
  majBouton()
  metierB:GenerateMenu() -- le menu affiche le métier coché (les métiers ont pu changer depuis la dernière ouverture)
end

SLASH_MAITRISE1 = "/maitrise"
SlashCmdList.MAITRISE = function() ns.ouvrir() end
lib.Regrouper({ nom = "Maîtrise", dossier = "Maitrise", icone = "Interface\\Icons\\INV_Misc_Book_11", ouvrir = ns.ouvrir })
