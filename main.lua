-- main.lua

-- =============================================================================
-- 1. INTEGRATED CARDS MODULE (Inlined from cards.lua)
-- =============================================================================
local Cards = {}

local image
local quads = {}
local FRAME_W, FRAME_H = 32, 48
Cards.FRAME_W = FRAME_W
Cards.FRAME_H = FRAME_H

local FRAMES = {
    cardBaseRed        = { 0,   0 },
    cardBaseBlue       = { 32,  0 },
    cardBaseGreen      = { 64,  0 },
    cardBaseYellow     = { 96,  0 },
    cardBasePurple     = { 128, 0 },

    cardGlyphOne       = { 0,   48 },
    cardGlyphTwo       = { 32,  48 },
    cardGlyphThree     = { 64,  48 },
    cardGlyphFour      = { 96,  48 },
    cardGlyphFive      = { 128, 48 },
    cardGlyphSix       = { 0,   96 },
    cardGlyphSeven     = { 32,  96 },
    cardGlyphEight     = { 64,  96 },
    cardGlyphNine      = { 96,  96 },
    cardGlyphZero      = { 128, 96 },

    cardWildDrawTwo    = { 0,   144 },
    cardWildSkip       = { 32,  144 },
    cardWildSuperSkip  = { 64,  144 },
    cardSymbolSpiral   = { 96,  144 },
}

local COLOR_BASE_FRAME = {
    Red    = "cardBaseRed",
    Blue   = "cardBaseBlue",
    Green  = "cardBaseGreen",
    Yellow = "cardBaseYellow",
    Wild   = "cardBasePurple",
}

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

local TYPE_ICON_FRAME = {
    skip      = "cardWildSkip",
    superskip = "cardWildSuperSkip",
    draw2     = "cardWildDrawTwo",
    wild      = "cardSymbolSpiral",
}

function Cards.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    image = love.graphics.newImage("resources/textures/cardtextures.png")
    local iw, ih = image:getDimensions()

    for name, pos in pairs(FRAMES) do
        quads[name] = love.graphics.newQuad(pos[1], pos[2], FRAME_W, FRAME_H, iw, ih)
    end
end

function Cards.createDeck()
    local deck = {}
    local colors = { "Red", "Blue", "Green", "Yellow" }

    for _, color in ipairs(colors) do
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

function Cards.draw(card, x, y, scale)
    scale = scale or 1
    love.graphics.setColor(1, 1, 1, 1) -- Ensure base colors draw cleanly without tint shifts

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

function Cards.applyEffect(card, ctx)
    local special = nil

    if card.type == "number" then
        ctx.baseChips = ctx.baseChips + card.value * 10
    -- Merged Super Skip alongside traditional mechanics
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
        special = { nextHandSize = 3, skipChainRule = true }
    end

    return special
end

function Cards.isWildCard(card)
    return card.color == "Wild" or card.type == "wild"
end

-- =============================================================================
-- 2. MAIN GAME LOGIC
-- =============================================================================

local states = { MENU = 1, PLAYING = 2, GAME_OVER = 3, WIN = 4, SHOP = 5 }
local gameState = states.MENU

-- =============================================================================
-- BACKGROUND: Balatro-style rotating swirl
-- =============================================================================
local bg = { time = 0 }

local function hsv2rgb(h, s, v)
    h = h % 1
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v
    else return v, p, q end
end

-- Draws an animated rotating stripe swirl across the whole screen, similar
-- in spirit to Balatro's spinning card-table backdrop.
local function drawSwirlBackground(t, intensity)
    intensity = intensity or 1
    local w, h = love.graphics.getDimensions()
    local cx, cy = w / 2, h / 2
    local diag = math.sqrt(w * w + h * h) * 1.6

    -- Deep base color so the stripes read as accents, not the whole show
    love.graphics.setColor(0.06, 0.07, 0.12, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)

    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate(t * 0.06)

    local stripeCount = 16
    for i = 1, stripeCount do
        local hue = (t * 0.03 + i / stripeCount) % 1
        local r, g, b = hsv2rgb(hue, 0.55, 0.30 * intensity)
        love.graphics.setColor(r, g, b, 0.9)
        love.graphics.push()
        love.graphics.rotate(i * (math.pi * 2 / stripeCount))
        love.graphics.rectangle("fill", -diag / 2, -34, diag, 68)
        love.graphics.pop()
    end
    love.graphics.pop()

    -- soft pulsing glow near the center
    local pulse = 0.5 + 0.5 * math.sin(t * 1.3)
    love.graphics.setColor(1, 1, 1, 0.04 * intensity * pulse)
    love.graphics.circle("fill", cx, cy, math.min(w, h) * 0.42)

    love.graphics.setColor(1, 1, 1, 1)
end

-- Darkening overlay so HUD text stays readable on top of the swirl
local function drawOverlay(alpha)
    local w, h = love.graphics.getDimensions()
    love.graphics.setColor(0, 0, 0, alpha)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Rounded panel helper used throughout the HUD for a cleaner look
local function drawPanel(x, y, w, h, fillColor, lineColor)
    love.graphics.setColor(fillColor[1], fillColor[2], fillColor[3], fillColor[4] or 0.55)
    love.graphics.rectangle("fill", x, y, w, h, 10, 10)
    if lineColor then
        love.graphics.setColor(lineColor[1], lineColor[2], lineColor[3], lineColor[4] or 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", x, y, w, h, 10, 10)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

local deck = {}
local hand = {}
local selectedCards = {}
local score = 0
local ante = 1
local baseTargetScore = 500
local targetScore = baseTargetScore
local playsLeft = 4
local basePlaysLeft = 4
local baseDiscards = 3
local discardsLeft = 3
local coins = 0

-- Hand configuration variables for Wild Card status rules
local currentHandTargetSize = 7
local skipChainRuleActive = false

local sfx = {}
local fonts = {}
local floatingTexts = {} 
local shakeTimer = 0
local shakeMag = 0
local cardAnim = {} 

local ALL_RELICS = {
    {
        id = "mult_booster", name = "Multiplier Booster", cost = 8,
        desc = "+0.5 Mult on every scoring chain",
        onScore = function(ctx) ctx.multiplier = ctx.multiplier + 0.5 end
    },
    {
        id = "chip_stacker", name = "Chip Stacker", cost = 8,
        desc = "+5 Chips per card played",
        onScore = function(ctx) ctx.baseChips = ctx.baseChips + (5 * ctx.numCards) end
    },
    {
        id = "wild_synergy", name = "Wild Synergy", cost = 10,
        desc = "+1 Mult for each Wild card in the chain",
        onScore = function(ctx) ctx.multiplier = ctx.multiplier + (1 * ctx.wildCount) end
    },
    {
        id = "extra_plays", name = "Extra Plays", cost = 12,
        desc = "+1 play per round (passive)",
        onAnteStart = function() basePlaysLeft = basePlaysLeft + 1 end
    },
    {
        id = "lucky_draw", name = "Lucky Draw", cost = 10,
        desc = "+1 extra card drawn on Draw+2 cards",
        onScore = function(ctx) ctx.extraDraw = ctx.extraDraw + 1 end
    },
    {
        id = "long_chain", name = "Chain Master", cost = 14,
        desc = "+0.2 Mult per card in the chain (beyond the first)",
        onScore = function(ctx) ctx.multiplier = ctx.multiplier + (0.2 * math.max(0, ctx.numCards - 1)) end
    },
    {
        id = "rainbow_chain", name = "Rainbow Chain", cost = 12,
        desc = "+0.75 Mult per unique color in the chain",
        onScore = function(ctx) ctx.multiplier = ctx.multiplier + (0.75 * (ctx.uniqueColors or 0)) end
    },
}
local ownedRelics = {}
local shopOffers = {}

function drawHand()
    while #hand < currentHandTargetSize and #deck > 0 do
        table.insert(hand, table.remove(deck, 1))
    end
end

function spawnFloatingText(x, y, text, color)
    table.insert(floatingTexts, {
        x = x, y = y, text = text,
        life = 1.2, maxLife = 1.2,
        vy = -60,
        color = color or {1, 1, 1}
    })
end

-- Screen setup helpers
function triggerShake(magnitude, duration)
    shakeMag = math.max(shakeMag, magnitude)
    shakeTimer = math.max(shakeTimer, duration)
end

function startNewAnte(resetRun)
    currentHandTargetSize = 7
    skipChainRuleActive = false

    if resetRun then
        ante = 1
        coins = 0
        score = 0
        ownedRelics = {}
        basePlaysLeft = 4
    else
        score = 0
    end

    deck = Cards.createDeck()
    Cards.shuffle(deck)
    hand = {}
    selectedCards = {}
    drawHand()

    targetScore = math.floor(baseTargetScore * (1.35 ^ (ante - 1)))
    playsLeft = basePlaysLeft
    discardsLeft = baseDiscards

    for _, relic in ipairs(ownedRelics) do
        if relic.onAnteStart then relic.onAnteStart() end
    end
    playsLeft = basePlaysLeft

    cardAnim = {}
    gameState = states.PLAYING
end

function rollShopOffers()
    shopOffers = {}
    local pool = {}
    for _, r in ipairs(ALL_RELICS) do
        local owned = false
        for _, o in ipairs(ownedRelics) do
            if o.id == r.id then owned = true break end
        end
        if not owned then table.insert(pool, r) end
    end
    Cards.shuffle(pool)
    for i = 1, math.min(3, #pool) do
        table.insert(shopOffers, pool[i])
    end
end

function buyRelic(index)
    local relic = shopOffers[index]
    if not relic then return end
    if coins < relic.cost then
        love.audio.play(sfx.click)
        return
    end
    coins = coins - relic.cost
    table.insert(ownedRelics, relic)
    if relic.onAnteStart then relic.onAnteStart() end
    table.remove(shopOffers, index)
    love.audio.play(sfx.coin)
end

function love.load()
    love.math.setRandomSeed(os.time())
    Cards.load()

    fonts.small  = love.graphics.newFont("resources/fonts/gamefont.ttf", 15)
    fonts.medium = love.graphics.newFont("resources/fonts/gamefont.ttf", 20)
    fonts.large  = love.graphics.newFont("resources/fonts/gamefont.ttf", 28)
    fonts.title  = love.graphics.newFont("resources/fonts/gamefont-big.ttf", 88)
    fonts.subtitle = love.graphics.newFont("resources/fonts/gamefont-big.ttf", 30)
    love.graphics.setFont(fonts.medium)

    sfx.coin         = love.audio.newSource("resources/sounds/coin.wav", "static")
    sfx.hurt         = love.audio.newSource("resources/sounds/hurt.wav", "static")
    sfx.boom         = love.audio.newSource("resources/sounds/boom.wav", "static")
    sfx.click        = love.audio.newSource("resources/sounds/click.wav", "static")
    sfx.pop          = love.audio.newSource("resources/sounds/pop.wav", "static")
    sfx.cardunselect = love.audio.newSource("resources/sounds/cardunselect.ogg", "static")
    sfx.cardselect   = love.audio.newSource("resources/sounds/cardselect.ogg", "static")

    deck = Cards.createDeck()
    Cards.shuffle(deck)
    drawHand()
    targetScore = baseTargetScore
    discardsLeft = baseDiscards
end

-- Builds the chips/multiplier context for a given set of hand indices without
-- mutating any global state, so it can be reused for both the live preview
-- and the real scoring pass.
function buildScoreContext(indices)
    local ctx = {
        baseChips = 0,
        multiplier = 1,
        extraDraw = 0,
        numCards = #indices,
        wildCount = 0,
    }

    local triggerSpecialHand = false
    local sameColor = true
    local firstColor = nil
    local colorSet = {}

    for _, index in ipairs(indices) do
        local card = hand[index]
        if card then
            if not Cards.isWildCard(card) then
                if firstColor == nil then
                    firstColor = card.color
                elseif firstColor ~= card.color then
                    sameColor = false
                end
            end
            colorSet[card.color] = true

            local special = Cards.applyEffect(card, ctx)
            if special and special.nextHandSize then
                triggerSpecialHand = true
            end
        end
    end

    local uniqueColors = 0
    for _ in pairs(colorSet) do uniqueColors = uniqueColors + 1 end
    ctx.uniqueColors = uniqueColors

    ctx.multiplier = ctx.multiplier + (ctx.numCards * 0.5)

    -- Flush bonus: every selected card (besides wilds) shares the same color
    ctx.flush = sameColor and firstColor ~= nil and ctx.numCards >= 2
    if ctx.flush then
        ctx.multiplier = ctx.multiplier + 2
    end

    -- Apply relic effects
    for _, relic in ipairs(ownedRelics) do
        if relic.onScore then relic.onScore(ctx) end
    end

    ctx.finalScore = math.floor(ctx.baseChips * ctx.multiplier)
    return ctx, triggerSpecialHand
end

function toggleCardSelection(num)
    if not hand[num] then return end
    local foundIndex = nil
    for i, val in ipairs(selectedCards) do
        if val == num then foundIndex = i break end
    end

    if foundIndex then
        table.remove(selectedCards, foundIndex)
        love.audio.stop(sfx.cardunselect)
        love.audio.play(sfx.cardunselect)
    else
        table.insert(selectedCards, num)
        love.audio.stop(sfx.cardselect)
        love.audio.play(sfx.cardselect)
    end
end

function discardSelected()
    if discardsLeft <= 0 or #selectedCards == 0 then
        love.audio.play(sfx.click)
        return
    end

    discardsLeft = discardsLeft - 1

    table.sort(selectedCards, function(a, b) return a > b end)
    for _, index in ipairs(selectedCards) do
        table.remove(hand, index)
    end

    selectedCards = {}
    cardAnim = {}
    drawHand()
    love.audio.play(sfx.pop)
end

function pointInRect(px, py, r)
    return px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h
end

-- Shared layout so the draw call and mouse hit-testing always agree on
-- where each card in hand actually is.
function getHandLayout()
    local cardWidth = 32 * 3.5
    local cardHeight = 48 * 3.5
    local panelW = 280
    local areaX = panelW + 40
    local areaW = math.max(200, love.graphics.getWidth() - areaX - 40)
    local startX = areaX + math.max(0, (areaW - (#hand * (cardWidth + 15))) / 2)
    local startY = 380

    local layout = {}
    for i = 1, #hand do
        local x = startX + (i - 1) * (cardWidth + 15)
        local liftY = cardAnim[i] and cardAnim[i].y or 0
        layout[i] = { x = x, y = startY + liftY, w = cardWidth, h = cardHeight }
    end
    return layout, cardWidth, cardHeight
end

-- Mouse-clickable PLAY HAND / DISCARD buttons, anchored to the side panel.
function getActionButtons()
    local panelX = 20
    local btnW, btnH = 240, 50
    local playBtn = { x = panelX + 20, y = 420, w = btnW, h = btnH }
    local discardBtn = { x = panelX + 20, y = 420 + btnH + 14, w = btnW, h = btnH }
    return playBtn, discardBtn
end

function isValidChain()
    if skipChainRuleActive then return true end
    if #selectedCards <= 1 then return true end
    for i = 2, #selectedCards do
        local prev = hand[selectedCards[i-1]]
        local curr = hand[selectedCards[i]]
        if Cards.isWildCard(prev) or Cards.isWildCard(curr) then
            -- Valid
        elseif prev.color ~= curr.color and prev.value ~= curr.value then
            return false
        end
    end
    return true
end

function scoreCombo()
    if #selectedCards == 0 or not isValidChain() then
        love.audio.play(sfx.click)
        return
    end

    local ctx, triggerSpecialHand = buildScoreContext(selectedCards)

    score = score + ctx.finalScore
    playsLeft = playsLeft - 1

    love.audio.play(sfx.boom)

    local cw, ch = love.graphics.getWidth(), love.graphics.getHeight()
    spawnFloatingText(cw / 2, ch / 2 + 20, "+" .. ctx.finalScore, {1, 0.9, 0.3})
    spawnFloatingText(cw / 2, ch / 2 + 50, string.format("x%.1f", ctx.multiplier), {0.6, 0.9, 1})
    if ctx.flush then
        spawnFloatingText(cw / 2, ch / 2 - 10, "FLUSH! +2 Mult", {0.9, 0.5, 1})
    end
    triggerShake(math.min(10, 2 + ctx.numCards), 0.18 + math.min(0.25, ctx.numCards * 0.04))

    table.sort(selectedCards, function(a,b) return a > b end)
    for _, index in ipairs(selectedCards) do
        table.remove(hand, index)
    end

    selectedCards = {}
    cardAnim = {}

    -- Process hand sizes rule modifications if Wild trigger conditions are met
    if triggerSpecialHand then
        currentHandTargetSize = 3
        skipChainRuleActive = true
    else
        currentHandTargetSize = 7
        skipChainRuleActive = false
    end

    drawHand()

    for i = 1, ctx.extraDraw do
        if #deck > 0 and #hand < 10 then table.insert(hand, table.remove(deck, 1)) end
    end

    if score >= targetScore then
        coins = coins + 10 + ante * 2
        rollShopOffers()
        gameState = states.SHOP
        love.audio.play(sfx.coin)
    elseif playsLeft <= 0 then
        gameState = states.GAME_OVER
        love.audio.play(sfx.hurt)
    end
end

function love.keypressed(key)
    if gameState == states.MENU then
        if key == "return" or key == "space" then
            startNewAnte(true)
            love.audio.play(sfx.pop)
        end
        return
    end

    if gameState == states.PLAYING then
        local num = tonumber(key)
        if num and num >= 1 and num <= #hand then
            toggleCardSelection(num)
        end

        if key == "d" then
            discardSelected()
        end

        if key == "return" then
            scoreCombo()
        end

        if key == "escape" then
            selectedCards = {}
            love.audio.play(sfx.pop)
        end

    elseif gameState == states.SHOP then
        local num = tonumber(key)
        if num and num >= 1 and num <= #shopOffers then
            buyRelic(num)
        end
        if key == "space" then
            ante = ante + 1
            startNewAnte(false)
            love.audio.play(sfx.pop)
        end

    elseif gameState == states.GAME_OVER or gameState == states.WIN then
        if key == "space" then
            startNewAnte(true)
            love.audio.play(sfx.pop)
        end
    end
end

function love.mousepressed(x, y, button)
    if button ~= 1 then return end

    if gameState == states.MENU then
        startNewAnte(true)
        love.audio.play(sfx.pop)
        return
    end

    if gameState == states.PLAYING then
        local layout = getHandLayout()
        for i, rect in ipairs(layout) do
            if pointInRect(x, y, rect) then
                toggleCardSelection(i)
                return
            end
        end

        local playBtn, discardBtn = getActionButtons()
        if pointInRect(x, y, playBtn) then
            scoreCombo()
            return
        end
        if pointInRect(x, y, discardBtn) then
            discardSelected()
            return
        end

    elseif gameState == states.SHOP then
        local cardWidth, cardHeight = 260, 220
        local startX = (love.graphics.getWidth() - (#shopOffers * (cardWidth + 30))) / 2
        local shopY = 230

        for i, relic in ipairs(shopOffers) do
            local rx = startX + (i - 1) * (cardWidth + 30)
            if pointInRect(x, y, { x = rx, y = shopY, w = cardWidth, h = cardHeight }) then
                buyRelic(i)
                return
            end
        end

    elseif gameState == states.GAME_OVER or gameState == states.WIN then
        startNewAnte(true)
        love.audio.play(sfx.pop)
    end
end

function love.update(dt)
    bg.time = bg.time + dt

    for i = #floatingTexts, 1, -1 do
        local t = floatingTexts[i]
        t.life = t.life - dt
        t.y = t.y + t.vy * dt
        t.vy = t.vy * 0.96
        if t.life <= 0 then table.remove(floatingTexts, i) end
    end

    if shakeTimer > 0 then
        shakeTimer = shakeTimer - dt
        if shakeTimer <= 0 then
            shakeTimer = 0
            shakeMag = 0
        end
    end

    for i, card in ipairs(hand) do
        if not cardAnim[i] then cardAnim[i] = { y = 0, targetY = 0 } end
        local isSelected = false
        for _, selIdx in ipairs(selectedCards) do
            if selIdx == i then isSelected = true break end
        end
        cardAnim[i].targetY = isSelected and -30 or 0
        local diff = cardAnim[i].targetY - cardAnim[i].y
        cardAnim[i].y = cardAnim[i].y + diff * math.min(1, dt * 12)
    end
end

function love.draw()
    -- Push for screen shake
    local shakeX, shakeY = 0, 0
    if shakeTimer > 0 then
        shakeX = (love.math.random() * 2 - 1) * shakeMag
        shakeY = (love.math.random() * 2 - 1) * shakeMag
    end

    love.graphics.push()
    love.graphics.translate(shakeX, shakeY)

    -- Apply CRT shader during gameplay (not in menu)
    if gameState ~= states.MENU then
        love.graphics.setShader(crtShader)
    end

    -- Clear background
    love.graphics.clear(0.05, 0.05, 0.08)

    -- Draw animated swirl background
    drawSwirlBackground(bg.time, (gameState == states.MENU) and 1.0 or 0.55)

    -- Draw overlay for HUD readability
    drawOverlay((gameState == states.MENU) and 0.18 or 0.45)

    -- Define scale factor for side menu
    local menuScale = 2
    local sidePanelWidth = 500
    local panelX = 20
    local panelY = 20
    local panelH = 600

    -- Draw side panel with scaling
    love.graphics.push()
    love.graphics.scale(menuScale)
    drawPanel(panelX / menuScale, panelY / menuScale, sidePanelWidth / menuScale, panelH / menuScale,
        {0.07, 0.08, 0.13, 0.7}, {1, 1, 1, 0.15})
    love.graphics.pop()

    -- Now draw all UI elements relative to scaled panel
    if gameState == states.MENU then
        local w, h = love.graphics.getDimensions()

        local pulse = 1 + 0.04 * math.sin(bg.time * 2)

        -- Title shadow + title, "MultiDecks"
        love.graphics.setFont(fonts.title)
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.printf("MultiDecks", 4, h * 0.28 + 6, w, "center", 0, pulse, pulse)
        local titleHue = (bg.time * 0.05) % 1
        local tr, tg, tb = hsv2rgb(titleHue, 0.45, 1)
        love.graphics.setColor(tr, tg, tb, 1)
        love.graphics.printf("MultiDecks", 0, h * 0.28, w, "center", 0, pulse, pulse)

        love.graphics.setFont(fonts.subtitle)
        love.graphics.setColor(0.85, 0.85, 0.95, 1)
        love.graphics.printf("A color-chaining, chip & multiplier card roguelite", 0, h * 0.46, w, "center")

        love.graphics.setFont(fonts.large)
        local promptAlpha = 0.6 + 0.4 * math.sin(bg.time * 3)
        love.graphics.setColor(1, 0.9, 0.4, promptAlpha)
        love.graphics.printf("Click anywhere, or press ENTER / SPACE, to start a run", 0, h * 0.60, w, "center")

        love.graphics.setFont(fonts.medium)
        love.graphics.setColor(0.7, 0.7, 0.75, 1)
        love.graphics.printf("Chain matching colors or numbers - rack up chips x multiplier each play", 0, h * 0.67, w, "center")

    elseif gameState == states.PLAYING then
        local w = love.graphics.getWidth()
        local panelX, panelW = 20, sidePanelWidth

        -- Side panel background (already drawn scaled)
        -- (Already done above with scaled drawPanel)

        -- Draw game HUD inside side panel
        love.graphics.setFont(fonts.large)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("ANTE " .. ante, panelX + 20, 40)

        love.graphics.setFont(fonts.medium)
        love.graphics.setColor(0.75, 0.85, 1)
        love.graphics.print("Target: " .. targetScore, panelX + 20, 76)

        love.graphics.setFont(fonts.large)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("Score: " .. score, panelX + 20, 102)

        -- Score progress bar toward target
        local barX, barY, barW, barH = panelX + 20, 138, panelW - 40, 12
        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.rectangle("fill", barX, barY, barW, barH, 4, 4)
        local pct = math.min(1, score / targetScore)
        love.graphics.setColor(0.3, 0.85, 0.5)
        love.graphics.rectangle("fill", barX, barY, barW * pct, barH, 4, 4)

        -- Live hand preview
        love.graphics.setFont(fonts.medium)
        local valid = isValidChain()
        if #selectedCards > 0 and valid then
            local previewCtx = buildScoreContext(selectedCards)
            love.graphics.setColor(0.6, 0.95, 0.8)
            love.graphics.print(string.format("%d chips x %.1f mult", previewCtx.baseChips, previewCtx.multiplier), panelX + 20, 172)
            love.graphics.setColor(1, 0.9, 0.4)
            love.graphics.print("= " .. previewCtx.finalScore, panelX + 20, 198)
            if previewCtx.flush then
                love.graphics.setColor(0.85, 0.5, 1)
                love.graphics.print("FLUSH! +2 Mult", panelX + 20, 224)
            end
        elseif #selectedCards > 0 and not valid then
            love.graphics.setColor(0.85, 0.3, 0.3)
            love.graphics.printf("Invalid chain - must match color or number", panelX + 20, 172, panelW - 40, "left")
        else
            love.graphics.setColor(0.55, 0.55, 0.6)
            love.graphics.printf("Click cards to build a chain", panelX + 20, 172, panelW - 40, "left")
        end

        love.graphics.setFont(fonts.medium)
        love.graphics.setColor(1, 0.8, 0.5)
        love.graphics.print("Plays left: " .. playsLeft, panelX + 20, 270)
        love.graphics.setColor(0.7, 0.85, 1)
        love.graphics.print("Discards left: " .. discardsLeft, panelX + 20, 296)
        love.graphics.setColor(1, 0.85, 0.3)
        love.graphics.print("Coins: " .. coins, panelX + 20, 322)

        -- Play / Discard buttons
        local playBtn, discardBtn = getActionButtons()
        local canPlay = #selectedCards > 0 and valid
        local canDiscard = #selectedCards > 0 and discardsLeft > 0

        drawPanel(playBtn.x, playBtn.y, playBtn.w, playBtn.h,
            canPlay and {0.25, 0.6, 0.35, 0.85} or {0.2, 0.22, 0.26, 0.6},
            {1, 1, 1, 0.25})
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("PLAY HAND", playBtn.x, playBtn.y + 14, playBtn.w, "center")

        drawPanel(discardBtn.x, discardBtn.y, discardBtn.w, discardBtn.h,
            canDiscard and {0.55, 0.3, 0.3, 0.85} or {0.2, 0.22, 0.26, 0.6},
            {1, 1, 1, 0.25})
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("DISCARD (D)", discardBtn.x, discardBtn.y + 14, discardBtn.w, "center")

        love.graphics.setColor(0.85, 0.85, 0.9)
        love.graphics.printf("Click cards to select. ENTER / Play Hand to score. ESC to clear.", panelX + panelW + 40, 30, w - panelW - 80, "left")

        -- Draw hand cards
        local layout, cardWidth, cardHeight = getHandLayout()
        for i, card in ipairs(hand) do
            local rect = layout[i]
            local x, y = rect.x, rect.y
            
            local isSelected = false
            for _, selIdx in ipairs(selectedCards) do
                if selIdx == i then isSelected = true break end
            end

            -- Draw card shadow
            love.graphics.setColor(0, 0, 0, 0.35)
            love.graphics.rectangle("fill", x + 6, y + 8, cardWidth, cardHeight, 6, 6)
            love.graphics.setColor(1, 1, 1, 1)

            -- Draw the card sprite
            Cards.draw(card, x, y, 3.5)

            -- Draw selection border
            if isSelected then
                love.graphics.setColor(1, 0.9, 0.4, 1)
                love.graphics.setLineWidth(4)
                love.graphics.rectangle("line", x, y, cardWidth, cardHeight, 4, 4)
            end
        end

    elseif gameState == states.SHOP then
        local w = love.graphics.getWidth()
        local shopPanelX = w/2 - 260
        local shopPanelY = 40
        local shopPanelW = 520
        local shopPanelH = 140
        love.graphics.setFont(fonts.medium)
        drawPanel(shopPanelX, shopPanelY, shopPanelW, shopPanelH, {0.08, 0.09, 0.14, 0.55}, {1, 0.85, 0.3, 0.3})

        love.graphics.setColor(1, 0.9, 0.3)
        love.graphics.printf("ANTE " .. ante .. " CLEARED! SHOP", 0, 60, w, "center", 0, 2, 2)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("Coins: " .. coins, 0, 120, w, "center", 0, 1.4, 1.4)
        love.graphics.printf("Press [1-3] to buy a relic. Press [SPACE] to continue to Ante " .. (ante + 1), 0, 160, w, "center")

        local cardWidth = 260
        local cardHeight = 220
        local startX = (w - (#shopOffers * (cardWidth + 30))) / 2
        local y = 230

        for i, relic in ipairs(shopOffers) do
            local x = startX + (i - 1) * (cardWidth + 30)
            local affordable = coins >= relic.cost

            love.graphics.setColor(0.15, 0.2, 0.25)
            love.graphics.rectangle("fill", x, y, cardWidth, cardHeight, 10, 10)

            love.graphics.setColor(affordable and 0.5 or 0.3, affordable and 0.8 or 0.3, affordable and 0.5 or 0.3)
            love.graphics.setLineWidth(3)
            love.graphics.rectangle("line", x, y, cardWidth, cardHeight, 10, 10)

            love.graphics.setColor(1, 1, 1)
            love.graphics.printf("[" .. i .. "] " .. relic.name, x + 10, y + 15, cardWidth - 20, "center")
            love.graphics.printf(relic.desc, x + 15, y + 70, cardWidth - 30, "left")
            love.graphics.setColor(1, 0.85, 0.3)
            love.graphics.printf("Cost: " .. relic.cost .. " coins", x + 10, y + cardHeight - 35, cardWidth - 20, "center")
        end

        if #ownedRelics > 0 then
            love.graphics.setColor(0.7, 0.7, 0.7)
            local names = {}
            for _, r in ipairs(ownedRelics) do table.insert(names, r.name) end
            love.graphics.printf("Owned: " .. table.concat(names, ", "), 0, 480, w, "center")
        end

    elseif gameState == states.GAME_OVER then
        love.graphics.setColor(0.9, 0.2, 0.2)
        love.graphics.printf("GAME OVER", 0, 180, love.graphics.getWidth(), "center", 0, 3, 3, 100)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("You ran out of plays on Ante " .. ante .. " before reaching " .. targetScore, 0, 280, love.graphics.getWidth(), "center", 0, 1.2, 1.2)
        love.graphics.printf("Final Score: " .. score .. "   Coins Earned This Run: " .. coins, 0, 330, love.graphics.getWidth(), "center")
        love.graphics.printf("Press SPACE to restart.", 0, 400, love.graphics.getWidth(), "center")

    elseif gameState == states.WIN then
        love.graphics.setColor(0.2, 0.9, 0.4)
        love.graphics.printf("RUN COMPLETE!", 0, 200, love.graphics.getWidth(), "center", 0, 3, 3, 100)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("Final Score: " .. score, 0, 300, love.graphics.getWidth(), "center", 0, 1.5, 1.5)
        love.graphics.printf("Press SPACE to play again.", 0, 400, love.graphics.getWidth(), "center")
    end

    -- Draw floating texts
    for _, t in ipairs(floatingTexts) do
        local alpha = math.max(0, t.life / t.maxLife)
        love.graphics.setColor(t.color[1], t.color[2], t.color[3], alpha)
        love.graphics.printf(t.text, t.x - 150, t.y, 300, "center", 0, 2, 2)
    end

    -- Pop the main push
    love.graphics.pop()

    -- Reset shader after drawing
    if gameState ~= states.MENU then
        love.graphics.setShader()
    end
end