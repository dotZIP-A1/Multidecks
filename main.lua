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
local gameState = states.PLAYING

local deck = {}
local hand = {}
local selectedCards = {}
local score = 0
local ante = 1
local baseTargetScore = 500
local targetScore = baseTargetScore
local playsLeft = 4
local basePlaysLeft = 4
local coins = 0

-- Hand configuration variables for Wild Card status rules
local currentHandTargetSize = 7
local skipChainRuleActive = false

local sfx = {}
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

    local ctx = {
        baseChips = 0,
        multiplier = 1,
        extraDraw = 0,
        numCards = #selectedCards,
        wildCount = 0,
    }

    local triggerSpecialHand = false

    -- Use Cards.applyEffect to balance point distributions
    for _, index in ipairs(selectedCards) do
        local card = hand[index]
        local special = Cards.applyEffect(card, ctx)
        if special and special.nextHandSize then
            triggerSpecialHand = true
        end
    end

    ctx.multiplier = ctx.multiplier + (ctx.numCards * 0.5)

    -- Apply relic effects
    for _, relic in ipairs(ownedRelics) do
        if relic.onScore then relic.onScore(ctx) end
    end

    local finalScore = math.floor(ctx.baseChips * ctx.multiplier)
    score = score + finalScore
    playsLeft = playsLeft - 1

    love.audio.play(sfx.boom)

    local cw, ch = love.graphics.getWidth(), love.graphics.getHeight()
    spawnFloatingText(cw / 2, ch / 2 + 20, "+" .. finalScore, {1, 0.9, 0.3})
    spawnFloatingText(cw / 2, ch / 2 + 50, string.format("x%.1f", ctx.multiplier), {0.6, 0.9, 1})
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
    if gameState == states.PLAYING then
        local num = tonumber(key)
        if num and num >= 1 and num <= #hand then
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

function love.update(dt)
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
    local shakeX, shakeY = 0, 0
    if shakeTimer > 0 then
        shakeX = (love.math.random() * 2 - 1) * shakeMag
        shakeY = (love.math.random() * 2 - 1) * shakeMag
    end
    love.graphics.push()
    love.graphics.translate(shakeX, shakeY)

    love.graphics.clear(0.08, 0.15, 0.15)

    if gameState == states.PLAYING then
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("ANTE " .. ante .. "   TARGET SCORE: " .. targetScore, 50, 40, 0, 1.5, 1.5)
        love.graphics.print("YOUR SCORE: " .. score, 50, 80, 0, 2, 2)
        love.graphics.print("PLAYS REMAINING: " .. playsLeft, 50, 140, 0, 1.5, 1.5)
        love.graphics.print("COINS: " .. coins, 800, 40, 0, 1.3, 1.3)

        love.graphics.printf("Controls: Press keys [1-10] to toggle combo cards. Press [ENTER] to score chain! [ESC] to clear selection.", 50, 220, 900, "center")

        local valid = isValidChain()
        if #selectedCards > 0 then
            if valid then
                love.graphics.setColor(0.3, 0.8, 0.3)
                love.graphics.printf("CHAIN VALID! Ready to score.", 50, 260, 900, "center")
            else
                love.graphics.setColor(0.8, 0.2, 0.2)
                love.graphics.printf("INVALID CHAIN! Next card must match color or number.", 50, 260, 900, "center")
            end
        end

        local cardWidth = 32 * 3.5  -- Matches roughly 112px wide
        local cardHeight = 48 * 3.5 -- Matches roughly 168px tall
        local startX = (love.graphics.getWidth() - (#hand * (cardWidth + 15))) / 2
        local startY = 380

        for i, card in ipairs(hand) do
            local x = startX + (i - 1) * (cardWidth + 15)
            local liftY = cardAnim[i] and cardAnim[i].y or 0
            local y = startY + liftY

            local isSelected = false
            for _, selIdx in ipairs(selectedCards) do
                if selIdx == i then isSelected = true break end
            end

            -- Render the visual sprite layout via Cards.draw
            Cards.draw(card, x, y, 3.5)

            -- Selection borders overlay
            if isSelected then
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.setLineWidth(4)
                love.graphics.rectangle("line", x, y, cardWidth, cardHeight, 4, 4)
            end

            -- Card index text indicators
            love.graphics.setColor(0, 0, 0, 0.75)
            love.graphics.rectangle("fill", x + 4, y + 4, 24, 18, 3, 3)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print("["..i.."]", x + 6, y + 6)
        end

    elseif gameState == states.SHOP then
        love.graphics.setColor(1, 0.9, 0.3)
        love.graphics.printf("ANTE " .. ante .. " CLEARED! SHOP", 0, 60, love.graphics.getWidth(), "center", 0, 2, 2)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("Coins: " .. coins, 0, 120, love.graphics.getWidth(), "center", 0, 1.4, 1.4)
        love.graphics.printf("Press [1-3] to buy a relic. Press [SPACE] to continue to Ante " .. (ante + 1), 0, 160, love.graphics.getWidth(), "center")

        local cardWidth = 260
        local cardHeight = 220
        local startX = (love.graphics.getWidth() - (#shopOffers * (cardWidth + 30))) / 2
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
            love.graphics.printf("Owned: " .. table.concat(names, ", "), 0, 480, love.graphics.getWidth(), "center")
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

    for _, t in ipairs(floatingTexts) do
        local alpha = math.max(0, t.life / t.maxLife)
        love.graphics.setColor(t.color[1], t.color[2], t.color[3], alpha)
        love.graphics.printf(t.text, t.x - 150, t.y, 300, "center", 0, 2, 2)
    end

    love.graphics.pop()
end