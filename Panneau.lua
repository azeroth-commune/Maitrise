-- Maîtrise, le panneau de la tranche contre la fenêtre de métier du jeu : la frise en tout petit (une ligne par étape,
-- l'étape en cours surlignée, les passées estompées), pour suivre sa tranche en fabriquant sans ouvrir /maitrise.
-- Montré quand la fenêtre de métier est ouverte sur un métier du personnage connecté (pas celui d'un autre, d'une guilde
-- ou d'un PNJ) qui a une tranche ; enfant de sa page de fabrication, il disparaît avec elle (autre onglet, fermée).
-- Il ne calcule rien (seul un clic dans /maitrise recalcule la route) : il lit les étapes gardées avec la tranche et y
-- place la compétence lue dans la fenêtre de métier, GetBaseProfessionInfo().skillLevel (ProfessionInfo,
-- Blizzard_APIDocumentationGenerated/TradeSkillUITypesDocumentation.lua:370).
-- Gestes d'un objet du jeu (skill ui-addon) : survol = la bulle de l'objet, puis l'étape ; clic = la recette choisie dans
-- la fenêtre de métier, C_TradeSkillUI.OpenRecipe (l'appel du suivi de recettes du jeu,
-- Blizzard_ObjectiveTracker/Blizzard_ProfessionsRecipeTracker.lua:51) ; Maj+clic = le lien dans le chat, Ctrl+clic droit =
-- le Brouillon de Composants (HandleModifiedItemClick). Clic sur l'en-tête : la fenêtre de Maîtrise. Aucun autre bouton.
local _, ns = ...
local lib = AzerothCommune

local LARGEUR, LIGNE, ICONE, ENTETE = 220, 16, 14, 20
local COULEURS = { orange = { 1, 0.5, 0.15 }, jaune = { 1, 0.82, 0 }, vert = { 0.25, 0.8, 0.25 }, gris = { 0.55, 0.55, 0.55 } }

-- Les lignes du panneau (pure : check.lua) d'après les étapes gardées de la tranche, à la compétence s : { etape, etat
-- (« passee », « courante », « avenir »), couleur (de la recette à s, seuils du client lus dans base, la base des recettes
-- du socle ; nil pour un trou, un apprentissage ou une recette pas encore à portée), nom, droite (« 166–172 ×7 ») }.
-- Un apprentissage est passé quand connue(étape) le dit (lu dans le jeu, pas deviné), à faire dès son niveau atteint.
function ns.lignesPanneau(etapes, s, base, connue)
  local out = {}
  for _, e in ipairs(etapes) do
    local l = { etape = e }
    if e.apprendre then
      l.etat = connue(e) and "passee" or (s >= e.de and "courante" or "avenir")
      l.nom = "Apprendre " .. (e.nom or "?")
      l.droite = e.prix and lib.ArgentCourt(e.prix) or "prix ?"
    else
      l.etat = s >= e.a and "passee" or (s >= e.de and "courante" or "avenir")
      if e.trou then
        l.nom, l.droite = "Aucune recette connue", ("%d–%d"):format(e.de, e.a)
      else
        l.nom, l.droite = e.nom or "?", ("%d–%d ×%d"):format(e.de, e.a, e.fois)
        local r = base[e.cle]
        if r and r.yellow and r.grey and s >= (r.level or 1) then l.couleur = ns.couleur({ y = r.yellow, g = r.grey }, s) end
      end
    end
    out[#out + 1] = l
  end
  return out
end

---------------------------------------------------------------------------------------------------
local panneau, lignes = nil, {}

-- Le métier de la fenêtre ouverte, s'il est au joueur : même règle que le bouton Fabriquer de Composants (Fabriquer.lua).
local function metierOuvert()
  local T = C_TradeSkillUI
  if not (T and T.GetBaseProfessionInfo) then return end
  if (T.IsTradeSkillLinked and T.IsTradeSkillLinked()) or (T.IsTradeSkillGuild and T.IsTradeSkillGuild())
    or (T.IsNPCCrafting and T.IsNPCCrafting()) then return end
  local p = T.GetBaseProfessionInfo()
  return p and p.professionName ~= "" and p.professionName or nil, p and p.skillLevel
end

-- Un apprentissage fait, lu dans la fenêtre de métier : un rang, quand son plafond est atteint ; une recette, apprise.
local function connue(e)
  if e.rang then
    local p = C_TradeSkillUI.GetBaseProfessionInfo()
    return p and (p.maxSkillLevel or 0) >= e.rang
  end
  local i = C_TradeSkillUI.GetRecipeInfo(e.cle)
  return i and i.learned
end

local function lien(id, nom)
  return select(2, C_Item.GetItemInfo(id)) or ("|cffffffff|Hitem:%d::::::::::::::::|h[%s]|h|r"):format(id, nom or id)
end

local function bulle(self)
  local e = self.etape
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  if e.trou then
    GameTooltip:AddLine(("Aucune recette de source connue de %d à %d"):format(e.de, e.a), 1, 0.6, 0.2)
  elseif e.apprendre then
    if e.objetPatron then GameTooltip:SetItemByID(e.objetPatron) elseif e.cle then GameTooltip:SetSpellByID(e.cle) else GameTooltip:SetText(e.nom or "?") end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("Apprendre %s — %s · %s"):format(e.nom or "?", e.source or "?", e.prix and lib.ArgentCourt(e.prix) or "prix inconnu"), 0.95, 0.65, 0.25)
    local m = ns.meilleurEndroit(ns.endroits(e, (metierOuvert())))
    if m then GameTooltip:AddLine(ns.lieu(m), 0.8, 0.8, 0.8) end
    GameTooltip:AddLine("Clic : un point sur la carte · Maj+clic : le lien dans le chat", 0.6, 0.6, 0.6)
  else
    if e.objet then GameTooltip:SetItemByID(e.objet) else GameTooltip:SetSpellByID(e.cle) end
    GameTooltip:AddLine(" ")
    local f = e.fourchette
    GameTooltip:AddLine(("De %d à %d : %d fabrication(s)%s"):format(e.de, e.a, e.fois,
      (f and f.bas < f.haut) and (", %d à %d 8 fois sur 10"):format(f.bas, f.haut) or ""), 1, 0.82, 0)
    GameTooltip:AddLine("Clic : la recette dans la fenêtre de métier · Maj+clic : le lien", 0.6, 0.6, 0.6)
  end
  GameTooltip:Show()
end

local function clic(self, bouton)
  local e = self.etape
  if e.trou then return end
  if IsModifierKeyDown() then
    local id = e.objetPatron or e.objet
    if id then
      HandleModifiedItemClick(lien(id, e.nom))
    elseif e.cle and IsModifiedClick("CHATLINK") then
      local l = C_Spell.GetSpellLink(e.cle)
      if l then ChatEdit_InsertLink(l) end
    end
  elseif bouton == "LeftButton" and e.apprendre then
    ns.surCarte(e, (metierOuvert()))
  elseif bouton == "LeftButton" and connue(e) then
    C_TradeSkillUI.OpenRecipe(e.cle)
  end
end

local function construire()
  panneau = CreateFrame("Frame", "MaitrisePanneau", ProfessionsFrame.CraftingPage or ProfessionsFrame, "BackdropTemplate")
  panneau:SetWidth(LARGEUR)
  panneau:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  panneau:SetBackdropColor(0.06, 0.06, 0.08, 0.96) -- comme les fenêtres du socle (AzerothCommune.Fenetre)
  panneau:SetBackdropBorderColor(0.66, 0.56, 1.00, 0.35)
  local h = CreateFrame("Button", nil, panneau)
  h:SetPoint("TOPLEFT", 4, -2)
  h:SetPoint("TOPRIGHT", -4, -2)
  h:SetHeight(ENTETE - 2)
  h:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  h.titre = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  h.titre:SetPoint("LEFT", 2, 0)
  h.niveau = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  h.niveau:SetPoint("RIGHT", -2, 0)
  h:SetScript("OnClick", function() ns.ouvrir() end)
  h:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
    GameTooltip:AddLine("Maîtrise : la tranche en cours")
    GameTooltip:AddLine("Clic : ouvrir Maîtrise (le détail, les achats, recalculer)", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  h:SetScript("OnLeave", function() GameTooltip:Hide() end)
  panneau.entete = h
  -- Plus de lignes que la fenêtre de métier n'est haute : elles défilent (la barre n'est montrée qu'alors).
  local sc = CreateFrame("ScrollFrame", nil, panneau, "UIPanelScrollFrameTemplate")
  sc.scrollBarHideable = true -- lu par le modèle à chaque changement de hauteur (SecureScrollTemplates.lua:83)
  -- ponytail: le simulateur rend une hauteur défilable fausse (celle du contenu) et remontre la barre ; on tient la nôtre.
  hooksecurefunc(sc.ScrollBar, "Show", function(self) if not panneau.deborde then self:Hide() end end)
  panneau.scroll = sc
  panneau.contenu = CreateFrame("Frame", nil, sc)
  panneau.contenu:SetSize(LARGEUR - 8, 1)
  sc:SetScrollChild(panneau.contenu)
  panneau.vide = panneau:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  panneau.vide:SetPoint("TOPLEFT", 8, -ENTETE - 2)
  panneau.vide:SetWidth(LARGEUR - 16)
  panneau.vide:SetJustifyH("LEFT")
  panneau.vide:SetText("Tranche d'une version précédente : « Mettre à jour le projet » dans Maîtrise pour la voir ici.")
end

local function ligne(i)
  local b = lignes[i]
  if b then return b end
  b = CreateFrame("Button", nil, panneau.contenu)
  b:SetHeight(LIGNE)
  b:SetPoint("TOPLEFT", 0, -(i - 1) * LIGNE)
  b:SetPoint("RIGHT", panneau.contenu, "RIGHT")
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  b.fond = b:CreateTexture(nil, "BACKGROUND")
  b.fond:SetAllPoints()
  b.fond:SetColorTexture(1, 1, 1, 0.12) -- l'étape en cours (neutre : la couleur du nom reste lisible)
  b.icone = b:CreateTexture(nil, "ARTWORK")
  b.icone:SetSize(ICONE, ICONE)
  b.icone:SetPoint("LEFT", 2, 0)
  b.droite = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.droite:SetPoint("RIGHT", -2, 0)
  b.nom = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.nom:SetPoint("LEFT", b.icone, "RIGHT", 4, 0)
  b.nom:SetPoint("RIGHT", b.droite, "LEFT", -4, 0)
  b.nom:SetJustifyH("LEFT")
  b.nom:SetWordWrap(false)
  b:SetScript("OnEnter", bulle)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnClick", clic)
  lignes[i] = b
  return b
end

local function rafraichir()
  local nom, s
  if ProfessionsFrame and ProfessionsFrame:IsShown() then nom, s = metierOuvert() end
  local t = nom and ns.trancheDe(nom)
  if not t then
    if panneau then panneau:Hide() end
    return
  end
  if not panneau then construire() end
  -- Contre le bord droit, en haut, après les onglets des métiers que la fenêtre de Forever porte sur ce bord
  -- (ProfessionsOverviewTab, Blizzard_Professions/Camelot/Blizzard_ProfessionsFrame.xml:13).
  local onglet = ProfessionsFrame.ProfessionsOverviewTab
  panneau:ClearAllPoints()
  panneau:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", (onglet and onglet:IsShown() and onglet:GetWidth() or 0) + 4, 0)
  s = s or t.de
  panneau.entete.titre:SetText(("Maîtrise · %s %d à %d"):format(nom, t.de, t.a))
  panneau.entete.niveau:SetText(s)
  local ls = ns.lignesPanneau(t.etapes or {}, s, lib:Lire("base des recettes") or {}, connue)
  local courante
  for i, l in ipairs(ls) do
    local b, e = ligne(i), l.etape
    b.etape = e
    b.icone:SetTexture(e.trou and "Interface\\Icons\\INV_Misc_QuestionMark" or e.apprendre and "Interface\\Icons\\INV_Misc_Book_11"
      or (e.objet and C_Item.GetItemIconByID(e.objet)) or C_Spell.GetSpellTexture(e.cle) or "Interface\\Icons\\INV_Misc_QuestionMark")
    b.nom:SetText(l.nom)
    b.droite:SetText(l.droite)
    local c = l.couleur and COULEURS[l.couleur] or (e.apprendre and { 0.95, 0.65, 0.25 }) or (e.trou and { 0.9, 0.3, 0.3 }) or { 0.8, 0.8, 0.8 }
    b.nom:SetTextColor(c[1], c[2], c[3])
    b.fond:SetShown(l.etat == "courante")
    b:SetAlpha(l.etat == "passee" and 0.45 or 1)
    b.icone:SetDesaturated(l.etat == "passee")
    b:Show()
    if l.etat == "courante" and not courante then courante = i end
  end
  for i = #ls + 1, #lignes do lignes[i]:Hide() end
  panneau.vide:SetShown(t.etapes == nil)
  -- La hauteur suit les lignes, jamais plus que la fenêtre de métier ; au-delà, la liste défile jusqu'à l'étape en cours.
  local contenu = math.max(#ls * LIGNE, t.etapes and 0 or 30)
  local h = math.min(ENTETE + contenu + 6, math.floor(ProfessionsFrame:GetHeight()))
  local deborde = ENTETE + contenu + 6 > h
  panneau.deborde = deborde
  panneau:SetHeight(h)
  panneau.scroll:ClearAllPoints()
  panneau.scroll:SetPoint("TOPLEFT", 4, -ENTETE)
  panneau.scroll:SetPoint("BOTTOMRIGHT", deborde and -26 or -4, 4)
  panneau.scroll.ScrollBar:SetShown(deborde)
  panneau.contenu:SetSize(LARGEUR - (deborde and 30 or 8), math.max(1, #ls * LIGNE))
  local visible = h - ENTETE - 6
  panneau.scroll:SetVerticalScroll(deborde and courante and math.max(0, math.min((courante - 3) * LIGNE, #ls * LIGNE - visible)) or 0)
  panneau:Show()
end

-- Fenêtre de métier ouverte, fermée ou mise à jour (une recette apprise), compétence changée (le signal des métiers du
-- socle, émis à chaque SKILL_LINES_CHANGED, AzerothCommune#69 ; la tranche finie y est déjà retirée), tranche tenue ou
-- lâchée (Composants signale tout changement de projet) : au plus une fois par image d'événements.
local prevu
local function bientot()
  if prevu then return end
  prevu = true
  C_Timer.After(0.2, function() prevu = false; rafraichir() end)
end
local ev = CreateFrame("Frame")
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_CLOSE" }) do ev:RegisterEvent(e) end
ev:SetScript("OnEvent", bientot)
lib:QuandReleve("métiers et compétences", bientot)
Composants.QuandChange(bientot)
