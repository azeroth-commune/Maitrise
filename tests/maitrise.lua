-- Tests d'intégration dans wow-ui-sim (tools/sim.sh test Maitrise) : Maîtrise chargé avec le socle et Composants dans
-- l'interface Forever simulée. La réserve des recettes du socle (RecettesReserve.lua, générée) donne les recettes ; le
-- métier du personnage est posé dans la base du socle.

local function enfants(f, ok, out)
    out = out or {}
    for _, c in ipairs({ f:GetChildren() }) do
        if ok(c) then out[#out + 1] = c end
        enfants(c, ok, out)
    end
    return out
end
local function bouton(texte)
    return enfants(MaitriseFrame, function(c) return c:GetObjectType() == "Button" and c.GetText and c:GetText() == texte end)[1]
end
-- Les étapes affichées de la frise (les cadres qui portent .etape).
local function etapes() return enfants(MaitriseFrame, function(c) return c.etape ~= nil and c:IsVisible() end) end

test("Maîtrise se charge : /maitrise, regroupé avec Azeroth Commune, l'API de tranche", function()
    assertEquals("/maitrise", SLASH_MAITRISE1)
    assertType("function", Maitrise.Tranche)
    local moi
    for _, r in ipairs(AzerothCommune.regroupes) do if r.nom == "Maîtrise" then moi = r end end
    assertNotNil(moi, "Maîtrise regroupé")
end)

test("Maîtrise : la route d'une tranche de Forge, 1 → 40, dans la fenêtre", function()
    local guid = UnitGUID("player")
    AzerothCommuneDB.chars = AzerothCommuneDB.chars or {}
    AzerothCommuneDB.chars[guid] = AzerothCommuneDB.chars[guid] or {}
    AzerothCommuneDB.chars[guid].professions = { { name = "Forge", rank = 1, max = 75 }, { name = "Minage", rank = 30, max = 75 } }
    -- Un scan de l'HV : barre de cuivre, pierre brute (aucun marchand ne les vend).
    AzerothCommuneMarket[AzerothCommune.MaisonHV()] = { scanned = "22/11 21:00", time = time(), items = {
        [2840] = { tiers = { { price = 40, qty = 200 } } }, [2835] = { tiers = { { price = 10, qty = 200 } } } } }
    SlashCmdList.MAITRISE("")
    assertTrue(MaitriseFrame:IsShown())
    local calc = assert(bouton("Calculer"), "bouton Calculer")
    local curseur = enfants(MaitriseFrame, function(c) return c:GetObjectType() == "EditBox" end)[1]
    assertEquals("11", curseur:GetText(), "curseur par défaut : compétence + 10")
    curseur:SetText("40")
    calc:Click()
    local res = assert(Maitrise.Tranche(nil, "Forge", 40))
    assertTrue(#res.fabrications > 0 and #res.trous == 0, "des fabrications, sans trou")
    assertEquals("22/11 21:00", res.scan)
    -- La frise : une étape par fabrication, l'objectif au bout ; chaque fabrication porte l'icône de son objet.
    local vues, manquent = etapes(), 0
    for _, o in ipairs(res.outils) do if not o.a then manquent = manquent + 1 end end
    assertEquals(#res.fabrications + #res.trous + #res.apprentissages + manquent + 1, #vues,
        "les lignes de la frise (étapes, apprentissages, outils qui manquent, objectif)")
    local avecIcone = 0
    for _, r in ipairs(vues) do if r.icone:IsShown() and r.icone.tex:GetTexture() then avecIcone = avecIcone + 1 end end
    assertEquals(#res.fabrications + #res.apprentissages + manquent, avecIcone, "une icône par fabrication, apprentissage et outil")
    -- Ctrl+clic droit sur l'icône, comme sur un objet du jeu : l'objet entre dans le Brouillon de Composants.
    local r1 = vues[1]
    for _, r in ipairs(vues) do if r.etape.objet and (not r1.etape.objet or r.etape.de < r1.etape.de) then r1 = r end end
    local id = assert(r1.etape.objet, "la première étape fabrique un objet")
    local ctrl, alt, maj, souris = IsControlKeyDown, IsAltKeyDown, IsShiftKeyDown, GetMouseButtonClicked
    IsControlKeyDown, IsAltKeyDown, IsShiftKeyDown = function() return true end, function() return false end, function() return false end
    GetMouseButtonClicked = function() return "RightButton" end
    local ok, err = pcall(r1.icone:GetScript("OnClick"), r1.icone, "RightButton")
    IsControlKeyDown, IsAltKeyDown, IsShiftKeyDown, GetMouseButtonClicked = ctrl, alt, maj, souris
    if not ok then error(err, 0) end
    local auBrouillon = false
    for _, l in ipairs(ComposantsDB.brouillon and ComposantsDB.brouillon.lines or {}) do auBrouillon = auBrouillon or l.id == id end
    assertTrue(auBrouillon, "l'objet de l'étape au Brouillon de Composants")
    if ComposantsFrame then ComposantsFrame:Hide() end
    MaitriseFrame:Hide()
end)

-- Le menu des métiers affiche le métier choisi, pas toujours le premier.
test("Maîtrise : le menu des métiers affiche le métier choisi", function()
    local guid = UnitGUID("player")
    AzerothCommuneDB.chars[guid].professions = { { name = "Forge", rank = 1, max = 75 }, { name = "Couture", rank = 20, max = 75 } }
    SlashCmdList.MAITRISE("")
    local dd = enfants(MaitriseFrame, function(c) return c.GenerateMenu and c.GetMenuDescription end)[1]
    local function texte() return dd.Text and dd.Text:GetText() or dd:GetText() end
    dd:GenerateMenu()
    for _, e in dd:GetMenuDescription():EnumerateElementDescriptions() do
        if MenuUtil.GetElementText(e) == "Couture (20)" then dd:Pick(e, MenuInputContext.MouseButton, "LeftButton") end
    end
    assertEquals("Couture (20)", texte())
    local curseur = enfants(MaitriseFrame, function(c) return c:GetObjectType() == "EditBox" end)[1]
    assertEquals("30", curseur:GetText(), "curseur de la Couture : 20 + 10")
    MaitriseFrame:Hide()
    SlashCmdList.MAITRISE("") -- rouvrir garde le choix
    assertEquals("Couture (20)", texte())
    MaitriseFrame:Hide()
end)

-- La tranche tenue (Maitrise#3) : créer depuis la fenêtre, Calculer sans toucher au projet, mettre le projet à jour en
-- gardant les choix, finir au curseur.
test("Maîtrise : la tranche devient un projet tenu, se met à jour et se termine", function()
    local guid = UnitGUID("player")
    local function rang(r) AzerothCommuneDB.chars[guid].professions = { { name = "Forge", rank = r, max = 75 } } end
    rang(1)
    AzerothCommuneMarket[AzerothCommune.MaisonHV()] = { scanned = "22/11 21:00", time = time(), items = {
        [2840] = { tiers = { { price = 40, qty = 200 } } }, [2835] = { tiers = { { price = 10, qty = 200 } } } } }
    MaitriseDB = nil
    SlashCmdList.MAITRISE("")
    local dd = enfants(MaitriseFrame, function(c) return c.GenerateMenu and c.GetMenuDescription end)[1]
    dd:GenerateMenu()
    for _, e in dd:GetMenuDescription():EnumerateElementDescriptions() do
        if MenuUtil.GetElementText(e) == "Forge (1)" then dd:Pick(e, MenuInputContext.MouseButton, "LeftButton") end
    end
    local curseur = enfants(MaitriseFrame, function(c) return c:GetObjectType() == "EditBox" end)[1]
    curseur:SetText("30")
    local faire = assert(bouton("En faire un projet"), "bouton de la tranche")
    assertFalse(faire:IsEnabled(), "rien à tenir avant Calculer")
    bouton("Calculer"):Click()
    assertTrue(faire:IsEnabled())
    faire:Click()
    -- Le projet tenu : lignes fabrication et raison visibles dans Composants.
    local projet
    for _, x in ipairs(Composants.Projets()) do if x.name == "Maîtrise : Forge de 1 à 30" then projet = x end end
    assertNotNil(projet, "projet « Maîtrise : Forge de 1 à 30 » (les niveaux dans le nom)")
    assertEquals("Maîtrise : Forge de 1 à 30", projet.tenu)
    assertTrue(ComposantsFrame:IsShown(), "le projet créé s'ouvre dans Composants")
    assertFalse(MaitriseFrame:IsShown(), "Maîtrise se ferme : on fabrique dans Composants (Maitrise#30)")
    assertEquals(projet, ComposantsDB.projets[ComposantsDB.courant], "sur ce projet")
    ComposantsFrame:Hide()
    SlashCmdList.MAITRISE("")
    assertTrue(#projet.lines > 0 and projet.lines[1].recette ~= nil and projet.lines[1].fois >= 1, "lignes fabrication")
    -- Avec une tranche : le bouton enregistre la route affichée (« Mettre à jour le projet ») ; la progression est dans le
    -- titre de la fenêtre, plus sur un bouton.
    local maj = assert(bouton("Mettre à jour le projet"), "le bouton du projet")
    assertNil(bouton("En faire un projet"))
    assertEquals("Maîtrise · tranche Forge 1 / 30", MaitriseFrame.title:GetText(), "la progression dans le titre")
    -- Calculer ne touche jamais au projet : un autre curseur, calculé, ne change pas la tranche.
    curseur:SetText("20")
    bouton("Calculer"):Click()
    assertEquals("Maîtrise : Forge de 1 à 30", projet.tenu, "Calculer ne touche pas au projet")
    -- Un choix de case, la compétence monte, Calculer puis Mettre à jour : le même projet prend la nouvelle route, le
    -- choix reste, le nom et la raison suivent.
    Composants.Choix(projet, 2840, "acheter")
    rang(11)
    curseur:SetText("30")
    bouton("Calculer"):Click()
    maj:Click()
    assertTrue(ComposantsFrame:IsShown() and not MaitriseFrame:IsShown(), "mis à jour : Maîtrise fermée, le projet montré")
    ComposantsFrame:Hide()
    SlashCmdList.MAITRISE("")
    assertEquals("acheter", projet.choix[2840], "choix de case gardé")
    assertEquals("Maîtrise : Forge de 11 à 30", projet.tenu)
    assertEquals("Maîtrise : Forge de 11 à 30", projet.name, "le nom suit les niveaux")
    assertEquals(1, #Composants.Projets(), "le même projet, pas un autre")
    -- Atteindre le curseur, fenêtre fermée : le gain de compétence (SKILL_LINES_CHANGED), relu et signalé par le socle
    -- (AzerothCommune#69), termine la tranche tout de suite ; le projet est lâché, le bouton redevient « En faire un projet ».
    MaitriseFrame:Hide()
    local gp, gpi = GetProfessions, GetProfessionInfo
    GetProfessions = function() return 1 end
    GetProfessionInfo = function() return "Forge", "icône", 30, 75 end
    local ok, err = pcall(FireEvent, "SKILL_LINES_CHANGED")
    GetProfessions, GetProfessionInfo = gp, gpi
    assert(ok, err)
    assertEquals(nil, projet.tenu, "projet lâché sans ouvrir la fenêtre")
    assertNil(MaitriseDB.tranches[guid].Forge, "tranche terminée au signal")
    SlashCmdList.MAITRISE("")
    assertNotNil(bouton("En faire un projet"), "une autre tranche est possible")
    assertNil(MaitriseDB.tranches[guid].Forge, "tranche oubliée")
    MaitriseFrame:Hide()
    if ComposantsFrame then ComposantsFrame:Hide() end
end)

-- La frise colorée et ses fourchettes (Maitrise#11) : un trait par plage de couleur, la fourchette écrite pour une étape
-- jaune ou verte, « incertaine » pour une étape surtout verte.
test("Maîtrise : la frise colore l'axe et écrit les fourchettes", function()
    local guid = UnitGUID("player")
    AzerothCommuneDB.chars[guid].professions = { { name = "Forge", rank = 1, max = 300 } }
    AzerothCommuneMarket[AzerothCommune.MaisonHV()] = { scanned = "22/11 21:00", time = time(), items = {
        [2840] = { tiers = { { price = 40, qty = 2000 } } }, [2835] = { tiers = { { price = 10, qty = 2000 } } } } }
    MaitriseDB = nil
    SlashCmdList.MAITRISE("")
    local dd = enfants(MaitriseFrame, function(c) return c.GenerateMenu and c.GetMenuDescription end)[1]
    dd:GenerateMenu()
    for _, e in dd:GetMenuDescription():EnumerateElementDescriptions() do
        if MenuUtil.GetElementText(e) == "Forge (1)" then dd:Pick(e, MenuInputContext.MouseButton, "LeftButton") end
    end
    enfants(MaitriseFrame, function(c) return c:GetObjectType() == "EditBox" end)[1]:SetText("150")
    bouton("Calculer"):Click()
    local vues, orange, fourchette, incertaine, traits = etapes(), 0, 0, 0, 0
    for _, r in ipairs(vues) do
        local e = r.etape
        if e.plages then
            for i = 1, #e.plages do assertTrue(r.traits[i]:IsShown(), "un trait par plage de couleur") traits = traits + 1 end
            local d = r.detail:GetText()
            if e.fourchette and e.fourchette.bas < e.fourchette.haut then -- réduite à un nombre : écrite comme un nombre simple
                fourchette = fourchette + 1
                assertTrue(d:find(("%d à %d fabrications (%d en moyenne)"):format(e.fourchette.bas, e.fourchette.haut, e.fois), 1, true) ~= nil, d)
            else
                orange = orange + 1
                assertTrue(d:find("à %d+ fabrications") == nil and d:find("moyenne", 1, true) == nil, "orange : un nombre simple : " .. d)
            end
            if e.incertaine then incertaine = incertaine + 1; assertTrue(d:find("incertaine", 1, true) ~= nil, d) end
        end
    end
    assertTrue(traits > 0 and fourchette > 0 and incertaine > 0, "des traits colorés, des fourchettes et une étape incertaine sur 1 → 150")
    MaitriseFrame:Hide()
end)

test("Maîtrise : un patron à l'HV est dit « patron à l'HV » dans la frise", function()
    local guid = UnitGUID("player")
    AzerothCommuneDB.chars[guid].professions = { { name = "Forge", rank = 229, max = 300 } }
    -- Les Eperons en mithril (sort 9964, 230 → 250) : patron de butin (7989), à l'HV pour 1 pc, composants à l'HV.
    local base = AzerothCommune:Lire("base des recettes")
    assertEquals(7989, base[9964].patron)
    assertEquals("inconnue", base[9964].source)
    local items = { [7989] = { tiers = { { price = 1, qty = 1 } } } }
    for _, rq in ipairs(base[9964].reagents) do items[rq.id] = { tiers = { { price = 10, qty = 2000 } } } end
    AzerothCommuneMarket[AzerothCommune.MaisonHV()] = { scanned = "22/11 21:00", time = time(), items = items }
    MaitriseDB = nil
    SlashCmdList.MAITRISE("")
    local dd = enfants(MaitriseFrame, function(c) return c.GenerateMenu and c.GetMenuDescription end)[1]
    dd:GenerateMenu()
    for _, e in dd:GetMenuDescription():EnumerateElementDescriptions() do
        if MenuUtil.GetElementText(e) == "Forge (229)" then dd:Pick(e, MenuInputContext.MouseButton, "LeftButton") end
    end
    enfants(MaitriseFrame, function(c) return c:GetObjectType() == "EditBox" end)[1]:SetText("250")
    bouton("Calculer"):Click()
    -- Le patron a sa ligne « Apprendre » (Maitrise#13), plus répété sur l'étape.
    local trouve
    for _, r in ipairs(etapes()) do
        if r.etape.cle == 9964 and r.etape.apprendre then
            trouve = true
            assertTrue(r.nom:GetText():find("Patron à l'HV", 1, true) ~= nil, r.nom:GetText())
            assertEquals(7989, r.etape.objetPatron)
        elseif r.etape.cle == 9964 then
            assertTrue(r.etape.patronHV and r.detail:GetText():find("patron", 1, true) == nil, "pas de patron sur l'étape : " .. r.detail:GetText())
        end
    end
    assertTrue(trouve, "une ligne « Apprendre » des Eperons en mithril, patron à l'HV")
    MaitriseFrame:Hide()
end)

-- Le résumé et le net par objet (Maitrise#12), les apprentissages à leur place (Maitrise#13) : tranche de Forge 1 → 40.
test("Maîtrise : le résumé a ses postes, l'étape son net, l'apprentissage sa ligne", function()
    local guid = UnitGUID("player")
    AzerothCommuneDB.chars[guid].professions = { { name = "Forge", rank = 1, max = 300 } }
    AzerothCommuneMarket[AzerothCommune.MaisonHV()] = { scanned = "22/11 21:00", time = time(), items = {
        [2840] = { tiers = { { price = 40, qty = 2000 } } }, [2835] = { tiers = { { price = 10, qty = 2000 } } } } }
    MaitriseDB = nil
    SlashCmdList.MAITRISE("")
    local dd = enfants(MaitriseFrame, function(c) return c.GenerateMenu and c.GetMenuDescription end)[1]
    dd:GenerateMenu()
    for _, e in dd:GetMenuDescription():EnumerateElementDescriptions() do
        if MenuUtil.GetElementText(e) == "Forge (1)" then dd:Pick(e, MenuInputContext.MouseButton, "LeftButton") end
    end
    enfants(MaitriseFrame, function(c) return c:GetObjectType() == "EditBox" end)[1]:SetText("150")
    bouton("Calculer"):Click()
    local res = assert(Maitrise.Tranche(nil, "Forge", 150))
    local texte = {}
    for _, rg in ipairs({ MaitriseFrame:GetRegions() }) do
        if rg.GetText and rg:GetText() then texte[#texte + 1] = rg:GetText() end
    end
    texte = table.concat(texte, "\n")
    local ac = AzerothCommune.ArgentCourt
    for _, morceau in ipairs({ "Composants : " .. ac(res.totalAchats), "Ventes au marchand : " .. ac(res.revente),
        "Maître et patrons : " .. ac(res.patrons), "Total net : " .. ac(res.net), "Jusqu'à " .. ac(res.netUneSurDix) .. " une fois sur dix" }) do
        assertTrue(texte:find(morceau, 1, true) ~= nil, "le résumé dit « " .. morceau .. " » : " .. texte)
    end
    assertTrue(res.netUneSurDix > res.net, "une fois sur dix au-dessus du net")
    local vues, fabs, apprends = etapes(), 0, 0
    for i, r in ipairs(vues) do
        local e = r.etape
        if e.apprendre then
            apprends = apprends + 1
            assertTrue(r.nom:GetText():find("Apprendre " .. e.nom, 1, true) ~= nil, r.nom:GetText())
            assertTrue(r.icone:IsShown(), "une icône (le livre)")
            for _, t in ipairs(r.traits) do assertTrue(not t:IsShown(), "pas de trait coloré propre à un apprentissage (ligne réemployée)") end
        elseif e.plages then
            fabs = fabs + 1
            assertTrue(r.detail:GetText():find(" par objet", 1, true) ~= nil, "net par objet : " .. r.detail:GetText())
        end
    end
    assertEquals(#res.fabrications, fabs)
    assertEquals(#res.apprentissages, apprends, "une ligne par apprentissage")
    MaitriseFrame:Hide()
end)

-- Temps de fabrication (AzerothCommune#70) et outils (AzerothCommune#71), sur la réserve du socle : une tranche de Forge
-- (75 → 110) demande le marteau de forgeron ; sans lui dans les sacs, une ligne « Outil » ; avec, l'étape dit « tu l'as ».
test("Maîtrise : le temps de chaque étape et le total ; l'outil à avoir, ou « tu l'as »", function()
    local guid = UnitGUID("player")
    local fiche = AzerothCommuneDB.chars[guid]
    fiche.professions = { { name = "Forge", rank = 75, max = 300 } }
    AzerothCommuneMarket[AzerothCommune.MaisonHV()] = { scanned = "22/11 21:00", time = time(), items = {
        [2840] = { tiers = { { price = 40, qty = 2000 } } }, [2835] = { tiers = { { price = 10, qty = 2000 } } },
        [2836] = { tiers = { { price = 20, qty = 2000 } } }, [2841] = { tiers = { { price = 80, qty = 2000 } } } } }
    local sacs = fiche.bags
    local function calculer(bags)
        fiche.bags = bags
        MaitriseDB = nil
        MaitriseFrame:Hide()
        SlashCmdList.MAITRISE("")
        local dd = enfants(MaitriseFrame, function(c) return c.GenerateMenu and c.GetMenuDescription end)[1]
        dd:GenerateMenu()
        for _, e in dd:GetMenuDescription():EnumerateElementDescriptions() do
            if MenuUtil.GetElementText(e) == "Forge (75)" then dd:Pick(e, MenuInputContext.MouseButton, "LeftButton") end
        end
        enfants(MaitriseFrame, function(c) return c:GetObjectType() == "EditBox" end)[1]:SetText("110")
        bouton("Calculer"):Click()
        return assert(Maitrise.Tranche(nil, "Forge", 110))
    end
    local ok, err = pcall(function()
        local res = calculer({ Backpack = { size = 16, items = {} } })
        assertTrue(res.temps > 0, "un temps de fabrication")
        local texte = {}
        for _, rg in ipairs({ MaitriseFrame:GetRegions() }) do
            if rg.GetText and rg:GetText() then texte[#texte + 1] = rg:GetText() end
        end
        texte = table.concat(texte, "\n")
        assertTrue(texte:find("Temps de fabrication : %d") ~= nil, "le total au résumé : " .. texte)
        local marteau
        for _, o in ipairs(res.outils) do if o.nom == "Marteau de forgeron" then marteau = o end end
        assertNotNil(marteau, "la Forge demande le marteau de forgeron")
        assertEquals(false, marteau.a)
        local ligne, detail
        for _, r in ipairs(etapes()) do
            if r.etape.outil and r.etape.nom == "Marteau de forgeron" then ligne = r end
            if r.etape.fois and r.etape.outils then detail = r end
        end
        assertNotNil(ligne, "une ligne « Outil » pour le marteau")
        assertTrue(ligne.nom:GetText():find("Outil : Marteau de forgeron", 1, true) ~= nil, ligne.nom:GetText())
        assertTrue(detail.detail:GetText():find("Marteau de forgeron : à avoir", 1, true) ~= nil, detail.detail:GetText())
        -- Le marteau dans les sacs : plus de ligne « Outil », l'étape dit « tu l'as ».
        res = calculer({ Backpack = { size = 16, items = { { id = 5956, count = 1 } } } })
        for _, r in ipairs(etapes()) do
            assertTrue(not (r.etape.outil and r.etape.nom == "Marteau de forgeron"), "plus de ligne Outil pour le marteau")
            if r.etape.fois and r.etape.outils then detail = r end
        end
        assertTrue(detail.detail:GetText():find("Marteau de forgeron : tu l'as", 1, true) ~= nil, detail.detail:GetText())
    end)
    fiche.bags = sacs
    MaitriseFrame:Hide()
    if not ok then error(err, 0) end
end)

-- À apprendre (Maitrise#4) : les rangs et les recettes à apprendre avec leur prix et où, comptés dans le total ; cochés tout
-- seuls quand le socle les voit appris ; le curseur plafonné au niveau du personnage, la raison écrite sous lui.
test("Maîtrise : rangs à apprendre, cochés par le socle, curseur plafonné par le niveau", function()
    local guid = UnitGUID("player")
    local fiche = AzerothCommuneDB.chars[guid]
    local garde = { character = fiche.character, recipes = fiche.recipes, trainers = AzerothCommuneDB.trainers }
    local waypoint, peut = C_Map.SetUserWaypoint, C_Map.CanSetUserWaypointOnMap
    local ok, err = pcall(function()
        fiche.professions = { { name = "Forge", rank = 60, max = 75 } }
        fiche.character = { level = 25 }
        fiche.recipes = { Forge = { rank = 60, max = 75, known = {} } }
        AzerothCommuneDB.trainers = { [9999] = { services = { { name = "Forge de compagnon", skill = "Forge", skill_rank = 50, cost = 450 } } } }
        AzerothCommuneMarket[AzerothCommune.MaisonHV()] = { scanned = "22/11 21:00", time = time(), items = {
            [2840] = { tiers = { { price = 40, qty = 2000 } } }, [2835] = { tiers = { { price = 10, qty = 2000 } } },
            [2836] = { tiers = { { price = 20, qty = 2000 } } }, [2841] = { tiers = { { price = 80, qty = 2000 } } } } }
        MaitriseDB = nil
        if MaitriseFrame then MaitriseFrame:Hide() end
        SlashCmdList.MAITRISE("")
        local dd = enfants(MaitriseFrame, function(c) return c.GenerateMenu and c.GetMenuDescription end)[1]
        dd:GenerateMenu()
        for _, e in dd:GetMenuDescription():EnumerateElementDescriptions() do
            if MenuUtil.GetElementText(e) == "Forge (60)" then dd:Pick(e, MenuInputContext.MouseButton, "LeftButton") end
        end
        local function textes()
            local t = {}
            for _, rg in ipairs({ MaitriseFrame:GetRegions() }) do if rg.GetText and rg:GetText() and rg:IsShown() then t[#t + 1] = rg:GetText() end end
            return table.concat(t, "\n")
        end
        assertTrue(textes():find("225 max : Artisan au niveau 35", 1, true) ~= nil, "la raison sous le curseur : " .. textes())
        local curseur = enfants(MaitriseFrame, function(c) return c:GetObjectType() == "EditBox" end)[1]
        curseur:SetText("260")
        bouton("Calculer"):Click()
        assertEquals("225", curseur:GetText(), "le curseur ramené au plafond")
        local res = assert(Maitrise.Tranche(nil, "Forge", 260))
        assertEquals(225, res.a)
        -- Les rangs : Compagnon au prix du maître relevé, Expert à prix inconnu ; le prix compte dans « Maître et patrons ».
        local compagnon, expert
        for _, r in ipairs(etapes()) do
            if r.etape.rang == 150 then compagnon = r elseif r.etape.rang == 225 then expert = r end
        end
        assertNotNil(compagnon, "une ligne pour le rang Compagnon")
        assertNotNil(expert, "une ligne pour le rang Expert")
        assertTrue(compagnon.nom:GetText():find("Apprendre Compagnon (150) — Maître · " .. AzerothCommune.ArgentCourt(450), 1, true) ~= nil, compagnon.nom:GetText())
        assertTrue(expert.nom:GetText():find("prix inconnu", 1, true) ~= nil, expert.nom:GetText())
        assertTrue(res.patrons >= 450, "le rang compté avec les patrons")
        assertTrue(textes():find("Maître et patrons : " .. AzerothCommune.ArgentCourt(res.patrons), 1, true) ~= nil, textes())
        -- Où : un maître de la Forge de la faction du joueur, d'après le socle (AzerothCommune#80).
        local ou = AzerothCommune.MaitresDuMetier("Forge")
        local f, nom = AzerothCommune.Faction(), nil
        for _, m in ipairs(ou) do if (not m.faction or m.faction == f) and m.nom and compagnon.detail:GetText():find(m.nom, 1, true) then nom = m.nom end end
        assertNotNil(nom, "le maître où l'apprendre : " .. compagnon.detail:GetText())
        -- Clic : un point sur la carte, chez ce maître.
        local vers
        C_Map.CanSetUserWaypointOnMap = function() return true end
        C_Map.SetUserWaypoint = function(p) vers = p end
        compagnon.icone:GetScript("OnClick")(compagnon.icone, "LeftButton")
        assertNotNil(vers, "un point sur la carte")
        -- Coché tout seul : le socle relève le rang appris (plafond à 150) et une recette apprise ; la fenêtre les coche.
        local recette
        for _, r in ipairs(etapes()) do if r.etape.apprendre and r.etape.cle then recette = r end end
        assertNotNil(recette, "une recette à apprendre sur 60 → 225")
        fiche.professions[1].max = 150
        fiche.recipes.Forge.known[recette.etape.cle] = true
        AzerothCommune:Signaler("métiers et compétences")
        assertTrue(compagnon.coche:IsShown(), "Compagnon coché")
        assertTrue(compagnon.nom:GetText():find("Appris : Compagnon (150)", 1, true) ~= nil, compagnon.nom:GetText())
        assertTrue(not expert.coche:IsShown(), "Expert pas encore")
        assertTrue(recette.coche:IsShown(), "la recette vue connue : cochée")
    end)
    fiche.character, fiche.recipes, AzerothCommuneDB.trainers = garde.character, garde.recipes, garde.trainers
    C_Map.SetUserWaypoint, C_Map.CanSetUserWaypointOnMap = waypoint, peut
    if MaitriseFrame then MaitriseFrame:Hide() end
    if not ok then error(err, 0) end
end)

-- Un autre de mes personnages (Maitrise#5) : deux personnages dans les données du socle ; le connecté est choisi par défaut,
-- l'autre se choisit dans le même menu, sa tranche part de sa compétence relevée et son curseur est plafonné par son niveau.
test("Maîtrise : préparer la montée d'un autre de mes personnages", function()
    local guid, AUTRE = UnitGUID("player"), "Player-6942-0000ABCD"
    local fiche = AzerothCommuneDB.chars[guid]
    local garde = fiche.character
    local ok, err = pcall(function()
        fiche.professions = { { name = "Forge", rank = 1, max = 300 } }
        fiche.character = { level = 60 }
        AzerothCommuneDB.chars[AUTRE] = { nom = "Riwanon Kerys", professions = { { name = "Forge", rank = 49, max = 75 },
            { name = "Dépeçage", rank = 100, max = 150 } }, character = { level = 19, faction = AzerothCommune.Faction() } }
        AzerothCommuneMarket[AzerothCommune.MaisonHV()] = { scanned = "22/11 21:00", time = time(), items = {
            [2840] = { tiers = { { price = 40, qty = 2000 } } }, [2835] = { tiers = { { price = 10, qty = 2000 } } },
            [2836] = { tiers = { { price = 20, qty = 2000 } } }, [2841] = { tiers = { { price = 80, qty = 2000 } } } } }
        MaitriseDB = nil
        if MaitriseFrame then MaitriseFrame:Hide() end
        SlashCmdList.MAITRISE("")
        local dd = enfants(MaitriseFrame, function(c) return c.GenerateMenu and c.GetMenuDescription end)[1]
        local function texte() return dd.Text and dd.Text:GetText() or dd:GetText() end
        dd:GenerateMenu()
        -- Le menu : les métiers du connecté, puis ceux de l'autre (sans la récolte).
        local entrees = {}
        for _, e in dd:GetMenuDescription():EnumerateElementDescriptions() do entrees[#entrees + 1] = MenuUtil.GetElementText(e) or "" end
        local tout = table.concat(entrees, " | ")
        assertTrue(tout:find("Forge (1)", 1, true) ~= nil and tout:find("Riwanon · Forge (49)", 1, true) ~= nil, tout)
        assertTrue(tout:find("Dépeçage", 1, true) == nil, "pas de métier de récolte : " .. tout)
        -- Le connecté est choisi par défaut (la fenêtre garde le métier choisi d'un test à l'autre, jamais un autre personnage).
        assertEquals("Forge (1)", texte(), "le personnage connecté par défaut")
        for _, e in dd:GetMenuDescription():EnumerateElementDescriptions() do
            if MenuUtil.GetElementText(e) == "Riwanon · Forge (49)" then dd:Pick(e, MenuInputContext.MouseButton, "LeftButton") end
        end
        assertEquals("Riwanon · Forge (49)", texte())
        local curseur = enfants(MaitriseFrame, function(c) return c:GetObjectType() == "EditBox" end)[1]
        assertEquals("59", curseur:GetText(), "curseur de Riwanon : 49 + 10")
        local regions = {}
        for _, rg in ipairs({ MaitriseFrame:GetRegions() }) do if rg.GetText and rg:GetText() and rg:IsShown() then regions[#regions + 1] = rg:GetText() end end
        assertTrue(table.concat(regions, "\n"):find("150 max : Expert au niveau 20", 1, true) ~= nil, "son plafond, par son niveau")
        curseur:SetText("200")
        bouton("Calculer"):Click()
        assertEquals("150", curseur:GetText(), "plafonné par le niveau de Riwanon")
        local res = assert(Maitrise.Tranche(AUTRE, "Forge", 200))
        assertEquals(49, res.de)
        assertEquals(150, res.a)
        bouton("En faire un projet"):Click()
        if ComposantsFrame then ComposantsFrame:Hide() end
        SlashCmdList.MAITRISE("") -- Maîtrise s'est fermée sur le projet : on la rouvre, toujours sur Riwanon
        assertNotNil(MaitriseDB.tranches[AUTRE] and MaitriseDB.tranches[AUTRE].Forge, "la tranche tenue au nom de Riwanon")
        assertNil(MaitriseDB.tranches[guid] and MaitriseDB.tranches[guid].Forge, "pas celle du connecté")
        local p
        for _, x in ipairs(Composants.Projets()) do if x.tenu == "Maîtrise : Riwanon, Forge de 49 à 150" then p = x end end
        assertNotNil(p, "le projet dit pour qui")
        assertEquals("Maîtrise · tranche Riwanon, Forge 49 / 150", MaitriseFrame.title:GetText())
        -- Revenir au connecté : son métier, sans tranche.
        dd:GenerateMenu()
        for _, e in dd:GetMenuDescription():EnumerateElementDescriptions() do
            if MenuUtil.GetElementText(e) == "Forge (1)" then dd:Pick(e, MenuInputContext.MouseButton, "LeftButton") end
        end
        assertEquals("Forge (1)", texte())
        assertEquals("Maîtrise", MaitriseFrame.title:GetText(), "le connecté n'a pas de tranche")
        Composants.Supprimer(p.id)
    end)
    fiche.character = garde
    AzerothCommuneDB.chars[AUTRE] = nil
    if MaitriseFrame then MaitriseFrame:Hide() end
    if ComposantsFrame then ComposantsFrame:Hide() end
    if not ok then error(err, 0) end
end)

-- Maitrise#32 : la fenêtre du socle, redimensionnable ; la rangée des réglages tient dans les 660 px de départ, les étapes
-- de la frise et la colonne Objet des achats prennent la largeur gagnée. Asynchrone : le changement de taille
-- (OnSizeChanged) arrive à l'image suivante.
local function ensuite(done, fn)
    C_Timer.After(0.05, function()
        local ok, err = pcall(fn)
        if not ok then done(function() error(err, 0) end) end
    end)
end
async_test("Maîtrise : la fenêtre s'agrandit, la frise et les achats suivent", function(done)
    SlashCmdList.MAITRISE("")
    MaitriseFrame:SetSize(660, 520)
    local etat = bouton("En faire un projet") or bouton("Mettre à jour le projet")
    assertNotNil(etat, "bouton du projet")
    assertTrue(etat:GetRight() <= MaitriseFrame:GetRight() - 8, "le bouton du projet ne touche pas le bord droit")
    bouton("Calculer"):Click()
    ensuite(done, function()
        local r = assert(etapes()[1], "une étape")
        local avant = r:GetWidth()
        MaitriseFrame:SetSize(900, 700)
        ensuite(done, function()
            done(function()
                assertEquals(math.floor(avant + 240 + 0.5), math.floor(r:GetWidth() + 0.5), "l'étape s'élargit avec la fenêtre")
                MaitriseFrame:SetSize(660, 520)
                MaitriseFrame:Hide()
            end)
        end)
    end)
end)
