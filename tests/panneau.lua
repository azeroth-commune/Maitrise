-- Le panneau de la tranche contre la fenêtre de métier (wow-ui-sim) : la vraie fenêtre Forever (Blizzard_Professions)
-- chargée ; le simulateur n'a pas de métier, les réponses de C_TradeSkillUI (métier ouvert, compétence, recette apprise)
-- sont celles du test, comme pour le bouton Fabriquer de Composants (Composants/tests/fabriquer.lua).
local function ecouler(s) -- horloge manuelle du simulateur : les minuteries programmées partent
    pcall(A_Admin.SetManualClock, GetTime())
    A_Admin.AdvanceTime(s)
end
local function enfants(f, ok, out)
    out = out or {}
    for _, c in ipairs({ f:GetChildren() }) do
        if ok(c) then out[#out + 1] = c end
        enfants(c, ok, out)
    end
    return out
end

test("Panneau : la tranche en petit contre la fenêtre de métier, une ligne par étape", function()
    if not ProfessionsFrame then C_AddOns.LoadAddOn("Blizzard_Professions") end
    assertNotNil(ProfessionsFrame, "la fenêtre de métier du jeu")
    local guid = UnitGUID("player")
    AzerothCommuneDB.chars[guid].professions = { { name = "Forge", rank = 1, max = 300 } }
    AzerothCommuneMarket[AzerothCommune.MaisonHV()] = { scanned = "22/11 21:00", time = time(), items = {
        [2840] = { tiers = { { price = 40, qty = 2000 } } }, [2835] = { tiers = { { price = 10, qty = 2000 } } } } }
    MaitriseDB = nil
    -- La tranche Forge 1 → 60, faite comme le joueur la fait : Calculer, puis En faire un projet.
    SlashCmdList.MAITRISE("")
    local dd = enfants(MaitriseFrame, function(c) return c.GenerateMenu and c.GetMenuDescription end)[1]
    dd:GenerateMenu()
    for _, e in dd:GetMenuDescription():EnumerateElementDescriptions() do
        if MenuUtil.GetElementText(e) == "Forge (1)" then dd:Pick(e, MenuInputContext.MouseButton, "LeftButton") end
    end
    enfants(MaitriseFrame, function(c) return c:GetObjectType() == "EditBox" end)[1]:SetText("60")
    local function bouton(t) return enfants(MaitriseFrame, function(c) return c:GetObjectType() == "Button" and c.GetText and c:GetText() == t end)[1] end
    bouton("Calculer"):Click()
    bouton("En faire un projet"):Click()
    if ComposantsFrame then ComposantsFrame:Hide() end
    MaitriseFrame:Hide()
    local tranche = assert(MaitriseDB.tranches[guid].Forge, "la tranche tenue")
    assertTrue(#tranche.etapes > 1, "les lignes de la frise gardées avec la tranche")

    local T, garde, ouvertes = C_TradeSkillUI, {}, {}
    -- La compétence : au début de la 2e étape fabriquée (la 1re est passée).
    local fabs = {}
    for _, e in ipairs(tranche.etapes) do if not e.apprendre and not e.trou then fabs[#fabs + 1] = e end end
    assertTrue(#fabs >= 2, "au moins deux étapes sur 1 → 60")
    local skill, lie = fabs[2].de, false
    local faux = {
        GetBaseProfessionInfo = function() return { professionName = "Forge", skillLevel = skill, maxSkillLevel = 75 } end,
        IsTradeSkillLinked = function() return lie end,
        IsTradeSkillGuild = function() return false end,
        IsNPCCrafting = function() return false end,
        GetRecipeInfo = function(k) return { recipeID = k, learned = true } end,
        GetCraftableCount = function() return 0 end,
        GetRecipeRequirements = function() return {} end,
        OpenRecipe = function(k) ouvertes[#ouvertes + 1] = k end,
    }
    for n, fn in pairs(faux) do garde[n], T[n] = T[n], fn end
    local ok, err = pcall(function()
        ProfessionsFrame:Show()
        FireEvent("TRADE_SKILL_SHOW")
        ecouler(1)
        local p = MaitrisePanneau
        assertNotNil(p, "le panneau")
        assertTrue(p:IsVisible(), "visible contre la fenêtre de métier")
        assertEquals(220, math.floor(p:GetWidth() + 0.5), "petit : 220 px de large")
        assertTrue(p:GetHeight() <= ProfessionsFrame:GetHeight() + 0.5, "jamais plus haut que la fenêtre de métier")
        local point, rel, relPoint = p:GetPoint(1)
        assertEquals("TOPLEFT TOPRIGHT", point .. " " .. relPoint, "contre le bord droit, en haut")
        assertEquals(ProfessionsFrame, rel)
        local lignes = enfants(p, function(c) return c.etape ~= nil and c:IsShown() end)
        assertEquals(#tranche.etapes, #lignes, "une ligne par étape")
        -- L'étape qui contient la compétence (20) est surlignée, celles d'avant estompées.
        local courantes, passees, cible = 0, 0
        for _, b in ipairs(lignes) do
            local e = b.etape
            if not e.apprendre and not e.trou then
                if e.de <= skill and skill < e.a then courantes = courantes + 1; assertTrue(b.fond:IsShown(), "en cours surlignée"); cible = b end
                if e.a <= skill then passees = passees + 1; assertTrue(b:GetAlpha() < 1, "passée estompée") end
                assertTrue(b.droite:GetText():find(("^%d–%d ×%d$"):format(e.de, e.a, e.fois)) ~= nil, b.droite:GetText())
            end
        end
        assertEquals(1, courantes, "une étape en cours")
        assertTrue(passees > 0, "la 1re étape est passée")
        assertTrue(p.entete.titre:GetText():find("Forge 1 à 60", 1, true) ~= nil, p.entete.titre:GetText())
        assertEquals(tostring(skill), p.entete.niveau:GetText())
        -- Clic : la recette choisie dans la fenêtre de métier.
        cible:GetScript("OnClick")(cible, "LeftButton")
        assertEquals(1, #ouvertes)
        assertEquals(cible.etape.cle, ouvertes[1])
        -- La compétence monte : l'étape en cours suit, sans rien recalculer.
        skill = cible.etape.a
        FireEvent("SKILL_LINES_CHANGED")
        ecouler(1)
        assertTrue(not cible.fond:IsShown() and cible:GetAlpha() < 1, "l'ancienne étape passée")
        assertEquals(tranche, MaitriseDB.tranches[guid].Forge, "la tranche n'est pas recalculée")
        -- Plus de lignes que la fenêtre n'est haute : la hauteur s'arrête à la sienne, la liste défile jusqu'à l'étape en cours.
        local vraies, longues = tranche.etapes, {}
        for i = 1, 60 do longues[i] = { de = i, a = i + 1, cle = cible.etape.cle, nom = "Étape " .. i, fois = 1 } end
        tranche.etapes, skill = longues, 50
        FireEvent("SKILL_LINES_CHANGED")
        ecouler(1)
        assertEquals(math.floor(ProfessionsFrame:GetHeight()), math.floor(p:GetHeight() + 0.5), "pas plus haut que la fenêtre de métier")
        assertTrue(p.scroll.ScrollBar:IsShown(), "la barre de défilement")
        assertTrue(p.scroll:GetVerticalScroll() > 0, "défilée jusqu'à l'étape en cours")
        tranche.etapes = vraies
        -- Clic sur l'en-tête : la fenêtre de Maîtrise.
        p.entete:Click()
        assertTrue(MaitriseFrame:IsShown(), "Maîtrise ouverte")
        MaitriseFrame:Hide()
        -- Le métier d'un autre (lien) : caché.
        lie = true
        FireEvent("TRADE_SKILL_LIST_UPDATE")
        ecouler(1)
        assertTrue(not p:IsShown(), "métier lié : caché")
        lie = false
        -- La fenêtre fermée : le panneau part avec elle.
        FireEvent("TRADE_SKILL_LIST_UPDATE")
        ecouler(1)
        assertTrue(p:IsShown())
        ProfessionsFrame:Hide()
        assertTrue(not p:IsVisible(), "caché avec la fenêtre de métier")
        -- Plus de tranche : plus de panneau.
        ProfessionsFrame:Show()
        MaitriseDB.tranches[guid].Forge = nil
        FireEvent("TRADE_SKILL_SHOW")
        ecouler(1)
        assertTrue(not p:IsShown(), "sans tranche : caché")
    end)
    for n in pairs(faux) do T[n] = garde[n] end
    ProfessionsFrame:Hide()
    if MaitriseFrame then MaitriseFrame:Hide() end
    if ComposantsFrame then ComposantsFrame:Hide() end
    if not ok then error(err, 0) end
end)
