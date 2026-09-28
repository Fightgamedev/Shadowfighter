local arenaWidth = 960
local floorY = 460
local gravity = 1500
local jumpSpeed = 600
local maxHealth = 100
local fighterWidth = 38
local standingHeight = 76
local crouchingHeight = 44
local blockDamageScale = 0.20
local blockKnockbackScale = 0.25
local roundDuration = 60
local roundEndDelay = 2
local roundsToWin = 2
local fighter1StartX = 260
local fighter2StartX = 700
local cpuEnabled = true
local cpuDifficulty = "normal"
local uiFont = love.graphics.newFont(12)
local timerFont = love.graphics.newFont(28)
local resultFont = love.graphics.newFont(38)

local attacks = {
    punch = { duration = 0.18, recovery = 0.28, range = 58, height = 26,
        damage = 24, knockback = 22, yOffset = 48 },
    kick = { duration = 0.25, recovery = 0.34, range = 82, height = 24,
        damage = 34, knockback = 30, yOffset = 30 },
}

local cpuProfiles = {
    easy = {
        reactionMin = 0.70, reactionMax = 1.00,
        attackChance = 0.48, blockChance = 0.12, jumpChance = 0.04,
        attackCooldownMin = 1.5, attackCooldownMax = 2.0,
    },
    normal = {
        reactionMin = 0.30, reactionMax = 0.52,
        attackChance = 0.65, blockChance = 0.16, jumpChance = 0.08,
        attackCooldownMin = 1.1, attackCooldownMax = 1.45,
    },
    hard = {
        reactionMin = 0.14, reactionMax = 0.28,
        attackChance = 0.88, blockChance = 0.20, jumpChance = 0.12,
        attackCooldownMin = 0.48, attackCooldownMax = 0.72,
    },
}

local cpu = {
    decisionTimer = 0.35,
    attackCooldown = 0,
    blockTimer = 0,
    jumpCooldown = 0,
}

local Fighter = {}
Fighter.__index = Fighter

function Fighter.new(x, color, controls)
    return setmetatable({
        startX = x,
        x = x,
        y = floorY,
        velocityY = 0,
        speed = 280,
        grounded = true,
        health = maxHealth,
        maxHealth = maxHealth,
        facing = 1,
        color = color,
        controls = controls,
        state = "idle",
        blocking = false,
        crouching = false,
        attack = nil,
        recovery = 0,
        ko = false,
    }, Fighter)
end

function Fighter:reset()
    self.x = self.startX
    self.y = floorY
    self.velocityY = 0
    self.grounded = true
    self.health = self.maxHealth
    self.facing = self.startX < arenaWidth / 2 and 1 or -1
    self.state = "idle"
    self.blocking = false
    self.crouching = false
    self.attack = nil
    self.recovery = 0
    self.ko = false
end

function Fighter:takeDamage(amount, knockback, attacker)
    if self.ko then
        return
    end

    local damageScale = self.blocking and blockDamageScale or 1
    local knockbackScale = self.blocking and blockKnockbackScale or 1
    local damage = math.max(1, math.floor(amount * damageScale + 0.5))
    self.health = math.max(0, self.health - damage)
    if self.health == 0 then
        self.ko = true
        self.attack = nil
        self.recovery = 0
        self.blocking = false
        return
    end

    self.x = math.max(fighterWidth / 2,
        math.min(arenaWidth - fighterWidth / 2,
            self.x + attacker.facing * knockback * knockbackScale))
end

function Fighter:isDown(control)
    if self.aiInput then
        return self.aiInput[control] == true
    end
    return love.keyboard.isDown(self.controls[control])
end

function Fighter:jump()
    if not self.ko and self.grounded then
        self.velocityY = -jumpSpeed
        self.grounded = false
    end
end

function Fighter:startAttack(kind)
    if self.ko or self.blocking or self:isDown("block")
        or self.attack or self.recovery > 0 then
        return
    end

    local settings = attacks[kind]
    self.attack = {
        kind = kind,
        timer = settings.duration,
        hitOpponent = false,
        hitbox = { x = 0, y = 0, width = settings.range, height = settings.height },
    }
end

function Fighter:update(dt)
    if self.ko then
        self.state = "ko"
        return
    end

    self.blocking = not self.attack and self:isDown("block")
    local direction = 0
    if self:isDown("left") then
        direction = direction - 1
    end
    if self:isDown("right") then
        direction = direction + 1
    end
    self.x = math.max(fighterWidth / 2,
        math.min(arenaWidth - fighterWidth / 2, self.x + direction * self.speed * dt))

    if not self.grounded then
        self.velocityY = self.velocityY + gravity * dt
        self.y = self.y + self.velocityY * dt
        if self.y >= floorY then
            self.y = floorY
            self.velocityY = 0
            self.grounded = true
        end
    end

    self.crouching = self.grounded and self:isDown("crouch")
    self.recovery = math.max(0, self.recovery - dt)
end

function Fighter:updateState()
    if self.ko then
        self.state = "ko"
    elseif self.attack then
        self.state = self.attack.kind == "punch" and "punching" or "kicking"
    elseif self.blocking then
        self.state = "blocking"
    elseif not self.grounded then
        self.state = "jumping"
    elseif self.crouching then
        self.state = "crouching"
    elseif self:isDown("left") or self:isDown("right") then
        self.state = "walking"
    else
        self.state = "idle"
    end
end

local fighter1 = Fighter.new(fighter1StartX, { 0.42, 0.72, 0.88 }, {
    left = "a", right = "d", jump = "w", crouch = "s",
    punch = "j", kick = "k", block = "l",
})
local fighter2 = Fighter.new(fighter2StartX, { 0.88, 0.38, 0.25 }, {
    left = "left", right = "right", jump = "up", crouch = "down",
    punch = "n", kick = "m", block = "b",
})

local fighters = { fighter1, fighter2 }

local game = {
    state = "fighting",
    timeRemaining = roundDuration,
    round = 1,
    score1 = 0,
    score2 = 0,
    result = "",
    transitionTimer = 0,
}

local function resetRound()
    fighter1:reset()
    fighter2:reset()
    fighter2.aiInput = nil
    cpu.decisionTimer = 0.35
    cpu.attackCooldown = 0
    cpu.blockTimer = 0
    cpu.jumpCooldown = 0
    game.timeRemaining = roundDuration
    game.result = ""
    game.transitionTimer = 0
    game.state = "fighting"
end

local function restartMatch()
    game.round = 1
    game.score1 = 0
    game.score2 = 0
    resetRound()
end

local function finishRound(winner)
    if game.state ~= "fighting" then
        return
    end

    if winner == 1 then
        game.score1 = game.score1 + 1
        game.result = "FIGHTER 1 WINS"
    elseif winner == 2 then
        game.score2 = game.score2 + 1
        game.result = "FIGHTER 2 WINS"
    else
        game.result = "DRAW"
    end

    fighter1.attack = nil
    fighter2.attack = nil
    fighter1.blocking = false
    fighter2.blocking = false
    fighter1.state = fighter1.ko and "ko" or "idle"
    fighter2.state = fighter2.ko and "ko" or "idle"

    if (winner == 1 and game.score1 >= roundsToWin)
        or (winner == 2 and game.score2 >= roundsToWin) then
        game.result = "FIGHTER " .. winner .. " WINS THE MATCH"
        game.state = "match_over"
    else
        game.state = "round_over"
        game.transitionTimer = roundEndDelay
    end
end

local function overlaps(a, b)
    return a.x < b.x + b.width and a.x + a.width > b.x
        and a.y < b.y + b.height and a.y + a.height > b.y
end

local function updateAttack(attacker, defender, dt)
    local attack = attacker.attack
    if not attack then
        return
    end

    local settings = attacks[attack.kind]
    local hitbox = attack.hitbox
    hitbox.y = attacker.y - settings.yOffset
    if attacker.facing > 0 then
        hitbox.x = attacker.x + fighterWidth / 2 + 2
    else
        hitbox.x = attacker.x - fighterWidth / 2 - 2 - hitbox.width
    end

    if not attack.hitOpponent and not defender.ko then
        local defenderHeight = defender.crouching and crouchingHeight or standingHeight
        local defenderBox = {
            x = defender.x - fighterWidth / 2,
            y = defender.y - defenderHeight,
            width = fighterWidth,
            height = defenderHeight,
        }
        if overlaps(hitbox, defenderBox) then
            attack.hitOpponent = true
            defender:takeDamage(settings.damage, settings.knockback, attacker)
        end
    end

    attack.timer = attack.timer - dt
    if attack.timer <= 0 then
        attacker.attack = nil
        attacker.recovery = settings.recovery
    end
end

local function separateFighters()
    local minimumDistance = fighterWidth
    local distance = fighter2.x - fighter1.x
    if math.abs(distance) >= minimumDistance then
        return
    end

    local direction = distance >= 0 and 1 or -1
    local overlap = minimumDistance - math.abs(distance)
    fighter1.x = fighter1.x - direction * overlap / 2
    fighter2.x = fighter2.x + direction * overlap / 2

    -- Keep separation when one fighter is already against an arena edge.
    if fighter1.x < fighterWidth / 2 then
        fighter1.x = fighterWidth / 2
        fighter2.x = fighter1.x + minimumDistance
    elseif fighter2.x > arenaWidth - fighterWidth / 2 then
        fighter2.x = arenaWidth - fighterWidth / 2
        fighter1.x = fighter2.x - minimumDistance
    end
end

local function updateCpu(dt)
    local profile = cpuProfiles[cpuDifficulty] or cpuProfiles.normal
    local input = { left = false, right = false, crouch = false, block = false }
    fighter2.aiInput = input

    cpu.decisionTimer = math.max(0, cpu.decisionTimer - dt)
    cpu.attackCooldown = math.max(0, cpu.attackCooldown - dt)
    cpu.blockTimer = math.max(0, cpu.blockTimer - dt)
    cpu.jumpCooldown = math.max(0, cpu.jumpCooldown - dt)

    local horizontalDistance = fighter1.x - fighter2.x
    local distance = math.abs(horizontalDistance)
    if distance > 90 then
        input.left = horizontalDistance < 0
        input.right = horizontalDistance > 0
    end
    input.block = cpu.blockTimer > 0

    if cpu.decisionTimer > 0 or fighter2.ko then
        return
    end

    cpu.decisionTimer = profile.reactionMin
        + love.math.random() * (profile.reactionMax - profile.reactionMin)
    local roll = love.math.random()

    if distance <= 145 and roll < profile.blockChance
        and cpu.blockTimer == 0 and not fighter2.attack then
        cpu.blockTimer = 0.30 + love.math.random() * 0.35
    elseif roll < profile.blockChance + profile.jumpChance
        and fighter2.grounded and cpu.jumpCooldown == 0 then
        fighter2:jump()
        cpu.jumpCooldown = 2.0 + love.math.random() * 2.0
    elseif distance <= 128 and roll < profile.blockChance + profile.jumpChance + profile.attackChance
        and cpu.attackCooldown == 0 and not fighter2.attack and not fighter2.blocking then
        local kind = love.math.random() < 0.5 and "punch" or "kick"
        fighter2:startAttack(kind)
        cpu.attackCooldown = profile.attackCooldownMin
            + love.math.random() * (profile.attackCooldownMax - profile.attackCooldownMin)
    end
end

function love.keypressed(key, scancode, isrepeat)
    if key == "r" and not isrepeat then
        restartMatch()
        return
    elseif key == "escape" then
        love.event.quit()
        return
    end
    if isrepeat or game.state ~= "fighting" then
        return
    end

    for _, fighter in ipairs(fighters) do
        if not (cpuEnabled and fighter == fighter2) then
            if key == fighter.controls.jump then
                fighter:jump()
            elseif key == fighter.controls.punch then
                fighter:startAttack("punch")
            elseif key == fighter.controls.kick then
                fighter:startAttack("kick")
            end
        end
    end
end

function love.update(dt)
    if game.state == "round_over" then
        game.transitionTimer = game.transitionTimer - dt
        if game.transitionTimer <= 0 then
            game.round = game.round + 1
            resetRound()
        end
        return
    elseif game.state == "match_over" then
        return
    end

    game.timeRemaining = math.max(0, game.timeRemaining - dt)
    if cpuEnabled and game.state == "fighting" then
        updateCpu(dt)
    else
        fighter2.aiInput = nil
    end
    fighter1:update(dt)
    fighter2:update(dt)
    separateFighters()

    if fighter2.x > fighter1.x then
        fighter1.facing = 1
        fighter2.facing = -1
    else
        fighter1.facing = -1
        fighter2.facing = 1
    end

    updateAttack(fighter1, fighter2, dt)
    updateAttack(fighter2, fighter1, dt)
    separateFighters()

    fighter1:updateState()
    fighter2:updateState()

    if fighter1.ko and fighter2.ko then
        finishRound(nil)
    elseif fighter1.ko then
        finishRound(2)
    elseif fighter2.ko then
        finishRound(1)
    elseif game.timeRemaining <= 0 then
        if fighter1.health > fighter2.health then
            finishRound(1)
        elseif fighter2.health > fighter1.health then
            finishRound(2)
        else
            finishRound(nil)
        end
    end
end

local function drawFighter(fighter)
    local bodyHeight = fighter.crouching and crouchingHeight or standingHeight
    local bodyTop = fighter.y - bodyHeight
    love.graphics.setColor(fighter.color[1], fighter.color[2], fighter.color[3])
    love.graphics.rectangle("fill", fighter.x - fighterWidth / 2, bodyTop,
        fighterWidth, bodyHeight)
    love.graphics.circle("fill", fighter.x, bodyTop - 11, 12)

    if fighter.blocking then
        love.graphics.setColor(0.55, 0.88, 1, 0.8)
        love.graphics.rectangle("line", fighter.x - fighterWidth / 2 - 5,
            bodyTop - 5, fighterWidth + 10, bodyHeight + 10)
    end

    if fighter.attack then
        local hitbox = fighter.attack.hitbox
        if fighter.attack.kind == "punch" then
            love.graphics.setColor(1, 0.86, 0.20, 0.45)
        else
            love.graphics.setColor(1, 0.42, 0.12, 0.45)
        end
        love.graphics.rectangle("fill", hitbox.x, hitbox.y, hitbox.width, hitbox.height)
        love.graphics.setColor(1, 0.95, 0.75, 0.9)
        love.graphics.rectangle("line", hitbox.x, hitbox.y, hitbox.width, hitbox.height)
    end
end

local function drawHealthBar(fighter, x, alignRight, label)
    local barWidth = 180
    local barX = alignRight and x - barWidth or x
    love.graphics.setColor(0.10, 0.10, 0.13)
    love.graphics.rectangle("fill", barX, 64, barWidth, 16)
    love.graphics.setColor(fighter.color[1], fighter.color[2], fighter.color[3])
    love.graphics.rectangle("fill", barX, 64,
        barWidth * fighter.health / fighter.maxHealth, 16)
    love.graphics.setColor(0.92, 0.94, 1)
    if alignRight then
        love.graphics.printf(label .. " HP " .. fighter.health,
            barX - 132, 63, 124, "right")
        love.graphics.printf("State: " .. fighter.state, barX - 132, 86, 304, "right")
    else
        love.graphics.print(label .. " HP " .. fighter.health, barX + barWidth + 8, 63)
        love.graphics.print("State: " .. fighter.state, barX, 86)
    end

    local attackStatus = "READY"
    if fighter.attack then
        attackStatus = string.upper(fighter.attack.kind) .. " ACTIVE"
    elseif fighter.recovery > 0 then
        attackStatus = "RECOVERY"
    elseif fighter.blocking then
        attackStatus = "BLOCKING"
    end
    if alignRight then
        love.graphics.printf("Attack: " .. attackStatus,
            barX - 132, 106, 304, "right")
    else
        love.graphics.print("Attack: " .. attackStatus, barX, 106)
    end
end

function love.draw()
    love.graphics.setFont(uiFont)
    love.graphics.clear(0.055, 0.065, 0.105)

    love.graphics.setColor(0.09, 0.105, 0.16)
    love.graphics.rectangle("fill", 0, 300, arenaWidth, 160)
    love.graphics.setColor(0.18, 0.20, 0.27)
    love.graphics.rectangle("fill", 0, floorY, arenaWidth, 80)
    love.graphics.setColor(0.40, 0.42, 0.50)
    love.graphics.rectangle("fill", 0, floorY, arenaWidth, 3)

    drawFighter(fighter1)
    drawFighter(fighter2)
    drawHealthBar(fighter1, 12, false, "F1")
    drawHealthBar(fighter2, arenaWidth - 12, true, "F2")

    love.graphics.setColor(0.92, 0.94, 1)
    love.graphics.setFont(timerFont)
    love.graphics.printf(string.format("%02d", math.ceil(game.timeRemaining)),
        0, 0, arenaWidth, "center")
    love.graphics.setFont(uiFont)
    love.graphics.printf("ROUND " .. game.round .. "     F1 " .. game.score1
        .. " - " .. game.score2 .. " F2", 0, 34, arenaWidth, "center")

    if game.state == "round_over" or game.state == "match_over" then
        love.graphics.setColor(1, 0.82, 0.25)
        love.graphics.setFont(resultFont)
        love.graphics.printf(game.result, 0, 190, arenaWidth, "center")
        love.graphics.setFont(uiFont)
        if game.state == "round_over" then
            love.graphics.setColor(0.92, 0.94, 1)
            love.graphics.printf("NEXT ROUND IN " .. math.ceil(game.transitionTimer),
                0, 245, arenaWidth, "center")
        else
            love.graphics.setColor(0.92, 0.94, 1)
            love.graphics.printf("PRESS R TO RESTART", 0, 245, arenaWidth, "center")
        end
    end

    love.graphics.setFont(uiFont)
    love.graphics.setColor(0.92, 0.94, 1)
    love.graphics.print("FPS: " .. love.timer.getFPS(), 12, 12)
end
