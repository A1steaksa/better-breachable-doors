local previousDoorHealths = {}

local handleDamageAnimationDuration = 0.75
local handleBreachAnimationDuration = 2
local handleRespawnAnimationDuration = 1

local doorDamageAnimationDuration = 0.1
local doorBreachAnimationDuration = 0.5
local doorRespawnAnimationDuration = 0.5

local ANGLE_ZERO = Angle( 0, 0, 0 )

local ease_outElastic = math.ease.OutElastic
local lerpAngle = LerpAngle
local math_min = math.min

local conVarHealth          = GetConVar( "doorbreach_health" )
local conVarRespawnTime     = GetConVar( "doorbreach_respawntime" )

local breachedHandleAngle   = Angle( 0, 79, 10 )
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
    -- Animation progress is mirrored so the door pushes away from damage then returns
    local adjustedProgress = math.abs( math_min( animationProgress, 1 ) - 0.5 ) * -2 + 1

    door:SetRenderAngles( nil )

    if animationProgress < 1 then

        local intensity = 1 - door:GetHealthAfterLastDamage() / conVarHealth:GetFloat()

        local intensity = math.pow( intensity, 2 )

        local doorAngleOffset = lerpAngle( ease_outElastic( adjustedProgress ), ANGLE_ZERO, -door:GetDamageDirection() * damagedDoorAngle * intensity )
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

    -- If the door hasn't taken damage, don't animate it
    if damageTime <= 0 then
        door.RenderOverride = nil
        return
    end

    -- Negative time means CurTime() is behind the server's time
    if timeSinceDamage < 0 then return end

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
    if not isStillAnimating then
        door.RenderOverride = nil
    end
end

-- Used as a RenderOverride for doors that need to animate
---@param self Entity
---@param flags STUDIO
local function DoorAnimationRenderOverride( self, flags )
    UpdateAnimationState( self, CurTime() )
    self:DrawModel( flags )
end

hook.Remove( "NotifyShouldTransmit", BBD_HOOK_CHANGE_PVS )
hook.Add( "NotifyShouldTransmit", BBD_HOOK_CHANGE_PVS, function( door, shouldTransmit )
    if not door or not IsValid( door ) then return end
    if door:GetClass() ~= "prop_door_rotating" then return end
    if not shouldTransmit then return end

    -- As doors enter the PVS, mark them for animation
    -- If they don't actually need to animate, they will be quickly removed from the list
    door.RenderOverride = DoorAnimationRenderOverride
end )

-- Called when a door's health changes
---@param door Entity The door that changed health
---@param name string The name of the networked variable that changed
---@param oldHealth number The door's health before the change
---@param newHealth number The door's health after the change
local function HealthChangedCallback( door, name, oldHealth, newHealth )
    previousDoorHealths[door] = oldHealth
    door.RenderOverride = DoorAnimationRenderOverride
end

-- Called when a door's damage time changes
---@param door Entity The door that changed damage time
---@param name string The name of the networked variable that changed
---@param oldTime number The door's damage time before the change
---@param serverTime number The door's damage time after the change
local function DamageTimeChangedCallback( door, name, oldTime, serverTime )
    door.RenderOverride = DoorAnimationRenderOverride
end

hook.Remove( "PostDoorCreated", BBD_HOOK_SETUP_CALLBACKS )
hook.Add( "PostDoorCreated", BBD_HOOK_SETUP_CALLBACKS, function( door )
    door:NetworkVarNotify( "HealthAfterLastDamage", HealthChangedCallback )
    door:NetworkVarNotify( "DamageTime", DamageTimeChangedCallback )
end )

local function SetupNotifications()
    for _, door in ipairs( ents.FindByClass( "prop_door_rotating" ) ) do
        door:NetworkVarNotify( "HealthAfterLastDamage", HealthChangedCallback )
        door:NetworkVarNotify( "DamageTime", DamageTimeChangedCallback )
    end
end
SetupNotifications()