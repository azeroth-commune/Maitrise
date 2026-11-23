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
    assertEquals(#res.fabrications + #res.trous + 1, #vues, "les étapes de la frise")
    local avecIcone = 0
    for _, r in ipairs(vues) do if r.icone:IsShown() and r.icone.tex:GetTexture() then avecIcone = avecIcone + 1 end end
    assertEquals(#res.fabrications, avecIcone, "une icône par fabrication")
    MaitriseFrame:Hide()
end)
