--src/cards.lua
--handles everything about cards: the sprite sheet, deck creation, drawing,
--and what each card type does when scored.

local Cards = {}

-- ===== SPRITE SHEET SETUP =====
local image
local quads = {}

local FRAME_W, FRAME_H = 32, 48
Cards.FRAME_W = FRAME_W
Cards.FRAME_H = FRAME_H

-- Frame coordinates copied directly from cardtextures.json.
-- If you ever re-export the sheet and the layout changes, only this table needs updating.
local FRAMES = {
    cardBaseRed       = { 0,   0 },
    cardBaseBlue       = { 32,  0 },
    cardBaseGreen       = { 64,  0 },
    cardBaseYellow       = { 96,  0 },
    cardBasePurple       = { 128, 0 },

    cardGlyphOne       = { 0,   48 },
    cardGlyphTwo       = { 32,  48 },
    cardGlyphThree       = { 64,  48 },
    cardGlyphFour       = { 96,  48 },
    cardGlyphFive       = { 128, 48 },
    cardGlyphSix       = { 0,   96 },
    cardGlyphSeven       = { 32,  96 },
    cardGlyphEight       = { 64,  96 },
    cardGlyphNine       = { 96,  96 },
    cardGlyphZero       = { 128, 96 },

    cardWildDrawTwo       = { 0,   144 },
    cardWildSkip       = { 32,  144 },
    cardWildSuperSkip       = { 64,  144 },
    cardSymbolSpiral       = { 96,  144 },
}

-- Maps a card's `color` field to the base-card frame to draw underneath everything.
local COLOR_BASE_FRAME = {
    Red    = "cardBaseRed",
    Blue   = "cardBaseBlue",
    Green  = "cardBaseGreen",
    Yellow = "cardBaseYellow",
    Wild   = "cardBasePurple",
}

-- Maps a number value (0-9) to its glyph overlay frame.
local NUMBER_GLYPH_FRAME = {
    [0] = "cardGlyphZero",
    [1] = "cardGlyphOne",
    [2] = "cardGlyphTwo",
    [3] = "cardGlyphThree",
    [4] = "cardGlyphFour",
    [5] = "cardGlyphFive",
    [6] = "cardGlyphSix",
    [7] = "cardGlyphSeven",
    [8] = "cardGlyphEight",
    [9] = "cardGlyphNine",
}

-- Maps a special card `type` to its overlay icon frame.
-- (numbers are handled separately via NUMBER_GLYPH_FRAME)
local TYPE_ICON_FRAME = {
    skip      = "cardWildSkip",
    superskip = "cardWildSuperSkip",
    draw2     = "cardWildDrawTwo",
    wild      = "cardSymbolSpiral",
}

-- Call once in love.load(). Loads the sheet and slices it into quads.
function Cards.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    image = love.graphics.newImage("resources/textures/cardtextures.png")
    local iw, ih = image:getDimensions()

    for name, pos in pairs(FRAMES) do
        quads[name] = love.graphics.newQuad(pos[1], pos[2], FRAME_W, FRAME_H, iw, ih)
    end
end

-- ===== DECK CREATION =====
-- Card shape: { color, value, type, display }
-- type is one of: "number", "skip", "superskip", "draw2", "wild"
local COLORS = { "Red", "Blue", "Green", "Yellow" }
Cards.COLORS = COLORS

function Cards.createDeck()
    local deck = {}

    for _, color in ipairs(COLORS) do
        -- Numbers: one 0, two each of 1-9 (matches your original distribution)
        for num = 0, 9 do
            table.insert(deck, { color = color, value = num, type = "number", display = tostring(num) })
            if num > 0 then
                table.insert(deck, { color = color, value = num, type = "number", display = tostring(num) })
            end
        end

        table.insert(deck, { color = color, value = 10, type = "skip",      display = "Skip (x2 Mult)" })
        table.insert(deck, { color = color, value = 11, type = "superskip", display = "Super Skip (x3 Mult)" })
        table.insert(deck, { color = color, value = 10, type = "draw2",     display = "Draw+2" })
    end

    -- Wild cards: purple base, always usable, only 4 in the deck
    for i = 1, 4 do
        table.insert(deck, { color = "Wild", value = 15, type = "wild", display = "WILD" })
    end

    return deck
end

function Cards.shuffle(deck)
    for i = #deck, 2, -1 do
        local j = love.math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
end

-- ===== DRAWING =====
-- Draws one card (base + overlay) at x, y. scale defaults to 1 (native 32x48).
function Cards.draw(card, x, y, scale)
    scale = scale or 1

    local baseFrame = COLOR_BASE_FRAME[card.color] or "cardBasePurple"
    local baseQuad = quads[baseFrame]
    if baseQuad then
        love.graphics.draw(image, baseQuad, x, y, 0, scale, scale)
    end

    local overlayFrame
    if card.type == "number" then
        overlayFrame = NUMBER_GLYPH_FRAME[card.value]
    else
        overlayFrame = TYPE_ICON_FRAME[card.type]
    end

    if overlayFrame and quads[overlayFrame] then
        love.graphics.draw(image, quads[overlayFrame], x, y, 0, scale, scale)
    end
end

-- ===== SCORING EFFECTS =====
-- Called once per selected card inside your scoreCombo loop.
-- `ctx` is the same running-totals table you already build in main.lua:
--   { baseChips, multiplier, extraDraw, numCards, wildCount }
-- This function mutates ctx directly and also returns a `special` table
-- for effects that aren't simple chip/mult math (currently just Wild's
-- "next hand size" rule), since that needs to be handled by main.lua's
-- hand-drawing logic, not the scoring math.
--
-- Returns: special (table or nil), e.g. { nextHandSize = 3, skipChainRule = true }
function Cards.applyEffect(card, ctx)
    local special = nil

    if card.type == "number" then
        ctx.baseChips = ctx.baseChips + card.value * 10

    elseif card.type == "skip" then
        ctx.multiplier = ctx.multiplier * 2
        ctx.baseChips = ctx.baseChips + 20

    elseif card.type == "superskip" then
        ctx.multiplier = ctx.multiplier * 3
        ctx.baseChips = ctx.baseChips + 30

    elseif card.type == "draw2" then
        ctx.extraDraw = ctx.extraDraw + 2
        ctx.baseChips = ctx.baseChips + 20

    elseif card.type == "wild" then
        ctx.baseChips = ctx.baseChips + 50
        ctx.multiplier = ctx.multiplier + 1
        ctx.wildCount = ctx.wildCount + 1

        -- Wild's special rule: your NEXT hand only has 3 cards, and those 3
        -- don't need to match colors/numbers at all. main.lua should check
        -- for this in scoreCombo and apply it when drawing the next hand.
        special = { nextHandSize = 3, skipChainRule = true }
    end

    return special
end

-- Convenience: true if a card type matches the "Wild" no-chain-rule exemption
-- (kept separate from applyEffect so isValidChain() in main.lua can use it
-- without running scoring math).
function Cards.isWildCard(card)
    return card.color == "Wild" or card.type == "wild"
end

return Cards