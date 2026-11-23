-- Maîtrise, la fenêtre (/maitrise) : le joueur vient y faire deux choses — choisir un métier et jusqu'où le monter ce
-- soir, puis lire la route (quelle recette, combien de fois) et ce qu'elle coûte. Un menu des métiers, un curseur, un
-- bouton Calculer (rien ne se recalcule tout seul) ; deux onglets : la Route (une frise) et les Achats (skill ui-addon).
local _, ns = ...
local lib = AzerothCommune

-- La montée des métiers de récolte et de la Pêche ne s'achète pas (hors du PRD).
local RECOLTE = { ["Minage"] = true, ["Herboristerie"] = true, ["Dépeçage"] = true, ["Pêche"] = true }
local nomsDeSession = {}
local frame, metierB, curseurE, calculB, etatB, resume, tabAchats, vues, frise
local HAUT = 190 -- sous l'en-tête (réglages, résumé de la tranche) : le haut de la frise et du tableau des achats
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
local TRAIT_L = 8 -- largeur du trait coloré de l'axe (retour de Virgile : plus large, plus lisible)
local COULEURS = { orange = { 1, 0.5, 0.15 }, jaune = { 1, 0.82, 0 }, vert = { 0.25, 0.8, 0.25 } }
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
  return ("de %d à %d · %s%s · %s par objet"):format(e.de, e.a, fab, e.incertaine and " · |cffff9933incertaine|r" or "", net)
end
-- Une ligne d'apprentissage : « Apprendre X — Maître · 25 pa ».
local function texteApprendre(e)
  return ("Apprendre %s — %s · %s"):format(e.nom, e.source, e.prix and lib.ArgentCourt(e.prix) or "prix inconnu")
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
  if e.apprendre then
    if e.objetPatron then GameTooltip:SetItemByID(e.objetPatron) else GameTooltip:SetSpellByID(e.cle) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(texteApprendre(e), 0.95, 0.65, 0.25)
    GameTooltip:AddLine("Maj+clic : le lien dans le chat", 0.6, 0.6, 0.6)
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
local function clic(self)
  local e = self:GetParent().etape
  -- Un patron (ligne « Apprendre ») ou le produit d'une étape : les clics d'un objet ; sinon (maître, enchantement) le sort.
  local id = e.objetPatron or e.objet
  if id then
    HandleModifiedItemClick(lienObjet(id))
  elseif IsModifiedClick("CHATLINK") then
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

local function dessinerFrise()
  local etapes = res and ns.etapesFrise(res) or {}
  for i, e in ipairs(etapes) do
    local r = cadreEtape(i)
    r.etape = e
    r.niveau:SetText(e.apprendre and "" or e.de) -- une ligne « Apprendre » garde sa place sur l'axe, sans répéter le niveau
    r.icone:SetShown(not e.trou and not e.fin)
    traitsEtape(r, e)
    if e.apprendre then
      r.point:SetColorTexture(0.85, 0.85, 0.85, 0.7) -- un tiret neutre, comme une étape : l'axe garde les couleurs des recettes
      r.icone.tex:SetTexture("Interface\\Icons\\INV_Misc_Book_11")
      r.nom:SetText("|cfff2a640" .. texteApprendre(e) .. "|r")
      r.detail:SetText("à apprendre avant l'étape suivante")
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
-- marchand, maître et patrons | net, net une fois sur dix), puis les avertissements (HV pas scanné, composants sans
-- prix en rouge, trous en orange). Le total net = composants + maître et patrons − ventes au marchand.
local function postes(r)
  local inconnus = 0
  for _, a in ipairs(r.apprentissages or {}) do if a.prix == nil then inconnus = inconnus + 1 end end
  local appr = lib.ArgentCourt(r.patrons) .. (inconnus > 0 and (" + %d prix inconnu%s"):format(inconnus, inconnus > 1 and "s" or "") or "")
  return ("Composants : %s\nVentes au marchand : %s\nMaître et patrons : %s"):format(lib.ArgentCourt(r.totalAchats),
      lib.ArgentCourt(r.revente), appr),
    ("|cffffd100Total net : %s|r\nJusqu'à %s une fois sur dix"):format(lib.ArgentCourt(r.net), lib.ArgentCourt(r.netUneSurDix))
end
-- La frise et le tableau des achats démarrent juste sous la dernière ligne de l'en-tête : sans avertissement, pas de vide
-- réservé (retour de Virgile, captures du 23/11). haut = hauteur des avertissements écrits (0 sans).
local function placerContenu(haut)
  local y = 136 + haut + 8
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
  resume.titre:SetText(("|cffffd100%s, de %d à %d|r · %s"):format(res.metier, res.de, res.a, prix))
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
-- tranche (compétence sur le curseur) est dans le titre de la fenêtre. Relu à l'ouverture et toutes les 5 s tant que la
-- fenêtre est ouverte, par le socle seulement (jamais GetProfessions) ; au curseur atteint, la tranche se termine.
local function majBouton()
  if not (frame and frame:IsShown() and choix) then return end
  local e = ns.trancheEtat(choix)
  frame.title:SetText(e and ("Maîtrise · tranche %s"):format(e.texte) or "Maîtrise")
  etatB:SetText(e and "Mettre à jour le projet" or "En faire un projet")
  etatB:SetEnabled(res ~= nil and res.metier == choix)
end

local function bulleTranche(self)
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
  local t = choix and ns.trancheDe(choix)
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

-- Clic : la route affichée devient la tranche (créée, ou le même projet mis à jour : choix de case gardés) et le projet
-- s'ouvre dans Composants. Clic droit, avec une tranche : ouvrir le projet, ou abandonner la tranche.
local function clicTranche(_, bouton)
  if not choix then return end
  local t = ns.trancheDe(choix)
  if t and bouton == "RightButton" then
    MenuUtil.CreateContextMenu(etatB, function(_, root)
      root:CreateButton("Ouvrir le projet", function() Composants.Ouvrir(t.projet) end)
      root:CreateButton("Abandonner la tranche", function() ns.trancheAbandonner(choix); majBouton() end)
    end)
    return
  end
  local nouvelle, err = ns.trancheCreer(choix, res)
  if not nouvelle then print("|cffffd100Maîtrise :|r " .. err)
  else Composants.Ouvrir(nouvelle.projet) end
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
  frame = lib.Fenetre("MaitriseFrame", "Maîtrise", 660, 520)
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
  resume = {}
  local function texte(nom, x, y, droite)
    local t = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("TOPLEFT", x, y)
    if droite then t:SetPoint("RIGHT", -16, 0) end
    t:SetJustifyH("LEFT")
    t:SetSpacing(3)
    resume[nom] = t
  end
  texte("titre", 16, -70, true)
  texte("gauche", 16, -88)
  resume.gauche:SetWidth(280) -- une largeur pour chaque colonne : sans elle, la ligne la plus longue est coupée
  texte("droite", 300, -88, true)
  texte("avert", 16, -136, true)

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
