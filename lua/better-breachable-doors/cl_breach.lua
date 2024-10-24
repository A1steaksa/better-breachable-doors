local BBD = _G.BBD

-- How much health each door had before the last damage event
---@type table<BBD.Door, number>
BBD.PreviousDoorHealth = BBD.PreviousDoorHealth or {}

-- When each door was previously damaged
---@type table<BBD.Door, number>
BBD.PreviousDamageTime = BBD.PreviousDamageTime or {}

-- A map of prop doors and their corresponding door entities
-- This is necessary because the callback for prop doors is inconsistent when removing the prop
-- So we're checking for the entity removed event and checking this table to see if it was a prop door
---@type table<Entity, BBD.Door>
BBD.PropDoors = BBD.PropDoors or {}

-- Constants
local ANGLE_ZERO = Angle( 0, 0, 0 )

-- Localized Global Functions
local Angle = Angle
local IsValid = IsValid
local GetConVar = GetConVar
local CurTime = CurTime
local ipairs = ipairs
local lerpAngle = LerpAngle

-- Localized Library Functions
local ents_FindByClass = ents.FindByClass
local hook_Add = hook.Add
local hook_Remove = hook.Remove
local math_min = math.min
local math_max = math.max
local math_abs = math.abs
local math_pow = math.pow
local math_ease_outElastic = math.ease.OutElastic
local render_OverrideColorWriteEnable = render.OverrideColorWriteEnable
local render_SetBlend = render.SetBlend

-- Local variables because they're used each frame during animations
local handleDamageAnimationDuration = 0.1
local handleBreachAnimationDuration = 2
local handleRespawnAnimationDuration = 1

local doorDamageAnimationDuration = 0.1
local doorBreachAnimationDuration = 0.5
local doorRespawnAnimationDuration = 0.5

local breachedHandleAngle   = Angle( 0, 79, 10 )
local breachedPushbarAngle  = Angle( -1, 9, 15 )

local damagedHandleAngle    = Angle( 1, 10, 0 )
local damagedPushbarAngle   = Angle( 1, 1, 1 )

local breachedDoorTilt      = Angle( 0, 0, -BBD.BreachedDoorTiltAmount )
local breachedDoorRoll      = Angle( BBD.BreachedDoorRollAmount, 0, 0 )

local damagedDoorAngle      = Angle( 0, 1, 0 )

-- ConVars
local conVarEnabled             = GetConVar( BBD.CONVAR_ENABLED )
local conVarMaxHealth           = GetConVar( BBD.CONVAR_HEALTH_MAX )
local conVarRespawnTime         = GetConVar( BBD.CONVAR_RESPAWNTIME )
local conVarHealthRegenDelay    = GetConVar( BBD.CONVAR_HEALTH_REGEN_DELAY )
local conVarHealthRegenRate     = GetConVar( BBD.CONVAR_HEALTH_REGEN_RATE )

--#region Rendering/Animation

-- Animate a door's broken handle and pushbar in response to being open-breached
---@param door BBD.Door
---@param animationProgress number
BBD.AnimateOpenBreachedHandle = function( door, animationProgress )
    animationProgress = math_min( animationProgress, 1 )

    local handleAngle = breachedHandleAngle
    local pushbarAngle = breachedPushbarAngle
    if animationProgress < 1 then
        handleAngle = lerpAngle( math_ease_outElastic( animationProgress ), ANGLE_ZERO, breachedHandleAngle )
        pushbarAngle = lerpAngle( math_ease_outElastic( animationProgress ), ANGLE_ZERO, breachedPushbarAngle )
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
---@param door BBD.Door
---@param animationProgress number
BBD.AnimateRespawnedHandle = function( door, animationProgress )
    animationProgress = math_min( animationProgress, 1 )

    local handleAngle = ANGLE_ZERO
    local pushbarAngle = ANGLE_ZERO

    if animationProgress < 1 then
        handleAngle = lerpAngle( math_ease_outElastic( animationProgress ), breachedHandleAngle, ANGLE_ZERO )
        pushbarAngle = lerpAngle( math_ease_outElastic( animationProgress ), breachedPushbarAngle, ANGLE_ZERO )
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


-- Animate a door's handle and pushbar in response to being damaged
---@param door BBD.Door
---@param animationProgress number
BBD.AnimateDamagedHandle = function( door, animationProgress )
    -- Animation progress is mirrored so the door pushes away from damage then returns
    local adjustedProgress = math_abs( math_min( animationProgress, 1 ) - 0.5 ) * -2 + 1

    local handleAngle = ANGLE_ZERO
    local pushbarAngle = ANGLE_ZERO

    if animationProgress < 1 then

        local intensity = 1 - door:GetHealthAfterLastDamage() / conVarMaxHealth:GetFloat()

        -- Squaring the intensity makes the animation more exaggerated as the door gets closer to death
        intensity = math_pow( intensity, 2 )

        handleAngle = lerpAngle( adjustedProgress, ANGLE_ZERO, damagedHandleAngle * intensity )
        pushbarAngle = lerpAngle( adjustedProgress, ANGLE_ZERO, damagedPushbarAngle * intensity )
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
---@param door BBD.Door
---@param animationProgress number
BBD.AnimateDamagedDoor = function( door, animationProgress )
    -- Animation progress is mirrored so the door pushes away from damage then returns
    local adjustedProgress = math_abs( math_min( animationProgress, 1 ) - 0.5 ) * -2 + 1

    door:SetRenderAngles( nil )

    if animationProgress < 1 then

        local intensity = 1 - door:GetHealthAfterLastDamage() / conVarMaxHealth:GetFloat()

        -- Squaring the intensity makes the animation more exaggerated as the door gets closer to death
        local intensity = math_pow( intensity, 2 )

        local doorAngleOffset = lerpAngle( math_ease_outElastic( adjustedProgress ), ANGLE_ZERO, door:GetDamageDirection() * damagedDoorAngle * intensity )
        door:SetRenderAngles( door:GetAngles() + doorAngleOffset )
    end
end


-- Animate a door's reaction to being open-breached
---@param door BBD.Door
---@param animationProgress number
BBD.AnimateOpenBreachedDoor = function( door, animationProgress )
    animationProgress = math_min( animationProgress, 1 )

    local doorAngleOffset = breachedDoorTilt + breachedDoorRoll * -door:GetDamageDirection()

    if animationProgress < 1 then
        doorAngleOffset = lerpAngle( math_ease_outElastic( animationProgress ), ANGLE_ZERO, doorAngleOffset )
    end

    door:SetRenderAngles( nil )
    door:SetRenderAngles( door:GetAngles() + doorAngleOffset )
end


-- Animate a breached door's reaction to being respawned
---@param door BBD.Door
---@param animationProgress number
BBD.AnimateRespawnedDoor = function( door, animationProgress )
    animationProgress = math_min( animationProgress, 1 )

    door:SetRenderAngles( nil )

    if animationProgress < 1 then
        local doorAngleOffset = breachedDoorTilt + breachedDoorRoll * -door:GetDamageDirection()

        local doorAngleOffset = lerpAngle( math_ease_outElastic( animationProgress ), doorAngleOffset, ANGLE_ZERO )
        door:SetRenderAngles( door:GetAngles() + doorAngleOffset )
    end
end


-- Fully updates the door's animation(s) based on its current state.
---@param door BBD.Door The door to animate
---@param time number The current time
---@return boolean # Whether the door is still animating
BBD.AnimateDoor = function( door, time )
    local isStillAnimating = false

    local damageTime = door:GetDamageTime()
    local timeSinceDamage = time - damageTime

    local healthBefore = BBD.CalculateDoorHealth( BBD.PreviousDoorHealth[door] or conVarMaxHealth:GetFloat(), BBD.PreviousDamageTime[door] or 0, damageTime )
    local healthAfter = door:GetHealthAfterLastDamage()
    local healthDelta = healthAfter - healthBefore

    -- Negative time means CurTime() is behind the server's time
    -- In this case, don't stop animating the door, but don't animate it either
    if timeSinceDamage < 0 then return true end

    local doorTookDamage = healthDelta < 0
    if doorTookDamage then

        -- Door damage animation
        local doorDamageAnimationProgress = timeSinceDamage / doorDamageAnimationDuration

        BBD.AnimateDamagedDoor( door, doorDamageAnimationProgress )
        isStillAnimating = isStillAnimating or ( doorDamageAnimationProgress < 1 )

        -- Door handle damage animation
        if door:GetIsHandleDamage() then
            local handleDamageAnimationProgress = timeSinceDamage / handleDamageAnimationDuration
            BBD.AnimateDamagedHandle( door, handleDamageAnimationProgress )
            isStillAnimating = isStillAnimating or ( handleDamageAnimationProgress < 1 )
        end

        -- Door breaching animations
        local isDoorBreached = healthAfter <= 0
        if isDoorBreached then
            -- Door handle breach animation
            local handleAnimationProgress = timeSinceDamage / handleBreachAnimationDuration
            BBD.AnimateOpenBreachedHandle( door, handleAnimationProgress )
            isStillAnimating = isStillAnimating or ( handleAnimationProgress < 1 )

            -- Door breach animation
            local doorBreachAnimationProgress = timeSinceDamage / doorBreachAnimationDuration
            BBD.AnimateOpenBreachedDoor( door, doorBreachAnimationProgress )
            isStillAnimating = isStillAnimating or ( doorBreachAnimationProgress < 1 )

        end
    else -- Door is respawning
        local respawnTime = damageTime + conVarRespawnTime:GetFloat()
        local timeSinceRespawn = time - respawnTime

        -- Door handle respawn animation
        local handleRespawnAnimationProgress = timeSinceRespawn / handleRespawnAnimationDuration
        BBD.AnimateRespawnedHandle( door, handleRespawnAnimationProgress )
        isStillAnimating = isStillAnimating or ( handleRespawnAnimationProgress < 1 )

        -- Door respawn animation
        local doorRespawnAnimationProgress = timeSinceRespawn / doorRespawnAnimationDuration
        BBD.AnimateRespawnedDoor( door, doorRespawnAnimationProgress )
        isStillAnimating = isStillAnimating or ( doorRespawnAnimationProgress < 1 )
    end

    return isStillAnimating
end

-- This function replaces the door's draw function when it's being animated or respawned 
---@param self BBD.Door
---@param flags number?
BBD.DoorRenderOverride = function( self, flags )
    local isAnimating = BBD.AnimateDoor( self, CurTime() )
    local isRespawning = self:GetIsDoorSolidifying()

    -- Respawning doors are drawn to be partially transparent
    if isRespawning then
        -- Write to the depth buffer, but not the color buffer
        render_OverrideColorWriteEnable( true, false )
        self:DrawModel( flags )
        render_OverrideColorWriteEnable( false, false )

        -- Write to the color buffer using the newly set depth buffer values
        render_SetBlend( 0.75 )
        self:DrawModel( flags )
        render_SetBlend( 1 )
    else
        -- Draw the door normally
        self:DrawModel( flags )
    end

    if not isAnimating and not isRespawning then
        self.RenderOverride = nil
    end
end

--#endregion Rendering/Animation

--#region Utility Functions

-- Calculate the expected health of a door based on a hypothetical state.
---@param health number # The door's health at the time of the damage event
---@param damageTime number # The time the door was damaged
---@param checkTime number # The time to check the door's health at
---@return number # The door's predicted or expected health at the given time
BBD.CalculateDoorHealth = function( health, damageTime, checkTime )
    local secondsSinceDamage = checkTime - damageTime

    -- If the door is dead
    if health <= 0 then
        -- Hasn't respawned
        if secondsSinceDamage < conVarRespawnTime:GetFloat() then
            return 0
        else -- Has respawned
            return conVarMaxHealth:GetFloat()
        end
    end

    -- We're behind the server's time, so health regen is impossible
    if damageTime > checkTime then
        return health
    end

    local healthRegenDelay = conVarHealthRegenDelay:GetFloat()

    -- If the door was damaged recently, don't regen health
    if secondsSinceDamage < healthRegenDelay then
        return health
    end

    -- Can't have negative seconds of regen
    local secondsOfRegen = math_max( secondsSinceDamage - healthRegenDelay, 0 )

    -- Regen health up to the max health
    return math_min( health + secondsOfRegen * conVarHealthRegenRate:GetFloat(), conVarMaxHealth:GetFloat() )
end

--#endregion Utility Functions

--#region Callbacks

-- Called when a door's health changes
---@param door BBD.Door The door that changed health
---@param name string The name of the networked variable that changed
---@param oldHealth number The door's health before the change
---@param newHealth number The door's health after the change
BBD.HealthChangedCallback = function( door, name, oldHealth, newHealth )
    BBD.PreviousDoorHealth[door] = oldHealth

    -- If the door respawned, it needs to animate
    if oldHealth <= 0 and newHealth >= conVarMaxHealth:GetFloat() then
        door.RenderOverride = BBD.DoorRenderOverride
    end
end


-- Called when a door's damage time changes
---@param door BBD.Door The door that changed damage time
---@param name string The name of the networked variable that changed
---@param oldTime number The door's damage time before the change
---@param serverTime number The door's damage time after the change
BBD.DamageTimeChangedCallback = function( door, name, oldTime, serverTime )
    BBD.PreviousDamageTime[door] = oldTime

    door.RenderOverride = BBD.DoorRenderOverride
end


-- Called when a prop door is spawned and assigned to a door
---@param door BBD.Door
---@param name string
---@param oldProp Entity
---@param newProp Entity
BBD.PropDoorChangedCallback = function( door, name, oldProp, newProp )
    if IsValid( newProp ) and not IsValid( oldProp ) then
        door:SetNoDraw( true )
        BBD.PropDoors[newProp] = door
        -- Steal the door's model instance so we have its decals
        newProp:SnatchModelInstance( door )
    end
end


---@param door BBD.Door
---@param shouldTransmit boolean
BBD.OnEntityEnteredPvs = function( door, shouldTransmit )
    if not shouldTransmit then return end
    if not door or not IsValid( door ) then return end
    if door:GetClass() ~= "prop_door_rotating" then return end

    -- As doors enter the PVS, mark them for animation
    -- If they don't actually need to animate, they will be quickly removed from the list
    door.RenderOverride = BBD.DoorRenderOverride
end


---@param ent Entity
---@param fullUpdate boolean 
BBD.OnEntityRemoved = function( ent, fullUpdate  )
    if fullUpdate then return end
    if not ent or not IsValid( ent ) then return end
    if ent:GetClass() ~= "prop_physics" then return end

    -- If this was a prop door being removed, start drawing the corresponding door again
    local door = BBD.PropDoors[ent]
    if door then
        door:SetNoDraw( false )
        BBD.PropDoors[ent] = nil
    end
end

--#endregion Callbacks

local hotloaded = false
if BBD.Disable then hotloaded = true BBD.Disable() end

-- Enable the door breach system
BBD.Enable = function()
    -- Attempt to animate doors entering the player's PVS
    hook_Add( "NotifyShouldTransmit", BBD.HOOK_CHANGE_PVS, BBD.OnEntityEnteredPvs )

    -- Detect prop doors being removed
    hook_Add( "EntityRemoved", BBD.HOOK_PROP_REMOVAL, BBD.OnEntityRemoved )

    -- Set up network callbacks for all doors
    for _, door in ipairs( ents_FindByClass( "prop_door_rotating" ) ) do
        ---@cast door Entity

        door:NetworkVarNotify( "HealthAfterLastDamage", BBD.HealthChangedCallback )
        door:NetworkVarNotify( "DamageTime", BBD.DamageTimeChangedCallback )
        door:NetworkVarNotify( "PropDoor", BBD.PropDoorChangedCallback )
    end
end

-- Disable the door breach system
BBD.Disable = function()
    hook_Remove( "NotifyShouldTransmit", BBD.HOOK_CHANGE_PVS )
    hook_Remove( "EntityRemoved", BBD.HOOK_PROP_REMOVAL )
end

-- Enable the system when the map loads
hook_Add( "InitPostEntity", BBD.HOOK_ENABLE, function()
    if conVarEnabled:GetBool() then BBD.Enable() end
end )

-- Enable or disable the system when the ConVar changes
cvars.AddChangeCallback( conVarEnabled:GetName(), function( _, oldValue, newValue )
    if newValue == "1" then BBD.Enable() else BBD.Disable() end
end )

if hotloaded then BBD.Enable() end