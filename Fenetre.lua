-- Maîtrise, la fenêtre (/maitrise) : le joueur vient y faire deux choses — choisir un métier et jusqu'où le monter ce
-- soir, puis lire la route (quelle recette, combien de fois) et ce qu'elle coûte. Un menu des métiers, un curseur, un
-- bouton Calculer (rien ne se recalcule tout seul) ; deux onglets : la Route et les Achats (skill ui-addon).
local _, ns = ...
local lib = AzerothCommune

-- La montée des métiers de récolte et de la Pêche ne s'achète pas (hors du PRD).
local RECOLTE = { ["Minage"] = true, ["Herboristerie"] = true, ["Dépeçage"] = true, ["Pêche"] = true }
local nomsDeSession = {}
local frame, metierB, curseurE, calculB, resume, tabRoute, tabAchats, vues
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

local function plage(f) return ("%d – %d"):format(f.de, f.a) end
local COL_ROUTE = {
  { key = "de", title = "Plage", w = 70, get = function(f) return f.de end, fmt = function(_, f) return plage(f) end, asc = true },
  { key = "nom", title = "Recette", w = 240, get = function(f) return f.nom end, asc = true },
  { key = "fois", title = "Fois", w = 50, align = "RIGHT", get = function(f) return f.fois end },
  { key = "patron", title = "Patron", w = 80, align = "RIGHT", get = function(f) return f.patron end,
    fmt = function(v) return v > 0 and lib.ArgentCourt(v) or "" end, tip = "Prix du patron à acheter (une fois)." },
}
local function nomObjet(id) return lib.NomObjet(id, lib:Lire("objets") or {}, nomsDeSession) end
local COL_ACHATS = {
  { key = "nom", title = "Objet", w = 240, get = function(a) return nomObjet(a.id) end, asc = true },
  { key = "qty", title = "Quantité", w = 70, align = "RIGHT", get = function(a) return a.qty end },
  { key = "cout", title = "Coût", w = 90, align = "RIGHT", get = function(a) return a.cout end, fmt = lib.ArgentCourt },
}

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

local function calculer()
  if not choix then return end
  local r, err = ns.tranche(nil, choix, tonumber(curseurE:GetText()))
  if not r then print("|cffffd100Maîtrise :|r " .. err) return end
  res = r
  tabRoute:SetData(res.fabrications)
  tabAchats:SetData(res.achats)
  ecrireResume()
end

local function choisir(nom)
  choix, res = nom, nil
  local rang = rangDe(nom) or 0
  curseurE:SetText(tostring(math.min(rang + 10, 300)))
  tabRoute:SetData({})
  tabAchats:SetData({})
  ecrireResume()
end

local function construire()
  frame = lib.Fenetre("MaitriseFrame", "Maîtrise", 560, 460)
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
  tabRoute = lib.Tableau(vues[1], COL_ROUTE, { name = "route", sort = "de", desc = false, top = 128, bottom = 14 })
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
  metierB:GenerateMenu()
  if choix then metierB:OverrideText(("%s (%d)"):format(choix, rangDe(choix) or 0)) end
end

SLASH_MAITRISE1 = "/maitrise"
SlashCmdList.MAITRISE = function() ns.ouvrir() end
lib.Regrouper({ nom = "Maîtrise", dossier = "Maitrise", icone = "Interface\\Icons\\INV_Misc_Book_11", ouvrir = ns.ouvrir })
