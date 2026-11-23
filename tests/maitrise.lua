-- Tests d'intégration dans wow-ui-sim (tools/sim.sh test Maitrise) : Maîtrise chargé avec le socle et Composants dans
-- l'interface Forever simulée. La réserve des recettes du socle (RecettesClassic.lua, générée) donne les recettes ; le
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
    local vues = etapes()
    assertEquals(#res.fabrications + #res.trous + #res.apprentissages + 1, #vues, "les lignes de la frise (étapes, apprentissages, objectif)")
    local avecIcone = 0
    for _, r in ipairs(vues) do if r.icone:IsShown() and r.icone.tex:GetTexture() then avecIcone = avecIcone + 1 end end
    assertEquals(#res.fabrications + #res.apprentissages, avecIcone, "une icône par fabrication et par apprentissage")
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
    assertEquals(projet, ComposantsDB.projets[ComposantsDB.courant], "sur ce projet")
    ComposantsFrame:Hide()
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
    if ComposantsFrame then ComposantsFrame:Hide() end
    assertEquals("acheter", projet.choix[2840], "choix de case gardé")
    assertEquals("Maîtrise : Forge de 11 à 30", projet.tenu)
    assertEquals("Maîtrise : Forge de 11 à 30", projet.name, "le nom suit les niveaux")
    assertEquals(1, #Composants.Projets(), "le même projet, pas un autre")
    -- Atteindre le curseur : la tranche se termine, le projet est lâché, le bouton redevient « En faire un projet ».
    rang(30)
    MaitriseFrame:Hide()
    SlashCmdList.MAITRISE("")
    assertEquals(nil, projet.tenu, "projet lâché")
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
            assertTrue(r.icone:IsShown() and #r.traits >= 0, "une icône (le livre)")
        elseif e.plages then
            fabs = fabs + 1
            assertTrue(r.detail:GetText():find(" par objet", 1, true) ~= nil, "net par objet : " .. r.detail:GetText())
        end
    end
    assertEquals(#res.fabrications, fabs)
    assertEquals(#res.apprentissages, apprends, "une ligne par apprentissage")
    MaitriseFrame:Hide()
end)
