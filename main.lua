local arenaWidth = 960
local levelWidth = 3600
local flagX = levelWidth - 150
local floorY = 460
local gravity = 1500
local jumpSpeed = 600
local maxHealth = 100
local fighterWidth = 38
local standingHeight = 76
local crouchingHeight = 44
local blockDamageScale = 0.20
local blockKnockbackScale = 0.25
local roundDuration = 120
local roundEndDelay = 2
local roundsToWin = 2
local hitStopDuration = 0.06
local hitFlashDuration = 0.12
local comboTimeout = 1.5
local fighter1StartX = 260
local fighter2StartX = 700
local cameraX = 0
local cameraCenterX = arenaWidth / 2
local cameraZoom = 1
local mountDistance = 72
local riderOffset = 34
local cpuEnabled = false
local cpuDifficulty = "normal"
local uiFont = love.graphics.newFont(12)
local timerFont = love.graphics.newFont(28)
local resultFont = love.graphics.newFont(38)
local titleFont = love.graphics.newFont(46)
local characterFont = love.graphics.newFont(24)

local characters = {
    {
        name = "EMBER", title = "THE FIREBRAND",
        color = { 0.94, 0.28, 0.18 }, accent = { 1.00, 0.72, 0.20 },
        health = 95, speed = 315, power = 1.08, jump = 1.04,
        affinity = "HORSE",
        description = "Fast, fearless, and built for pressure.",
    },
    {
        name = "TEMPEST", title = "THE SKY DANCER",
        color = { 0.22, 0.68, 0.96 }, accent = { 0.58, 0.92, 1.00 },
        health = 90, speed = 325, power = 0.96, jump = 1.16,
        affinity = "HORSE",
        description = "Lightning movement and unmatched jumps.",
    },
    {
        name = "WARDEN", title = "THE IRON WALL",
        color = { 0.50, 0.58, 0.70 }, accent = { 0.88, 0.92, 1.00 },
        health = 120, speed = 245, power = 1.12, jump = 0.92,
        affinity = "BOAR",
        description = "Heavy armor, crushing blows, steady feet.",
    },
    {
        name = "VIPER", title = "THE NIGHT HUNTER",
        color = { 0.50, 0.88, 0.35 }, accent = { 0.78, 1.00, 0.48 },
        health = 100, speed = 290, power = 1.04, jump = 1.08,
        affinity = "BOAR",
        description = "Balanced, elusive, and hard to predict.",
    },
}

local attacks = {
    punch = { startup = 0.07, active = 0.10, recovery = 0.29, range = 58, height = 26,
        damage = 24, knockback = 22, yOffset = 48 },
    kick = { startup = 0.11, active = 0.14, recovery = 0.36, range = 82, height = 24,
        damage = 34, knockback = 30, yOffset = 30 },
}

local specialMoves = {
    { name = "CHAIN HOOK", cooldown = 5.0, duration = 0.62 },
    { name = "SHADOW RUSH", cooldown = 4.0, duration = 0.34 },
    { name = "SOUL BURST", cooldown = 6.0, duration = 0.48 },
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

local pits = {
    { left = 1160, right = 1310 },
    { left = 1980, right = 2160 },
    { left = 2860, right = 3030 },
}

local platforms = {
    { x = 1030, y = 365, width = 150, height = 18 },
    { x = 1260, y = 335, width = 145, height = 18, moving = true,
        startX = 1260, range = 130, speed = 1.35, phase = 0 },
    { x = 1740, y = 345, width = 180, height = 18 },
    { x = 2020, y = 305, width = 150, height = 18, moving = true,
        startX = 2020, range = 105, speed = 1.55, phase = 1.7 },
    { x = 2570, y = 350, width = 165, height = 18 },
    { x = 2900, y = 320, width = 165, height = 18, moving = true,
        startX = 2900, range = 120, speed = 1.25, phase = 3.1 },
}

local spikes = {
    { x = 720, width = 80 }, { x = 1490, width = 90 },
    { x = 2440, width = 90 }, { x = 3230, width = 75 },
}

local function isOverPit(x)
    for _, pit in ipairs(pits) do
        if x > pit.left and x < pit.right then
            return true
        end
    end
    return false
end

local function platformAtFoot(x, y)
    for _, platform in ipairs(platforms) do
        if x >= platform.x - 12 and x <= platform.x + platform.width + 12
            and math.abs(y - platform.y) < 5 then
            return platform
        end
    end
    return nil
end

local loseLife
local spawnFireball
local fireballs = {}

local Fighter = {}
Fighter.__index = Fighter

function Fighter.new(x, color, controls)
    return setmetatable({
        startX = x,
        x = x,
        y = floorY,
        velocityY = 0,
        speed = 280,
        power = 1,
        jumpScale = 1,
        character = nil,
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
        hitFlash = 0,
        combo = 0,
        comboTimer = 0,
        ko = false,
        mount = nil,
        special = nil,
        specialCooldowns = { 0, 0, 0 },
        mushroomTimer = 0,
        shieldHealth = 0,
        fireTimer = 0,
        fireballCooldown = 0,
        bootsTimer = 0,
        bondCharmTimer = 0,
        stunTimer = 0,
        invulnerableTimer = 0,
        platform = nil,
        comebackBoost = 1,
    }, Fighter)
end

function Fighter:reset()
    if self.mount then
        self.mount.rider = nil
        self.mount = nil
    end
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
    self.hitFlash = 0
    self.combo = 0
    self.comboTimer = 0
    self.ko = false
    self.special = nil
    self.specialCooldowns = { 0, 0, 0 }
    self.mushroomTimer = 0
    self.shieldHealth = 0
    self.fireTimer = 0
    self.fireballCooldown = 0
    self.bootsTimer = 0
    self.bondCharmTimer = 0
    self.stunTimer = 0
    self.invulnerableTimer = 0
    self.platform = nil
    self.comebackBoost = 1
end

function Fighter:takeDamage(amount, knockback, attacker)
    if self.ko or self.invulnerableTimer > 0 then
        return
    end

    local damageScale = self.blocking and blockDamageScale or 1
    if self.mushroomTimer > 0 then
        damageScale = damageScale * 0.80
    end
    local knockbackScale = self.blocking and blockKnockbackScale or 1
    local damage = math.max(1, math.floor(amount * damageScale + 0.5))
    if self.shieldHealth > 0 then
        local absorbed = math.min(self.shieldHealth, damage)
        self.shieldHealth = self.shieldHealth - absorbed
        damage = damage - absorbed
        self.hitFlash = hitFlashDuration
        if damage <= 0 then
            return
        end
    end
    self.health = math.max(0, self.health - damage)
    if self.health == 0 then
        self.ko = true
        self.attack = nil
        self.special = nil
        self.recovery = 0
        self.blocking = false
        if self.mount then
            self.mount.rider = nil
            self.mount.x = self.x
            self.mount.bonded = false
            self.mount.mood = "STARTLED"
            self.mount = nil
        end
        return
    end

    self.x = math.max(fighterWidth / 2,
        math.min(levelWidth - fighterWidth / 2,
            self.x + attacker.facing * knockback * knockbackScale))
end

function Fighter:isDown(control)
    if self.aiInput then
        return self.aiInput[control] == true
    end
    if self.phoneInput and self.phoneInput[control] then
        return true
    end
    return love.keyboard.isDown(self.controls[control])
end

function Fighter:jump()
    if not self.ko and self.stunTimer <= 0 and self.grounded then
        local mountJump = self.mount and self.mount.jumpBoost or 1
        if self.mount and self.mount.bonded then
            mountJump = mountJump + 0.08
        end
        self.velocityY = -jumpSpeed * self.jumpScale * mountJump
        self.grounded = false
    end
end

function Fighter:startAttack(kind)
    if self.ko or self.stunTimer > 0 or self.blocking or self:isDown("block")
        or self.attack or self.special or self.recovery > 0 then
        return
    end

    local settings = attacks[kind]
    local sizeScale = self.mushroomTimer > 0 and 1.35 or 1
    self.attack = {
        kind = kind,
        phase = "startup",
        timer = settings.startup,
        hitOpponent = false,
        hitbox = { x = 0, y = 0, width = settings.range * sizeScale,
            height = settings.height * sizeScale },
    }
    if kind == "punch" and self.fireTimer > 0 and self.fireballCooldown <= 0
        and spawnFireball then
        spawnFireball(self)
        self.fireballCooldown = 0.65
    end
end

function Fighter:startSpecial(index)
    if self.ko or self.stunTimer > 0 or self.attack or self.special or self.blocking
        or self.recovery > 0 or self.specialCooldowns[index] > 0 then
        return false
    end
    local move = specialMoves[index]
    self.special = {
        index = index,
        name = move.name,
        timer = move.duration,
        duration = move.duration,
        hit = false,
        targetX = self.x + self.facing * (index == 1 and 390 or 110),
    }
    self.specialCooldowns[index] = move.cooldown
    self.blocking = false
    return true
end

function Fighter:update(dt)
    self.hitFlash = math.max(0, self.hitFlash - dt)
    self.comboTimer = math.max(0, self.comboTimer - dt)
    for i = 1, 3 do
        self.specialCooldowns[i] = math.max(0, self.specialCooldowns[i] - dt)
    end
    self.mushroomTimer = math.max(0, self.mushroomTimer - dt)
    self.fireTimer = math.max(0, self.fireTimer - dt)
    self.fireballCooldown = math.max(0, self.fireballCooldown - dt)
    self.bootsTimer = math.max(0, self.bootsTimer - dt)
    self.bondCharmTimer = math.max(0, self.bondCharmTimer - dt)
    self.stunTimer = math.max(0, self.stunTimer - dt)
    self.invulnerableTimer = math.max(0, self.invulnerableTimer - dt)
    if self.comboTimer == 0 then
        self.combo = 0
    end
    if self.ko then
        self.state = "ko"
        return
    end
    if self.stunTimer > 0 then
        self.state = "stunned"
        self.blocking = false
    end

    if self.platform then
        self.x = self.x + (self.platform.dx or 0)
    end
    if self.grounded then
        local support = platformAtFoot(self.x, self.y)
        if self.y == floorY and not isOverPit(self.x) then
            self.platform = nil
        elseif support then
            self.platform = support
        else
            self.grounded = false
            self.platform = nil
        end
    end

    local canControl = self.stunTimer <= 0
    self.blocking = canControl and not self.attack and not self.special
        and self:isDown("block")
    local direction = 0
    if canControl and self:isDown("left") then
        direction = direction - 1
    end
    if canControl and self:isDown("right") then
        direction = direction + 1
    end
    local speedMultiplier = self.mount and self.mount.speedBoost or 1
    if self.mount and self.mount.bonded then
        speedMultiplier = speedMultiplier + 0.12
    end
    if self.bootsTimer > 0 then
        speedMultiplier = speedMultiplier * 1.35
    end
    speedMultiplier = speedMultiplier * self.comebackBoost
    self.x = math.max(fighterWidth / 2,
        math.min(levelWidth - fighterWidth / 2,
            self.x + direction * self.speed * speedMultiplier * dt))
    if self.mount then
        self.mount.x = self.x
        self.mount.y = self.y
        self.mount.facing = self.facing
    end

    if not self.grounded then
        local previousY = self.y
        self.velocityY = self.velocityY + gravity * dt
        self.y = self.y + self.velocityY * dt
        local landedPlatform = nil
        if self.velocityY >= 0 then
            for _, platform in ipairs(platforms) do
                if self.x >= platform.x - 12
                    and self.x <= platform.x + platform.width + 12
                    and previousY <= platform.y and self.y >= platform.y then
                    landedPlatform = platform
                    break
                end
            end
        end
        if landedPlatform then
            self.y = landedPlatform.y
            self.velocityY = 0
            self.grounded = true
            self.platform = landedPlatform
        elseif self.y >= floorY and not isOverPit(self.x) then
            self.y = floorY
            self.velocityY = 0
            self.grounded = true
            self.platform = nil
        elseif self.y > floorY + 220 and loseLife then
            loseLife(self, "FELL")
            return
        end
    end

    self.crouching = self.grounded and self:isDown("crouch")
    self.recovery = math.max(0, self.recovery - dt)
end

function Fighter:updateState()
    if self.ko then
        self.state = "ko"
    elseif self.stunTimer > 0 then
        self.state = "stunned"
    elseif self.special then
        self.state = string.lower(self.special.name):gsub(" ", "_")
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
    special1 = "u", special2 = "i", special3 = "o",
})
local fighter2 = Fighter.new(fighter2StartX, { 0.88, 0.38, 0.25 }, {
    left = "left", right = "right", jump = "up", crouch = "down",
    punch = "n", kick = "m", block = "b",
    special1 = "1", special2 = "2", special3 = "3",
})

local fighters = { fighter1, fighter2 }
local selectedCharacter = { 1, 2 }
local selectionReady = { false, false }
local menuPulse = 0

local function applyCharacter(fighter, characterIndex)
    local character = characters[characterIndex]
    fighter.character = character
    fighter.color = character.color
    fighter.speed = character.speed
    fighter.power = character.power
    fighter.jumpScale = character.jump
    fighter.maxHealth = character.health
    fighter.health = character.health
end

local animals = {
    {
        kind = "HORSE", x = 200, startX = 200, y = floorY,
        color = { 0.58, 0.34, 0.17 }, mane = { 0.18, 0.11, 0.08 },
        speedBoost = 1.45, jumpBoost = 1.18, rider = nil, facing = 1,
        mood = "CURIOUS", bob = 0, bondTimer = 0, bonded = false,
    },
    {
        kind = "BOAR", x = 760, startX = 760, y = floorY,
        color = { 0.42, 0.30, 0.24 }, mane = { 0.20, 0.16, 0.14 },
        speedBoost = 1.25, jumpBoost = 1.08, rider = nil, facing = -1,
        mood = "GRUMPY", bob = 0, bondTimer = 0, bonded = false,
    },
}

local levelBlocks = {
    { x = 840, y = 278, powerType = "MUSHROOM" },
    { x = 900, y = 222, powerType = "SHIELD" },
    { x = 960, y = 278, powerType = "FIRE" },
    { x = 1580, y = 260, powerType = "BOOTS" },
    { x = 1640, y = 204, powerType = "BOND" },
    { x = 2260, y = 278, powerType = "LIGHTNING" },
    { x = 2320, y = 222, powerType = "SHIELD" },
    { x = 2380, y = 278, powerType = "FIRE" },
    { x = 2920, y = 250, powerType = "MUSHROOM" },
}
local mushrooms = {}

local function resetPowerUps()
    mushrooms = {}
    for _, block in ipairs(levelBlocks) do
        block.hit = false
        block.bump = 0
    end
end

local function spawnPowerUp(block, fighter)
    block.hit = true
    block.bump = 0.22
    table.insert(mushrooms, {
        kind = block.powerType,
        x = block.x + 23,
        y = block.y - 10,
        velocityY = -120,
        direction = fighter.facing,
        collected = false,
    })
end

local function updatePowerUps(dt)
    for _, block in ipairs(levelBlocks) do
        block.bump = math.max(0, (block.bump or 0) - dt)
        if not block.hit then
            for _, fighter in ipairs(fighters) do
                local scale = fighter.mushroomTimer > 0 and 1.35 or 1
                local headY = fighter.y - (fighter.mount and riderOffset or 0)
                    - standingHeight * scale - 22 * scale
                if fighter.velocityY < 0
                    and math.abs(fighter.x - (block.x + 23)) < 38
                    and headY <= block.y + 54 and headY >= block.y + 18 then
                    spawnPowerUp(block, fighter)
                    fighter.velocityY = math.max(80, -fighter.velocityY * 0.25)
                    break
                end
            end
        end
    end

    for _, mushroom in ipairs(mushrooms) do
        if not mushroom.collected then
            mushroom.velocityY = mushroom.velocityY + gravity * dt
            mushroom.y = mushroom.y + mushroom.velocityY * dt
            if mushroom.y >= floorY - 18 then
                mushroom.y = floorY - 18
                mushroom.velocityY = 0
                mushroom.x = mushroom.x + mushroom.direction * 72 * dt
            end
            mushroom.x = math.max(20, math.min(levelWidth - 20, mushroom.x))

            for _, fighter in ipairs(fighters) do
                if not fighter.ko and math.abs(fighter.x - mushroom.x) < 34
                    and math.abs(fighter.y - mushroom.y) < 70 then
                    mushroom.collected = true
                    if mushroom.kind == "MUSHROOM" then
                        fighter.mushroomTimer = 14
                        fighter.health = math.min(fighter.maxHealth, fighter.health + 25)
                    elseif mushroom.kind == "SHIELD" then
                        fighter.shieldHealth = 40
                    elseif mushroom.kind == "FIRE" then
                        fighter.fireTimer = 14
                    elseif mushroom.kind == "BOOTS" then
                        fighter.bootsTimer = 12
                    elseif mushroom.kind == "BOND" then
                        fighter.bondCharmTimer = 16
                        if fighter.mount then
                            fighter.mount.bonded = true
                            fighter.mount.bondTimer = 2.4
                        end
                    elseif mushroom.kind == "LIGHTNING" then
                        local opponent = fighter == fighter1 and fighter2 or fighter1
                        opponent.stunTimer = math.max(opponent.stunTimer, 1.5)
                        opponent.attack = nil
                        opponent.special = nil
                    end
                    fighter.hitFlash = 0.35
                    break
                end
            end
        end
    end
end

local function resetAnimals()
    for _, animal in ipairs(animals) do
        animal.x = animal.startX
        animal.y = floorY
        animal.rider = nil
        animal.bonded = false
        animal.bondTimer = 0
        animal.mood = animal.kind == "HORSE" and "CURIOUS" or "GRUMPY"
        animal.facing = animal.startX < arenaWidth / 2 and 1 or -1
    end
end

local function toggleMount(fighter)
    if fighter.ko or not fighter.grounded or fighter.attack then
        return false
    end
    if fighter.mount then
        fighter.mount.rider = nil
        fighter.mount.bonded = false
        fighter.mount.mood = "WAITING"
        fighter.mount.x = math.max(45, math.min(levelWidth - 45,
            fighter.x - fighter.facing * 52))
        fighter.mount.y = floorY
        fighter.mount = nil
        return true
    end

    local closest = nil
    local closestDistance = mountDistance + 1
    for _, animal in ipairs(animals) do
        local distance = math.abs(fighter.x - animal.x)
        if not animal.rider and distance <= mountDistance and distance < closestDistance then
            closest = animal
            closestDistance = distance
        end
    end
    if closest then
        fighter.mount = closest
        closest.rider = fighter
        closest.bonded = fighter.bondCharmTimer > 0
            or (fighter.character and fighter.character.affinity == closest.kind)
        closest.bondTimer = closest.bonded and 2.4 or 0.8
        closest.mood = closest.bonded and "BONDED!" or "READY"
        closest.x = fighter.x
        closest.y = fighter.y
        closest.facing = fighter.facing
        return true
    end
    return false
end

local function updateAnimals(dt)
    for _, animal in ipairs(animals) do
        animal.bob = animal.bob + dt * (animal.rider and 8 or 2.5)
        animal.bondTimer = math.max(0, animal.bondTimer - dt)
        if animal.rider then
            animal.x = animal.rider.x
            animal.y = animal.rider.y
            animal.facing = animal.rider.facing
        else
            local nearest = nil
            local nearestDistance = math.huge
            for _, fighter in ipairs(fighters) do
                if not fighter.ko then
                    local distance = math.abs(fighter.x - animal.x)
                    if distance < nearestDistance then
                        nearest = fighter
                        nearestDistance = distance
                    end
                end
            end

            if nearest and nearestDistance < 150 then
                local direction = nearest.x > animal.x and 1 or -1
                animal.facing = direction
                if nearest.mount then
                    animal.mood = "STARTLED"
                    animal.x = animal.x - direction * 42 * dt
                elseif nearest.character
                    and nearest.character.affinity == animal.kind then
                    animal.mood = "FRIENDLY"
                    if nearestDistance > 62 then
                        animal.x = animal.x + direction * 24 * dt
                    end
                else
                    animal.mood = animal.kind == "HORSE" and "CURIOUS" or "WATCHING"
                end
            end
            animal.x = math.max(48, math.min(levelWidth - 48, animal.x))
            animal.y = floorY
        end
    end

    local first = animals[1]
    local second = animals[2]
    if not first.rider and not second.rider then
        local distance = second.x - first.x
        if math.abs(distance) < 105 then
            local direction = distance >= 0 and 1 or -1
            local push = (105 - math.abs(distance)) * 0.5
            first.x = first.x - direction * push
            second.x = second.x + direction * push
            first.facing = direction
            second.facing = -direction
            first.mood = "SNIFFING"
            second.mood = "SNIFFING"
        end
    end
end

local game = {
    state = "character_select",
    timeRemaining = roundDuration,
    hitStopTimer = 0,
    round = 1,
    score1 = 0,
    score2 = 0,
    result = "",
    transitionTimer = 0,
    lives = { 3, 3 },
}

local function resetPlatforms()
    for _, platform in ipairs(platforms) do
        if platform.moving then
            platform.x = platform.startX
        end
        platform.dx = 0
    end
end

local function updatePlatforms(dt)
    for _, platform in ipairs(platforms) do
        platform.dx = 0
        if platform.moving then
            local oldX = platform.x
            platform.x = platform.startX
                + math.sin(menuPulse * platform.speed + platform.phase) * platform.range
            platform.dx = platform.x - oldX
        end
    end
end

spawnFireball = function(fighter)
    table.insert(fireballs, {
        x = fighter.x + fighter.facing * 34,
        y = fighter.y - (fighter.mount and riderOffset or 0) - 44,
        velocityX = fighter.facing * 520,
        owner = fighter,
        active = true,
        life = 2.2,
    })
end

local function updateFireballs(dt)
    for _, fireball in ipairs(fireballs) do
        if fireball.active then
            fireball.x = fireball.x + fireball.velocityX * dt
            fireball.life = fireball.life - dt
            local defender = fireball.owner == fighter1 and fighter2 or fighter1
            if not defender.ko and math.abs(defender.x - fireball.x) < 30
                and math.abs((defender.y - 45) - fireball.y) < 70 then
                defender:takeDamage(18 * fireball.owner.power
                    * fireball.owner.comebackBoost, 42, fireball.owner)
                defender.hitFlash = hitFlashDuration
                fireball.active = false
            elseif fireball.life <= 0 or fireball.x < 0 or fireball.x > levelWidth then
                fireball.active = false
            end
        end
    end
end

local function checkpointFor(x)
    local checkpoints = { 180, 820, 1500, 2240, 3060 }
    local result = checkpoints[1]
    for _, checkpoint in ipairs(checkpoints) do
        if checkpoint <= x then
            result = checkpoint
        end
    end
    return result
end

loseLife = function(fighter, reason)
    if game.state ~= "fighting" then
        return
    end
    local playerNumber = fighter == fighter1 and 1 or 2
    game.lives[playerNumber] = math.max(0, game.lives[playerNumber] - 1)
    if fighter.mount then
        fighter.mount.rider = nil
        fighter.mount.bonded = false
        fighter.mount = nil
    end
    if game.lives[playerNumber] <= 0 then
        local winner = playerNumber == 1 and 2 or 1
        game.state = "match_over"
        game.result = "PLAYER " .. winner .. " WINS — NO LIVES LEFT"
        return
    end
    fighter.x = checkpointFor(fighter.x)
    fighter.y = floorY - 90
    fighter.velocityY = 0
    fighter.grounded = false
    fighter.platform = nil
    fighter.health = fighter.maxHealth
    fighter.ko = false
    fighter.attack = nil
    fighter.special = nil
    fighter.blocking = false
    fighter.mushroomTimer = 0
    fighter.shieldHealth = 0
    fighter.fireTimer = 0
    fighter.bootsTimer = 0
    fighter.stunTimer = 0
    fighter.invulnerableTimer = 2.0
    fighter.state = "respawning"
end

local function updateComebackBoosts()
    for playerNumber, fighter in ipairs(fighters) do
        local opponent = playerNumber == 1 and fighter2 or fighter1
        local otherNumber = playerNumber == 1 and 2 or 1
        local behindLives = game.lives[playerNumber] < game.lives[otherNumber]
        local behindRace = opponent.x - fighter.x > 520
        fighter.comebackBoost = (behindLives or behindRace) and 1.12 or 1
    end
end

local function updateHazards()
    for _, fighter in ipairs(fighters) do
        if not fighter.ko and fighter.invulnerableTimer <= 0
            and fighter.y >= floorY - 3 then
            for _, spike in ipairs(spikes) do
                if fighter.x > spike.x and fighter.x < spike.x + spike.width then
                    local attacker = fighter == fighter1 and fighter2 or fighter1
                    fighter:takeDamage(18, 18, attacker)
                    fighter.velocityY = -260
                    fighter.grounded = false
                    fighter.invulnerableTimer = 0.85
                    break
                end
            end
        end
    end
end

local function resetRound()
    resetAnimals()
    resetPowerUps()
    resetPlatforms()
    fireballs = {}
    fighter1:reset()
    fighter2:reset()
    game.hitStopTimer = 0
    fighter2.aiInput = nil
    cpu.decisionTimer = 0.35
    cpu.attackCooldown = 0
    cpu.blockTimer = 0
    cpu.jumpCooldown = 0
    game.timeRemaining = roundDuration
    game.result = ""
    game.transitionTimer = 0
    game.state = "fighting"
    cameraX = 0
    cameraCenterX = arenaWidth / 2
    cameraZoom = 1
end

local function restartMatch()
    game.round = 1
    game.score1 = 0
    game.score2 = 0
    game.lives = { 3, 3 }
    resetRound()
end

local function beginMatch()
    applyCharacter(fighter1, selectedCharacter[1])
    applyCharacter(fighter2, selectedCharacter[2])
    game.round = 1
    game.score1 = 0
    game.score2 = 0
    game.lives = { 3, 3 }
    resetRound()
end

local function openCharacterSelect()
    game.state = "character_select"
    selectionReady[1] = false
    selectionReady[2] = false
    fighter1.aiInput = nil
    fighter2.aiInput = nil
end

local phonePollTimer = 0
local previousPhoneEvents = { {}, {} }
local phoneEventsInitialized = false
local phoneConnected = { false, false }

local function readPhoneState()
    local contents = love.filesystem.read("phone_controls.txt")
    local values = {}
    if contents then
        for key, value in contents:gmatch("([%w_]+)=([^\n]+)") do
            values[key] = value
        end
    end
    return values
end

local function handlePhonePress(playerNumber, action)
    local fighter = fighters[playerNumber]
    if game.state == "character_select" then
        if action == "left" then
            selectedCharacter[playerNumber] = (selectedCharacter[playerNumber] - 2)
                % #characters + 1
            selectionReady[playerNumber] = false
        elseif action == "right" then
            selectedCharacter[playerNumber] = selectedCharacter[playerNumber]
                % #characters + 1
            selectionReady[playerNumber] = false
        elseif action == "confirm" or action == "punch" then
            selectionReady[playerNumber] = true
            if playerNumber == 1 and cpuEnabled then
                repeat
                    selectedCharacter[2] = love.math.random(1, #characters)
                until selectedCharacter[2] ~= selectedCharacter[1]
                selectionReady[2] = true
            end
            if selectionReady[1] and selectionReady[2] then
                beginMatch()
            end
        end
        return
    end
    if game.state ~= "fighting" or fighter.ko then
        return
    end
    if action == "jump" then
        fighter:jump()
    elseif action == "punch" then
        fighter:startAttack("punch")
    elseif action == "kick" then
        fighter:startAttack("kick")
    elseif action == "mount" then
        toggleMount(fighter)
    elseif action == "special1" then
        fighter:startSpecial(1)
    elseif action == "special2" then
        fighter:startSpecial(2)
    elseif action == "special3" then
        fighter:startSpecial(3)
    end
end

local function updatePhoneControls(dt)
    phonePollTimer = phonePollTimer - dt
    if phonePollTimer > 0 then
        return
    end
    phonePollTimer = 0.04
    local values = readPhoneState()
    local currentTime = os.time()
    -- Phone-controller sessions currently run as two-player matches.
    cpuEnabled = false

    local actions = {
        "left", "right", "jump", "crouch", "punch", "kick", "block",
        "mount", "special1", "special2", "special3", "confirm",
    }
    for playerNumber = 1, 2 do
        local seen = tonumber(values["p" .. playerNumber .. "_seen"] or "0") or 0
        local connected = currentTime - seen <= 2
        phoneConnected[playerNumber] = connected
        local current = {}
        for _, action in ipairs(actions) do
            current[action] = connected
                and values["p" .. playerNumber .. "_" .. action] == "1"
            local eventKey = "p" .. playerNumber .. "_event_" .. action
            local eventCount = tonumber(values[eventKey] or "0") or 0
            local previousCount = previousPhoneEvents[playerNumber][action]
                or eventCount
            if phoneEventsInitialized and eventCount > previousCount then
                handlePhonePress(playerNumber, action)
            end
            previousPhoneEvents[playerNumber][action] = eventCount
        end
        fighters[playerNumber].phoneInput = connected and current or nil
    end
    phoneEventsInitialized = true
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
    fighter1.special = nil
    fighter2.special = nil
    game.hitStopTimer = 0
    fighter1.blocking = false
    fighter2.blocking = false
    fighter1.state = fighter1.ko and "ko" or "idle"
    fighter2.state = fighter2.ko and "ko" or "idle"

    if (winner == 1 and game.score1 >= roundsToWin)
        or (winner == 2 and game.score2 >= roundsToWin) then
        game.result = "FIGHTER " .. winner .. " WINS THE MATCH"
        fighter1.combo = 0
        fighter1.comboTimer = 0
        fighter2.combo = 0
        fighter2.comboTimer = 0
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
    attack.timer = attack.timer - dt
    if attack.timer <= 0 then
        if attack.phase == "startup" then
            attack.phase = "active"
            attack.timer = settings.active
        else
            attacker.attack = nil
            attacker.recovery = settings.recovery
            if not attack.hitOpponent then
                attacker.combo = 0
                attacker.comboTimer = 0
            end
            return
        end
    end

    if attack.phase == "active" then
        local hitbox = attack.hitbox
        local attackerOffset = attacker.mount and riderOffset or 0
        hitbox.y = attacker.y - attackerOffset - settings.yOffset
        if attacker.facing > 0 then
            hitbox.x = attacker.x + fighterWidth / 2 + 2
        else
            hitbox.x = attacker.x - fighterWidth / 2 - 2 - hitbox.width
        end

        if not attack.hitOpponent and not defender.ko then
            local defenderScale = defender.mushroomTimer > 0 and 1.35 or 1
            local defenderHeight = (defender.crouching and crouchingHeight
                or standingHeight) * defenderScale
            local defenderOffset = defender.mount and riderOffset or 0
            local defenderBox = {
                x = defender.x - fighterWidth / 2,
                y = defender.y - defenderOffset - defenderHeight,
                width = fighterWidth,
                height = defenderHeight,
            }
            if overlaps(hitbox, defenderBox) then
                attack.hitOpponent = true
                local bondPower = attacker.mount and attacker.mount.bonded and 1.05 or 1
                local mushroomPower = attacker.mushroomTimer > 0 and 1.35 or 1
                defender:takeDamage(settings.damage * attacker.power
                    * bondPower * mushroomPower * attacker.comebackBoost,
                    settings.knockback, attacker)
                attacker.combo = attacker.combo + 1
                attacker.comboTimer = comboTimeout
                defender.combo = 0
                defender.comboTimer = 0
                defender.hitFlash = hitFlashDuration
                game.hitStopTimer = hitStopDuration
            end
        end
    end
end

local function updateSpecial(attacker, defender, dt)
    local special = attacker.special
    if not special then
        return
    end

    special.timer = special.timer - dt
    local progress = 1 - special.timer / special.duration
    local distance = math.abs(defender.x - attacker.x)
    local direction = defender.x >= attacker.x and 1 or -1
    local mushroomPower = attacker.mushroomTimer > 0 and 1.35 or 1

    if special.index == 1 then
        local reach = math.min(390, progress * 720)
        special.targetX = attacker.x + attacker.facing * reach
        if not special.hit and progress >= 0.32 and progress <= 0.82
            and direction == attacker.facing and distance <= 400 then
            special.hit = true
            special.targetX = defender.x
            defender:takeDamage(12 * attacker.power * mushroomPower
                * attacker.comebackBoost, 0, attacker)
            defender.x = math.max(fighterWidth / 2,
                math.min(levelWidth - fighterWidth / 2,
                    attacker.x + attacker.facing * 68))
            defender.velocityY = math.min(defender.velocityY, 0)
            defender.hitFlash = hitFlashDuration
            game.hitStopTimer = hitStopDuration * 0.7
        end
    elseif special.index == 2 then
        attacker.x = math.max(fighterWidth / 2,
            math.min(levelWidth - fighterWidth / 2,
                attacker.x + attacker.facing * 720 * dt))
        special.targetX = attacker.x + attacker.facing * 70
        if not special.hit and distance <= 92 then
            special.hit = true
            defender:takeDamage(27 * attacker.power * mushroomPower
                * attacker.comebackBoost, 64, attacker)
            defender.hitFlash = hitFlashDuration
            game.hitStopTimer = hitStopDuration
        end
    elseif special.index == 3 then
        special.targetX = attacker.x
        if not special.hit and progress >= 0.22 then
            special.hit = true
            if distance <= 155 then
                defender:takeDamage(22 * attacker.power * mushroomPower
                    * attacker.comebackBoost, 88, attacker)
                defender.hitFlash = hitFlashDuration
                game.hitStopTimer = hitStopDuration
            end
        end
    end

    if special.timer <= 0 then
        attacker.special = nil
        attacker.recovery = 0.22
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
    elseif fighter2.x > levelWidth - fighterWidth / 2 then
        fighter2.x = levelWidth - fighterWidth / 2
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

    if not fighter2.mount then
        toggleMount(fighter2)
    end

    cpu.decisionTimer = profile.reactionMin
        + love.math.random() * (profile.reactionMax - profile.reactionMin)
    local roll = love.math.random()

    if distance > 145 and distance <= 400 and fighter2.specialCooldowns[1] == 0
        and roll < 0.20 then
        fighter2:startSpecial(1)
    elseif distance <= 120 and fighter2.specialCooldowns[3] == 0
        and roll < 0.16 then
        fighter2:startSpecial(3)
    elseif distance <= 190 and fighter2.specialCooldowns[2] == 0
        and roll < 0.14 then
        fighter2:startSpecial(2)
    elseif distance <= 145 and roll < profile.blockChance
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
    if game.state == "character_select" then
        if key == "escape" then
            love.event.quit()
            return
        elseif isrepeat then
            return
        end

        if not selectionReady[1] then
            if key == "a" or (cpuEnabled and key == "left") then
                selectedCharacter[1] = (selectedCharacter[1] - 2) % #characters + 1
            elseif key == "d" or (cpuEnabled and key == "right") then
                selectedCharacter[1] = selectedCharacter[1] % #characters + 1
            elseif key == "j" or key == "return" or key == "space" then
                selectionReady[1] = true
                if cpuEnabled then
                    repeat
                        selectedCharacter[2] = love.math.random(1, #characters)
                    until selectedCharacter[2] ~= selectedCharacter[1]
                    selectionReady[2] = true
                    beginMatch()
                end
            end
        elseif key == "a" or key == "d"
            or (cpuEnabled and (key == "left" or key == "right")) then
            selectionReady[1] = false
        end

        if not cpuEnabled and not selectionReady[2] then
            if key == "left" then
                selectedCharacter[2] = (selectedCharacter[2] - 2) % #characters + 1
            elseif key == "right" then
                selectedCharacter[2] = selectedCharacter[2] % #characters + 1
            elseif key == "n" then
                selectionReady[2] = true
            end
        end
        if not cpuEnabled and selectionReady[1] and selectionReady[2] then
            beginMatch()
        end
        return
    end

    if key == "r" and not isrepeat then
        restartMatch()
        return
    elseif key == "c" and not isrepeat then
        openCharacterSelect()
        return
    elseif key == "escape" then
        love.event.quit()
        return
    end
    if isrepeat or game.state ~= "fighting" or game.hitStopTimer > 0 then
        return
    end

    if key == "e" then
        toggleMount(fighter1)
        return
    elseif key == "/" and not cpuEnabled then
        toggleMount(fighter2)
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
            elseif key == fighter.controls.special1 then
                fighter:startSpecial(1)
            elseif key == fighter.controls.special2 then
                fighter:startSpecial(2)
            elseif key == fighter.controls.special3 then
                fighter:startSpecial(3)
            end
        end
    end
end

function love.update(dt)
    menuPulse = menuPulse + dt
    updatePhoneControls(dt)
    if game.state == "character_select" then
        return
    end
    if game.state == "round_over" then
        fighter1.hitFlash = math.max(0, fighter1.hitFlash - dt)
        fighter2.hitFlash = math.max(0, fighter2.hitFlash - dt)
        game.transitionTimer = game.transitionTimer - dt
        if game.transitionTimer <= 0 then
            game.round = game.round + 1
            resetRound()
        end
        return
    elseif game.state ~= "fighting" then
        fighter1.hitFlash = math.max(0, fighter1.hitFlash - dt)
        fighter2.hitFlash = math.max(0, fighter2.hitFlash - dt)
        return
    end

    if game.hitStopTimer > 0 then
        game.hitStopTimer = math.max(0, game.hitStopTimer - dt)
        return
    end

    game.timeRemaining = math.max(0, game.timeRemaining - dt)
    updatePlatforms(dt)
    updateComebackBoosts()
    if cpuEnabled and game.state == "fighting" then
        updateCpu(dt)
    else
        fighter2.aiInput = nil
    end
    fighter1:update(dt)
    fighter2:update(dt)
    updatePowerUps(dt)
    updateFireballs(dt)
    updateHazards()
    separateFighters()

    if fighter2.x > fighter1.x then
        fighter1.facing = 1
        fighter2.facing = -1
    else
        fighter1.facing = -1
        fighter2.facing = 1
    end
    updateAnimals(dt)
    updateSpecial(fighter1, fighter2, dt)
    updateSpecial(fighter2, fighter1, dt)

    local fighterDistance = math.abs(fighter2.x - fighter1.x)
    local desiredZoom = math.max(0.55, math.min(1, 760 / (fighterDistance + 260)))
    cameraZoom = cameraZoom + (desiredZoom - cameraZoom) * math.min(1, dt * 3.5)
    local desiredCenter = (fighter1.x + fighter2.x) / 2
    local visibleHalf = arenaWidth / (2 * cameraZoom)
    desiredCenter = math.max(visibleHalf,
        math.min(levelWidth - visibleHalf, desiredCenter))
    cameraCenterX = cameraCenterX
        + (desiredCenter - cameraCenterX) * math.min(1, dt * 4.5)
    cameraX = cameraCenterX - visibleHalf

    updateAttack(fighter1, fighter2, dt)
    updateAttack(fighter2, fighter1, dt)
    separateFighters()

    fighter1:updateState()
    fighter2:updateState()

    if fighter1.x >= flagX - 24 or fighter2.x >= flagX - 24 then
        local winner = fighter1.x >= flagX - 24 and 1 or 2
        game.state = "game_won"
        game.result = "PLAYER " .. winner .. " CAPTURED THE FLAG!"
        fighter1.attack = nil
        fighter2.attack = nil
        fighter1.blocking = false
        fighter2.blocking = false
        return
    end

    if fighter1.ko then
        loseLife(fighter1, "KO")
    end
    if fighter2.ko and game.state == "fighting" then
        loseLife(fighter2, "KO")
    end
    if game.state ~= "fighting" then
        return
    end
    if game.timeRemaining <= 0 then
        game.state = "match_over"
        if fighter1.x > fighter2.x then
            game.result = "TIME — PLAYER 1 WINS THE RACE"
        elseif fighter2.x > fighter1.x then
            game.result = "TIME — PLAYER 2 WINS THE RACE"
        elseif game.lives[1] > game.lives[2] then
            game.result = "TIME — PLAYER 1 WINS ON LIVES"
        elseif game.lives[2] > game.lives[1] then
            game.result = "TIME — PLAYER 2 WINS ON LIVES"
        else
            game.result = "TIME — DRAW"
        end
    end
end

local function drawFighter(fighter)
    local scale = fighter.mushroomTimer > 0 and 1.35 or 1
    local bodyWidth = fighterWidth * scale
    local bodyHeight = (fighter.crouching and crouchingHeight or standingHeight) * scale
    local bodyBaseY = fighter.y - (fighter.mount and riderOffset or 0)
    local bodyTop = bodyBaseY - bodyHeight
    local bodyShift = 0
    if fighter.attack then
        bodyShift = fighter.facing * (fighter.attack.phase == "active" and 4 or -2)
    elseif fighter.special and fighter.special.index == 2 then
        bodyShift = fighter.facing * 10
    elseif fighter.recovery > 0 then
        bodyShift = -fighter.facing * 2
    end

    if fighter.mushroomTimer > 0 then
        local pulse = 0.20 + 0.08 * math.sin(menuPulse * 8)
        love.graphics.setColor(1, 0.28, 0.18, pulse)
        love.graphics.circle("fill", fighter.x, bodyTop + bodyHeight / 2,
            46 * scale)
        love.graphics.setColor(1, 0.84, 0.28, 0.9)
        love.graphics.rectangle("line", fighter.x - bodyWidth / 2 - 5,
            bodyTop - 20 * scale, bodyWidth + 10, bodyHeight + 25 * scale)
    end
    if fighter.shieldHealth > 0 then
        love.graphics.setColor(0.24, 0.68, 1, 0.22)
        love.graphics.circle("fill", fighter.x, bodyTop + bodyHeight / 2,
            54 * scale)
        love.graphics.setColor(0.52, 0.86, 1, 0.9)
        love.graphics.circle("line", fighter.x, bodyTop + bodyHeight / 2,
            54 * scale)
    end

    if fighter.invulnerableTimer > 0
        and math.floor(fighter.invulnerableTimer * 12) % 2 == 0 then
        love.graphics.setColor(fighter.color[1], fighter.color[2], fighter.color[3], 0.28)
    elseif fighter.hitFlash > 0 then
        love.graphics.setColor(1, 1, 1)
    else
        love.graphics.setColor(fighter.color[1], fighter.color[2], fighter.color[3])
    end
    love.graphics.rectangle("fill", fighter.x - bodyWidth / 2 + bodyShift, bodyTop,
        bodyWidth, bodyHeight)
    love.graphics.circle("fill", fighter.x + bodyShift,
        bodyTop - 11 * scale, 12 * scale)

    if fighter.attack then
        local reach = fighter.attack.phase == "active" and 24 or 10
        local limbX = fighter.facing > 0
            and fighter.x + bodyWidth / 2 - 2
            or fighter.x - bodyWidth / 2 - reach * scale + 2
        love.graphics.rectangle("fill",
            limbX,
            bodyBaseY - (fighter.attack.kind == "kick" and 24 or 48),
            reach * scale, 8 * scale)
    end

    if fighter.blocking then
        love.graphics.setColor(0.55, 0.88, 1, 0.8)
        love.graphics.rectangle("line", fighter.x - bodyWidth / 2 - 5,
            bodyTop - 5, bodyWidth + 10, bodyHeight + 10)
    end

    if fighter.attack and fighter.attack.phase == "active" then
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

local function drawSpecialEffect(fighter)
    local special = fighter.special
    if not special then
        return
    end
    local progress = 1 - special.timer / special.duration
    local accent = fighter.character and fighter.character.accent or fighter.color

    if special.index == 1 then
        local handX = fighter.x + fighter.facing * 18
        local handY = fighter.y - (fighter.mount and riderOffset or 0) - 48
        local tipX = special.targetX
        love.graphics.setLineWidth(4)
        love.graphics.setColor(0.72, 0.74, 0.80)
        love.graphics.line(handX, handY, tipX, handY + 4)
        local links = math.max(1, math.floor(math.abs(tipX - handX) / 18))
        for i = 1, links do
            local x = handX + (tipX - handX) * i / links
            love.graphics.setColor(i % 2 == 0 and { 0.95, 0.76, 0.30 }
                or { 0.64, 0.66, 0.72 })
            love.graphics.circle("line", x, handY + 4, 6)
        end
        love.graphics.setColor(0.92, 0.24, 0.18)
        love.graphics.polygon("fill", tipX, handY + 4,
            tipX - fighter.facing * 18, handY - 8,
            tipX - fighter.facing * 18, handY + 16)
        love.graphics.setLineWidth(1)
    elseif special.index == 2 then
        for i = 1, 4 do
            love.graphics.setColor(accent[1], accent[2], accent[3], 0.32 / i)
            love.graphics.rectangle("fill",
                fighter.x - fighter.facing * i * 22 - 18,
                fighter.y - 72, 36, 70, 8, 8)
        end
    else
        local radius = 35 + math.sin(math.min(1, progress) * math.pi) * 130
        love.graphics.setColor(accent[1], accent[2], accent[3], 0.18)
        love.graphics.circle("fill", fighter.x, fighter.y - 42, radius)
        love.graphics.setColor(accent[1], accent[2], accent[3], 0.86)
        love.graphics.setLineWidth(5)
        love.graphics.circle("line", fighter.x, fighter.y - 42, radius)
        love.graphics.setLineWidth(1)
    end
end

local function drawAnimal(animal)
    local x = animal.x
    local y = animal.y + math.sin(animal.bob) * (animal.rider and 2.5 or 1)
    local facing = animal.facing or 1
    love.graphics.setColor(animal.color)
    if animal.kind == "HORSE" then
        love.graphics.ellipse("fill", x, y - 25, 43, 21)
        love.graphics.rectangle("fill", x + facing * 25 - 7, y - 58, 14, 38)
        love.graphics.ellipse("fill", x + facing * 32, y - 60, 18, 13)
        love.graphics.rectangle("fill", x - 28, y - 24, 8, 24)
        love.graphics.rectangle("fill", x + 20, y - 24, 8, 24)
        love.graphics.setColor(animal.mane)
        love.graphics.rectangle("fill", x + facing * 19 - 4, y - 58, 8, 31)
        love.graphics.polygon("fill", x - facing * 42, y - 34,
            x - facing * 58, y - 45, x - facing * 45, y - 25)
    else
        love.graphics.ellipse("fill", x, y - 20, 42, 20)
        love.graphics.ellipse("fill", x + facing * 34, y - 24, 20, 15)
        love.graphics.rectangle("fill", x - 25, y - 19, 8, 19)
        love.graphics.rectangle("fill", x + 18, y - 19, 8, 19)
        love.graphics.setColor(0.92, 0.84, 0.62)
        love.graphics.polygon("fill", x + facing * 47, y - 24,
            x + facing * 58, y - 30, x + facing * 49, y - 18)
        love.graphics.setColor(animal.mane)
        love.graphics.polygon("fill", x - 22, y - 39, x + 15, y - 41, x, y - 31)
    end

    if not animal.rider then
        love.graphics.setColor(0.95, 0.88, 0.38)
        love.graphics.printf(animal.kind, x - 48, y - 88, 96, "center")
        love.graphics.setColor(0.68, 0.74, 0.84)
        love.graphics.printf(animal.mood, x - 55, y - 74, 110, "center")
        if math.abs(fighter1.x - animal.x) <= mountDistance then
            love.graphics.setColor(1, 0.92, 0.42)
            love.graphics.printf("E  RIDE", x - 55, y - 105, 110, "center")
        elseif not cpuEnabled and math.abs(fighter2.x - animal.x) <= mountDistance then
            love.graphics.setColor(1, 0.92, 0.42)
            love.graphics.printf("/  RIDE", x - 55, y - 105, 110, "center")
        end
    elseif animal.bondTimer > 0 then
        local riderColor = animal.rider.character.accent
        love.graphics.setColor(riderColor[1], riderColor[2], riderColor[3],
            math.min(1, animal.bondTimer))
        love.graphics.printf(animal.bonded and "★ PERFECT BOND ★" or "MOUNTED",
            x - 90, y - 146, 180, "center")
        if animal.bonded then
            for i = 1, 3 do
                local angle = menuPulse * 2.4 + i * 2.1
                love.graphics.circle("fill", x + math.cos(angle) * 50,
                    y - 75 + math.sin(angle) * 18, 3)
            end
        end
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
    local playerNumber = fighter == fighter1 and 1 or 2
    local livesText = string.rep("♥", game.lives[playerNumber])
    if alignRight then
        love.graphics.printf(label .. " HP " .. fighter.health,
            barX - 132, 63, 124, "right")
        love.graphics.printf(livesText, barX, 44, barWidth, "right")
        love.graphics.printf("State: " .. fighter.state, barX - 132, 86, 304, "right")
    else
        love.graphics.print(label .. " HP " .. fighter.health, barX + barWidth + 8, 63)
        love.graphics.print(livesText, barX, 44)
        love.graphics.print("State: " .. fighter.state, barX, 86)
    end

    local attackStatus = "READY"
    if fighter.attack then
        attackStatus = string.upper(fighter.attack.kind) .. " "
            .. string.upper(fighter.attack.phase)
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

local function drawSpecialHud(fighter, x, alignRight, keys)
    local totalWidth = 204
    local startX = alignRight and x - totalWidth or x
    for i, move in ipairs(specialMoves) do
        local boxX = startX + (i - 1) * 70
        local ready = fighter.specialCooldowns[i] <= 0
        love.graphics.setColor(ready and { 0.16, 0.28, 0.24, 0.94 }
            or { 0.11, 0.12, 0.17, 0.90 })
        love.graphics.rectangle("fill", boxX, 126, 64, 28, 5, 5)
        love.graphics.setColor(ready and { 0.40, 1.00, 0.64 }
            or { 0.42, 0.44, 0.52 })
        love.graphics.rectangle("line", boxX, 126, 64, 28, 5, 5)
        love.graphics.printf(keys[i] .. "  " .. (ready and "READY"
            or string.format("%.1f", fighter.specialCooldowns[i])),
            boxX, 132, 64, "center")
    end
end

local function drawStat(label, value, maximum, x, y, width, color)
    love.graphics.setFont(uiFont)
    love.graphics.setColor(0.72, 0.76, 0.86)
    love.graphics.print(label, x, y)
    love.graphics.setColor(0.12, 0.14, 0.22)
    love.graphics.rectangle("fill", x + 48, y + 3, width, 7, 4, 4)
    love.graphics.setColor(color)
    love.graphics.rectangle("fill", x + 48, y + 3,
        width * math.min(1, value / maximum), 7, 4, 4)
end

local function drawCharacterPortrait(character, x, y, scale, selected)
    if selected then
        local glow = 0.16 + 0.08 * math.sin(menuPulse * 4)
        love.graphics.setColor(character.accent[1], character.accent[2],
            character.accent[3], glow)
        love.graphics.circle("fill", x, y, 70 * scale)
    end

    love.graphics.setColor(0.06, 0.07, 0.12)
    love.graphics.polygon("fill",
        x - 42 * scale, y + 58 * scale,
        x - 30 * scale, y - 5 * scale,
        x + 30 * scale, y - 5 * scale,
        x + 42 * scale, y + 58 * scale)
    love.graphics.setColor(character.color)
    love.graphics.rectangle("fill", x - 25 * scale, y - 2 * scale,
        50 * scale, 62 * scale, 10 * scale, 10 * scale)
    love.graphics.circle("fill", x, y - 28 * scale, 27 * scale)
    love.graphics.setColor(character.accent)
    love.graphics.polygon("fill",
        x - 28 * scale, y - 34 * scale,
        x, y - 60 * scale,
        x + 28 * scale, y - 34 * scale,
        x + 17 * scale, y - 42 * scale,
        x - 18 * scale, y - 42 * scale)
    love.graphics.rectangle("fill", x - 30 * scale, y + 15 * scale,
        60 * scale, 9 * scale, 4 * scale, 4 * scale)
    love.graphics.setColor(1, 0.96, 0.78)
    love.graphics.rectangle("fill", x - 16 * scale, y - 31 * scale,
        10 * scale, 4 * scale, 2 * scale, 2 * scale)
    love.graphics.rectangle("fill", x + 6 * scale, y - 31 * scale,
        10 * scale, 4 * scale, 2 * scale, 2 * scale)
end

local function drawCharacterSelect()
    love.graphics.clear(0.025, 0.03, 0.07)
    for y = 0, 540, 18 do
        local blend = y / 540
        love.graphics.setColor(0.04 + blend * 0.06, 0.05 + blend * 0.03,
            0.12 + blend * 0.08, 1)
        love.graphics.rectangle("fill", 0, y, arenaWidth, 18)
    end
    for i = 1, 22 do
        local x = (i * 137) % arenaWidth
        local y = 82 + (i * 71) % 360
        local alpha = 0.12 + 0.08 * math.sin(menuPulse * 1.6 + i)
        love.graphics.setColor(0.55, 0.72, 1, alpha)
        love.graphics.circle("fill", x, y, i % 3 + 1)
    end

    love.graphics.setFont(titleFont)
    love.graphics.setColor(0.12, 0.42, 0.72, 0.28)
    love.graphics.printf("CHOOSE YOUR FIGHTER", 3, 25, arenaWidth, "center")
    love.graphics.setColor(0.94, 0.96, 1)
    love.graphics.printf("CHOOSE YOUR FIGHTER", 0, 22, arenaWidth, "center")
    love.graphics.setFont(uiFont)
    love.graphics.setColor(0.48, 0.78, 1)
    love.graphics.printf("SHADOW FIGHTERS  //  RIDE. STRIKE. SURVIVE.",
        0, 75, arenaWidth, "center")

    local cardWidth = 202
    local cardGap = 18
    local startX = 49
    for i, character in ipairs(characters) do
        local x = startX + (i - 1) * (cardWidth + cardGap)
        local selected = selectedCharacter[1] == i
            or (not cpuEnabled and selectedCharacter[2] == i)
        local y = selected and 108 or 116
        local cardHeight = selected and 334 or 318

        love.graphics.setColor(0, 0, 0, 0.35)
        love.graphics.rectangle("fill", x + 5, y + 7, cardWidth, cardHeight, 12, 12)
        love.graphics.setColor(0.075, 0.085, 0.15, 0.96)
        love.graphics.rectangle("fill", x, y, cardWidth, cardHeight, 12, 12)
        love.graphics.setColor(character.color[1], character.color[2],
            character.color[3], selected and 0.95 or 0.42)
        love.graphics.rectangle("line", x, y, cardWidth, cardHeight, 12, 12)
        love.graphics.rectangle("fill", x, y, cardWidth, 5, 12, 12)

        drawCharacterPortrait(character, x + cardWidth / 2, y + 100,
            selected and 0.90 or 0.82, selected)
        love.graphics.setFont(characterFont)
        love.graphics.setColor(character.accent)
        love.graphics.printf(character.name, x, y + 178, cardWidth, "center")
        love.graphics.setFont(uiFont)
        love.graphics.setColor(0.64, 0.68, 0.78)
        love.graphics.printf(character.title, x, y + 207, cardWidth, "center")
        love.graphics.setColor(0.82, 0.84, 0.90)
        love.graphics.printf(character.description, x + 16, y + 229,
            cardWidth - 32, "center")
        love.graphics.setColor(character.accent)
        love.graphics.printf("BONDS WITH " .. character.affinity,
            x + 16, y + 257, cardWidth - 32, "center")
        drawStat("HP", character.health, 120, x + 18, y + 278, 112, character.color)
        drawStat("SPD", character.speed, 325, x + 18, y + 296, 112, character.color)
        drawStat("PWR", character.power, 1.12, x + 18, y + 314, 112, character.color)

        if selected then
            love.graphics.setColor(character.accent)
            love.graphics.polygon("fill", x + cardWidth / 2 - 9, y - 10,
                x + cardWidth / 2 + 9, y - 10, x + cardWidth / 2, y - 1)
        end
    end

    local current = characters[selectedCharacter[1]]
    love.graphics.setColor(0.04, 0.05, 0.09, 0.92)
    love.graphics.rectangle("fill", 0, 464, arenaWidth, 76)
    love.graphics.setColor(current.color)
    love.graphics.rectangle("fill", 0, 464, arenaWidth, 2)
    love.graphics.setFont(characterFont)
    love.graphics.setColor(current.accent)
    love.graphics.print("P1  " .. current.name, 42, 478)
    love.graphics.setFont(uiFont)
    love.graphics.setColor(0.82, 0.86, 0.94)
    love.graphics.print("A / D  SELECT", 285, 482)
    love.graphics.print("J / ENTER  CONFIRM", 410, 482)
    love.graphics.setColor(0.48, 0.54, 0.66)
    love.graphics.print(cpuEnabled and "OPPONENT: CPU RANDOM"
        or "P2: ARROWS + N TO CONFIRM", 650, 482)
    love.graphics.setColor(phoneConnected[1] and { 0.38, 1.00, 0.62 }
        or { 0.48, 0.52, 0.62 })
    love.graphics.print("P1 PHONE: " .. (phoneConnected[1] and "CONNECTED" or "WAITING"),
        42, 503)
    love.graphics.setColor(phoneConnected[2] and { 0.38, 1.00, 0.62 }
        or { 0.48, 0.52, 0.62 })
    love.graphics.printf("P2 PHONE: " .. (phoneConnected[2] and "CONNECTED" or "WAITING")
        .. (selectionReady[2] and "  •  READY" or ""), 650, 503, 268, "right")
    love.graphics.setColor(0.55, 0.60, 0.72)
    love.graphics.printf("C returns here during a match  •  ESC quits",
        0, 523, arenaWidth, "center")
end

local function drawScrollingBackground()
    love.graphics.clear(0.08, 0.13, 0.26)
    for y = 0, floorY, 20 do
        local t = y / floorY
        love.graphics.setColor(0.08 + t * 0.16, 0.14 + t * 0.12,
            0.30 + t * 0.14)
        love.graphics.rectangle("fill", 0, y, arenaWidth, 20)
    end

    love.graphics.setColor(1, 0.72, 0.28, 0.18)
    love.graphics.circle("fill", 760 - cameraX * 0.04, 130, 72)
    for i = 0, 10 do
        local cloudX = i * 390 - cameraX * 0.16
        love.graphics.setColor(0.82, 0.88, 1, 0.24)
        love.graphics.ellipse("fill", cloudX, 112 + (i % 3) * 36, 72, 18)
        love.graphics.circle("fill", cloudX - 28, 105 + (i % 3) * 36, 22)
        love.graphics.circle("fill", cloudX + 20, 101 + (i % 3) * 36, 28)
    end

    for i = 0, 8 do
        local hillX = i * 520 - cameraX * 0.32
        love.graphics.setColor(0.12, 0.24, 0.30)
        love.graphics.polygon("fill", hillX - 220, floorY,
            hillX, 215 + (i % 2) * 45, hillX + 230, floorY)
        love.graphics.setColor(0.16, 0.34, 0.32)
        love.graphics.polygon("fill", hillX - 130, floorY,
            hillX + 60, 285 + (i % 3) * 18, hillX + 260, floorY)
    end
end

local function drawFlag()
    love.graphics.setColor(0.88, 0.90, 0.96)
    love.graphics.rectangle("fill", flagX, floorY - 205, 8, 205)
    love.graphics.setColor(1, 0.78, 0.18)
    love.graphics.circle("fill", flagX + 4, floorY - 212, 11)
    love.graphics.setColor(0.92, 0.18, 0.24)
    love.graphics.polygon("fill", flagX + 8, floorY - 195,
        flagX + 92, floorY - 168, flagX + 8, floorY - 138)
    love.graphics.setColor(1, 0.88, 0.34)
    love.graphics.printf("GOAL", flagX + 10, floorY - 186, 72, "center")
end

local function drawWorldScenery()
    love.graphics.setColor(0.20, 0.19, 0.25)
    love.graphics.rectangle("fill", 0, floorY, levelWidth, 80)
    love.graphics.setColor(0.45, 0.34, 0.22)
    love.graphics.rectangle("fill", 0, floorY, levelWidth, 8)
    for x = 0, levelWidth, 64 do
        love.graphics.setColor((x / 64) % 2 == 0 and { 0.25, 0.23, 0.30 }
            or { 0.30, 0.27, 0.34 })
        love.graphics.rectangle("fill", x, floorY + 8, 64, 34)
    end

    for _, pit in ipairs(pits) do
        love.graphics.setColor(0.015, 0.02, 0.04)
        love.graphics.rectangle("fill", pit.left, floorY - 2,
            pit.right - pit.left, 100)
        love.graphics.setColor(0.72, 0.18, 0.10, 0.45)
        for x = pit.left + 12, pit.right - 12, 24 do
            love.graphics.polygon("fill", x - 8, floorY + 70,
                x, floorY + 42, x + 8, floorY + 70)
        end
    end

    for _, platform in ipairs(platforms) do
        love.graphics.setColor(platform.moving and { 0.24, 0.70, 0.84 }
            or { 0.52, 0.42, 0.62 })
        love.graphics.rectangle("fill", platform.x, platform.y,
            platform.width, platform.height, 6, 6)
        love.graphics.setColor(0.82, 0.88, 1, 0.75)
        love.graphics.rectangle("line", platform.x + 2, platform.y + 2,
            platform.width - 4, platform.height - 4, 5, 5)
    end

    for _, spike in ipairs(spikes) do
        love.graphics.setColor(0.78, 0.82, 0.90)
        for x = spike.x, spike.x + spike.width - 16, 16 do
            love.graphics.polygon("fill", x, floorY,
                x + 8, floorY - 28, x + 16, floorY)
        end
    end

    for _, block in ipairs(levelBlocks) do
        local bumpOffset = block.bump > 0 and -8 * math.sin(block.bump / 0.22 * math.pi) or 0
        local y = block.y + bumpOffset
        love.graphics.setColor(block.hit and { 0.34, 0.30, 0.28 }
            or { 0.90, 0.54, 0.16 })
        love.graphics.rectangle("fill", block.x, y, 46, 46, 5, 5)
        love.graphics.setColor(block.hit and { 0.48, 0.44, 0.40 }
            or { 1, 0.78, 0.28 })
        love.graphics.rectangle("line", block.x + 3, y + 3, 40, 40, 4, 4)
        love.graphics.setFont(characterFont)
        love.graphics.printf(block.hit and "·" or "?", block.x, y + 8, 46, "center")
    end

    for _, mushroom in ipairs(mushrooms) do
        if not mushroom.collected then
            local colors = {
                MUSHROOM = { 0.96, 0.18, 0.18 }, SHIELD = { 0.24, 0.64, 1.00 },
                FIRE = { 1.00, 0.42, 0.08 }, BOOTS = { 0.38, 1.00, 0.52 },
                BOND = { 0.94, 0.42, 0.88 }, LIGHTNING = { 1.00, 0.90, 0.18 },
            }
            local labels = {
                MUSHROOM = "M", SHIELD = "S", FIRE = "F",
                BOOTS = "B", BOND = "♥", LIGHTNING = "⚡",
            }
            love.graphics.setColor(colors[mushroom.kind] or colors.MUSHROOM)
            love.graphics.circle("fill", mushroom.x, mushroom.y, 19)
            love.graphics.setColor(1, 0.96, 0.88)
            love.graphics.circle("line", mushroom.x, mushroom.y, 16)
            love.graphics.setFont(uiFont)
            love.graphics.printf(labels[mushroom.kind] or "?",
                mushroom.x - 18, mushroom.y - 7, 36, "center")
        end
    end

    for _, fireball in ipairs(fireballs) do
        if fireball.active then
            love.graphics.setColor(1, 0.28, 0.08, 0.28)
            love.graphics.circle("fill", fireball.x, fireball.y, 21)
            love.graphics.setColor(1, 0.78, 0.20)
            love.graphics.circle("fill", fireball.x, fireball.y, 11)
        end
    end

    for i = 1, 9 do
        local x = 380 + i * 330
        love.graphics.setColor(0.18, 0.12, 0.10)
        love.graphics.rectangle("fill", x - 8, floorY - 72, 16, 72)
        love.graphics.setColor(0.12, 0.42, 0.26)
        love.graphics.circle("fill", x, floorY - 88, 38)
        love.graphics.circle("fill", x - 25, floorY - 72, 28)
        love.graphics.circle("fill", x + 25, floorY - 72, 28)
    end
    drawFlag()
end

local function powerStatus(fighter)
    local status = {}
    if fighter.mushroomTimer > 0 then table.insert(status, "GIANT") end
    if fighter.shieldHealth > 0 then table.insert(status, "SHIELD " .. fighter.shieldHealth) end
    if fighter.fireTimer > 0 then table.insert(status, "FIRE") end
    if fighter.bootsTimer > 0 then table.insert(status, "SPEED") end
    if fighter.bondCharmTimer > 0 then table.insert(status, "BOND") end
    if fighter.comebackBoost > 1 then table.insert(status, "COMEBACK") end
    return table.concat(status, "  •  ")
end

function love.draw()
    if game.state == "character_select" then
        drawCharacterSelect()
        return
    end
    love.graphics.setFont(uiFont)
    drawScrollingBackground()
    love.graphics.push()
    love.graphics.translate(arenaWidth / 2, floorY)
    love.graphics.scale(cameraZoom, cameraZoom)
    love.graphics.translate(-cameraCenterX, -floorY)
    drawWorldScenery()
    for _, animal in ipairs(animals) do
        drawAnimal(animal)
    end
    drawFighter(fighter1)
    drawFighter(fighter2)
    drawSpecialEffect(fighter1)
    drawSpecialEffect(fighter2)
    love.graphics.pop()
    drawHealthBar(fighter1, 12, false, "F1")
    drawHealthBar(fighter2, arenaWidth - 12, true, "F2")
    drawSpecialHud(fighter1, 12, false, { "U", "I", "O" })
    drawSpecialHud(fighter2, arenaWidth - 12, true, { "1", "2", "3" })

    love.graphics.setColor(0.92, 0.94, 1)
    love.graphics.setFont(timerFont)
    love.graphics.printf(string.format("%02d", math.ceil(game.timeRemaining)),
        0, 0, arenaWidth, "center")
    love.graphics.setFont(uiFont)
    love.graphics.printf("3-LIFE FLAG RACE", 0, 34, arenaWidth, "center")

    if fighter1.combo > 0 then
        love.graphics.setColor(1, 0.86, 0.35)
        love.graphics.print(fighter1.combo .. " HIT COMBO", 12, 164)
    end
    if fighter2.combo > 0 then
        love.graphics.setColor(1, 0.86, 0.35)
        love.graphics.printf(fighter2.combo .. " HIT COMBO", arenaWidth - 192,
            164, 180, "right")
    end

    if game.state == "round_over" or game.state == "match_over"
        or game.state == "game_won" then
        love.graphics.setColor(1, 0.82, 0.25)
        love.graphics.setFont(resultFont)
        love.graphics.printf(game.result, 0, 190, arenaWidth, "center")
        love.graphics.setFont(uiFont)
        if game.state == "round_over" then
            love.graphics.setColor(0.92, 0.94, 1)
            love.graphics.printf("NEXT ROUND IN " .. math.ceil(game.transitionTimer),
                0, 245, arenaWidth, "center")
        elseif game.state == "match_over" then
            love.graphics.setColor(0.92, 0.94, 1)
            love.graphics.printf("PRESS R TO RESTART", 0, 245, arenaWidth, "center")
        else
            love.graphics.setColor(0.92, 0.94, 1)
            love.graphics.printf("THE SHADOW ROAD IS CONQUERED!  •  R RESTART  •  C CHARACTERS",
                0, 245, arenaWidth, "center")
        end
    end

    love.graphics.setFont(uiFont)
    love.graphics.setColor(0.92, 0.94, 1)
    love.graphics.print("FPS: " .. love.timer.getFPS(), 12, 12)
    local progressWidth = 230
    local progress = math.min(1, fighter1.x / flagX)
    local progress2 = math.min(1, fighter2.x / flagX)
    love.graphics.setColor(0.08, 0.09, 0.14, 0.88)
    love.graphics.rectangle("fill", arenaWidth / 2 - progressWidth / 2,
        52, progressWidth, 10, 5, 5)
    love.graphics.setColor(1, 0.72, 0.20)
    love.graphics.rectangle("fill", arenaWidth / 2 - progressWidth / 2,
        52, progressWidth * progress, 10, 5, 5)
    love.graphics.setColor(0.30, 0.72, 1.00)
    love.graphics.rectangle("fill", arenaWidth / 2 - progressWidth / 2,
        59, progressWidth * progress2, 3, 2, 2)
    love.graphics.setColor(0.94, 0.96, 1)
    love.graphics.printf("P1 " .. math.floor(progress * 100) .. "%  •  P2 "
        .. math.floor(progress2 * 100) .. "%",
        arenaWidth / 2 - 70, 65, 140, "center")
    love.graphics.printf("F1: E TO MOUNT / DISMOUNT"
        .. (cpuEnabled and "" or "     F2: / TO MOUNT / DISMOUNT"),
        0, 516, arenaWidth, "center")
    if fighter1.mount then
        love.graphics.setColor(fighter1.mount.bonded and { 1, 0.86, 0.28 }
            or { 0.80, 0.84, 0.92 })
        love.graphics.print(fighter1.mount.kind
            .. (fighter1.mount.bonded and "  PERFECT BOND" or "  MOUNTED"), 12, 180)
    end
    if fighter1.mushroomTimer > 0 then
        love.graphics.setColor(1, 0.36, 0.20)
        love.graphics.print("SUPER SIZE  "
            .. string.format("%.1fs", fighter1.mushroomTimer), 12, 198)
    end
    if fighter2.mount then
        love.graphics.setColor(fighter2.mount.bonded and { 1, 0.86, 0.28 }
            or { 0.80, 0.84, 0.92 })
        love.graphics.printf(fighter2.mount.kind
            .. (fighter2.mount.bonded and "  PERFECT BOND" or "  MOUNTED"),
            arenaWidth - 212, 180, 200, "right")
    end
    if fighter2.mushroomTimer > 0 then
        love.graphics.setColor(1, 0.36, 0.20)
        love.graphics.printf("SUPER SIZE  "
            .. string.format("%.1fs", fighter2.mushroomTimer),
            arenaWidth - 212, 198, 200, "right")
    end
    love.graphics.setColor(1, 0.82, 0.30)
    love.graphics.print(powerStatus(fighter1), 12, 216)
    love.graphics.setColor(0.46, 0.82, 1)
    love.graphics.printf(powerStatus(fighter2), arenaWidth - 312, 216, 300, "right")
end
