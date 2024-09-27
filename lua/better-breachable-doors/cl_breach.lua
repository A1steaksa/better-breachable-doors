local doorsToAnimate = {}
local previousDoorHealths = {}

local handleDamageAnimationDuration = 0.75
local handleBreachAnimationDuration = 2
local handleRespawnAnimationDuration = 1

local doorDamageAnimationDuration = 2
local doorBreachAnimationDuration = 0.5
local doorRespawnAnimationDuration = 0.5

local ANGLE_ZERO = Angle( 0, 0, 0 )

local ease_outElastic = math.ease.OutElastic
local lerpAngle = LerpAngle
local lerpVector = LerpVector
local math_min = math.min
local pi = math.pi

local conVarEnabled         = GetConVar( "doorbreach_enabled" )
local conVarHealth          = GetConVar( "doorbreach_health" )
local conVarUnlock          = GetConVar( "doorbreach_unlock" )
local conVarOpen            = GetConVar( "doorbreach_open" )
local conVarOpenSpeed       = GetConVar( "doorbreach_speed" )
local conVarRespawnTime     = GetConVar( "doorbreach_respawntime" )

local breachedHandleAngle   = Angle( 10, 79, 15 )
local breachedPushbarAngle  = Angle( -1, 9, 15 )
local breachedDoorAngle     = Angle( 1.5, 0, -1.5 )
local damagedDoorAngle      = Angle( 0, 1, 0 )

-- Animate a door's broken handle and pushbar in response to being breached
---@param door Entity
---@param animationProgress number
local function AnimateBreachingHandle( door, animationProgress )
    animationProgress = math_min( animationProgress, 1 )

    local handleAngle = breachedHandleAngle
    local pushbarAngle = breachedPushbarAngle
    if animationProgress < 1 then
        handleAngle = lerpAngle( ease_outElastic( animationProgress ), ANGLE_ZERO, breachedHandleAngle )
        pushbarAngle = lerpAngle( ease_outElastic( animationProgress ), ANGLE_ZERO, breachedPushbarAngle )
    end

    local handleBone = door:LookupBone( "handle" )
    if handleBone then
        door:ManipulateBoneAngles( handleBone, handleAngle )
    end
    local pushbarBone = door:LookupBone( "handle02" )
    if pushbarBone then
        door:ManipulateBoneAngles( pushbarBone, pushbarAngle )
    end
end

-- Animate a door's handle and pushbar in response to being respawned
---@param door Entity
---@param animationProgress number
local function AnimateRespawningHandle( door, animationProgress )
    animationProgress = math_min( animationProgress, 1 )

    local handleAngle = ANGLE_ZERO
    local pushbarAngle = ANGLE_ZERO

    if animationProgress < 1 then
        handleAngle = lerpAngle( ease_outElastic( animationProgress ), breachedHandleAngle, ANGLE_ZERO )
        pushbarAngle = lerpAngle( ease_outElastic( animationProgress ), breachedPushbarAngle, ANGLE_ZERO )
    end

    local handleBone = door:LookupBone( "handle" )
    if handleBone then
        door:ManipulateBoneAngles( handleBone, handleAngle )
    end
    local pushbarBone = door:LookupBone( "handle02" )
    if pushbarBone then
        door:ManipulateBoneAngles( pushbarBone, pushbarAngle )
    end
end

-- Animate a door's reaction to damage
---@param door Entity
---@param animationProgress number
local function AnimateDamagingDoor( door, animationProgress )
    animationProgress = math_min( animationProgress, 1 )

    animationProgress = math.abs( animationProgress - 1 / 2 )

    print( animationProgress )

    door:SetRenderAngles( nil )

    if animationProgress < 1 then
        local doorAngleOffset = lerpAngle( math.ease.OutElastic( animationProgress ), ANGLE_ZERO, damagedDoorAngle )
        door:SetRenderAngles( door:GetAngles() + doorAngleOffset )
    end
end

-- Animate a door's reaction to being breached
---@param door Entity
---@param animationProgress number
local function AnimateBreachingDoor( door, animationProgress )
    animationProgress = math_min( animationProgress, 1 )

    local doorAngleOffset = breachedDoorAngle

    if animationProgress < 1 then
        doorAngleOffset = lerpAngle( ease_outElastic( animationProgress ), ANGLE_ZERO, breachedDoorAngle )
    end

    door:SetRenderAngles( nil )
    door:SetRenderAngles( door:GetAngles() + doorAngleOffset )
end

-- Animate a breached door's reaction to being respawned
---@param door Entity
---@param animationProgress number
local function AnimateRespawningDoor( door, animationProgress )
    animationProgress = math_min( animationProgress, 1 )

    door:SetRenderAngles( nil )

    if animationProgress < 1 then
        local doorAngleOffset = lerpAngle( ease_outElastic( animationProgress ), breachedDoorAngle, ANGLE_ZERO )
        door:SetRenderAngles( door:GetAngles() + doorAngleOffset )
    end
end

-- Fully updates the door's animation(s) based on its current state.
---@param door Entity The door to animate
---@param time number The current time
local function UpdateAnimationState( door, time )
    local isStillAnimating = false

    local health = door:GetHealthAfterLastDamage()
    local healthDelta = health - ( previousDoorHealths[door] or 0 )
    local damageTime = door:GetDamageTime()
    local timeSinceDamage = time - damageTime

    local doorTookDamage = healthDelta < 0
    if doorTookDamage then
        -- Door damage animation
        local doorDamageAnimationProgress = timeSinceDamage / doorDamageAnimationDuration
        AnimateDamagingDoor( door, doorDamageAnimationProgress )
        isStillAnimating = isStillAnimating or ( doorDamageAnimationProgress < 1 )

        -- Door breaching animations
        local isDoorBreached = health <= 0
        if isDoorBreached then
            -- Door handle breach animation
            local handleAnimationProgress = timeSinceDamage / handleBreachAnimationDuration
            AnimateBreachingHandle( door, handleAnimationProgress )
            isStillAnimating = isStillAnimating or ( handleAnimationProgress < 1 )

            -- Door breach animation
            local doorBreachAnimationProgress = timeSinceDamage / doorBreachAnimationDuration
            AnimateBreachingDoor( door, doorBreachAnimationProgress )
            isStillAnimating = isStillAnimating or ( doorBreachAnimationProgress < 1 )

        end
    else
        local respawnTime = damageTime + conVarRespawnTime:GetFloat()
        local timeSinceRespawn = time - respawnTime

        -- Door handle respawn animation
        local handleRespawnAnimationProgress = timeSinceRespawn / handleRespawnAnimationDuration
        AnimateRespawningHandle( door, handleRespawnAnimationProgress )
        isStillAnimating = isStillAnimating or ( handleRespawnAnimationProgress < 1 )

        -- Door respawn animation
        local doorRespawnAnimationProgress = timeSinceRespawn / doorRespawnAnimationDuration
        AnimateRespawningDoor( door, doorRespawnAnimationProgress )
        isStillAnimating = isStillAnimating or ( doorRespawnAnimationProgress < 1 )
    end

    -- If we had nothing to animate on this door, it is done animating
    if not isStillAnimating then doorsToAnimate[door] = nil end
end

hook.Remove( "Think", BBD_HOOK_ANIMATE_DOORS )
hook.Add( "Think", BBD_HOOK_ANIMATE_DOORS, function()
    local time = CurTime()

    for door, _ in pairs( doorsToAnimate ) do
        UpdateAnimationState( door, time )
    end
end )

hook.Remove( "NotifyShouldTransmit", BBD_HOOK_CHANGE_PVS )
hook.Add( "NotifyShouldTransmit", BBD_HOOK_CHANGE_PVS, function( ent, shouldTransmit )
    if not ent or not IsValid( ent ) then return end
    if ent:GetClass() ~= "prop_door_rotating" then return end
    if not shouldTransmit then return end

    -- As doors enter the PVS, mark them for animation
    -- If they don't actually need to animate, they will be quickly removed from the list
    doorsToAnimate[ent] = true
end )

-- Called when a door's health changes
---@param door Entity The door that changed health
---@param name string The name of the networked variable that changed
---@param oldHealth number The door's health before the change
---@param newHealth number The door's health after the change
local function HealthChangedCallback( door, name, oldHealth, newHealth )
    previousDoorHealths[door] = oldHealth
    doorsToAnimate[door] = true
end

hook.Remove( "PostDoorCreated", BBD_HOOK_SETUP_CALLBACKS )
hook.Add( "PostDoorCreated", BBD_HOOK_SETUP_CALLBACKS, function( door )
    door:NetworkVarNotify( "HealthAfterLastDamage", HealthChangedCallback )
end )

local function SetupNotifications()
    for _, door in ipairs( ents.FindByClass( "prop_door_rotating" ) ) do
        door:NetworkVarNotify( "HealthAfterLastDamage", HealthChangedCallback )
    end
end
SetupNotifications()