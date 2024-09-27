-- Effects Config
-- Amount to tilt the door forward when it's been breached
local brokenDoorTiltAmount = -2.5
-- Amount to rotate the door open more than normal when it's been breached
local brokenDoorExtraRotation = 2.5

-- Indexed by door entities
---@type table<Entity, DOOR_DIRECTION>
local respawnDirection      = {}

local ANGLE_ZERO = Angle( 0, 0, 0 )

local conVarEnabled         = GetConVar( "doorbreach_enabled" )
local conVarHealth          = GetConVar( "doorbreach_health" )
local conVarUnlock          = GetConVar( "doorbreach_unlock" )
local conVarOpen            = GetConVar( "doorbreach_open" )
local conVarOpenSpeed       = GetConVar( "doorbreach_speed" )
local conVarRespawnTime     = GetConVar( "doorbreach_respawntime" )

-- Called when a door is respawned.
---@param door Entity Door that respawned
local function HandleDoorRespawn( door )
    if not IsValid( door ) then return end

    door:SetHealthAfterLastDamage( conVarHealth:GetFloat() )

    -- Reset the door's rotation to its normal open position
    local resetRotation
    if respawnDirection[ door ] == 1 then
        resetRotation = door:GetInternalVariable( "m_angRotationOpenForward" )
    else
        resetRotation = door:GetInternalVariable( "m_angRotationOpenBack" )
    end
    door:SetAngles( Angle( resetRotation.x, resetRotation.y, resetRotation.z ) )

    -- Reset the door's handle and pushbar angles
    local handleBone = door:LookupBone( "handle" )
    if handleBone then
        door:ManipulateBoneAngles( handleBone, ANGLE_ZERO )
    end
    local pushbarBone = door:LookupBone( "handle02" )
    if pushbarBone then
        door:ManipulateBoneAngles( pushbarBone, ANGLE_ZERO )
    end

    door:SetLocalAngularVelocity( ANGLE_ZERO )

    -- The door is now open
    door:SetSaveValue( "m_eDoorState", DOOR_STATE_OPEN )
end

-- Called when a door is destroyed.
---@param door Entity Door that died
---@param dmg CTakeDamageInfo Damage that killed the door
local function HandleDoorDeath( door, dmg )
    if not door or not dmg or not IsValid( door ) or not IsValid( dmg ) then return end

    -- Unlock the door
    if conVarUnlock:GetBool() then
        door:Input( "Unlock" )
    end

    -- Open the door
    if conVarOpen:GetBool() then

        -- Open or close the door to get it moving
        local doorState = door:GetInternalVariable( "m_eDoorState" )
        if doorState == DOOR_STATE_CLOSED then
            door:Input( "Open" )
        else
            door:Input( "Close" )
        end

        -- Figure out which direction the damage is pushing the door
        local openDirection = dmg:GetDamageForce():Dot( door:GetForward() ) > 0 and 1 or -1
        respawnDirection[ door ] = openDirection

        -- Get the door's normal open angle in the direction it's being pushed
        local rotationVariableName = openDirection == 1 and "m_angRotationOpenForward" or "m_angRotationOpenBack"
        local goalAng = door:GetInternalVariable( rotationVariableName )

        -- Modify the normal open angle to make the door look broken after it's opened
        goalAng = goalAng + Vector(
            0,
            brokenDoorExtraRotation * -openDirection,   -- Rotate open more than normal
            brokenDoorTiltAmount                        -- Tilt forward off its hinges
        )
        door:SetSaveValue( "m_angGoal", goalAng )

        -- Changing the speed and goal angle means we need to re-calculate the door's angular velocity and
        -- the time it will take to reach the goal angle
        local localAngles = door:GetLocalAngles()
        local angleDelta = goalAng - Vector( localAngles.p, localAngles.y, localAngles.r )
        local openDuration = angleDelta:Length() / conVarOpenSpeed:GetFloat()
        
        -- When the door will be done opening
        local openDoneTime = door:GetInternalVariable( "ltime" ) + openDuration
        door:SetSaveValue( "m_flMoveDoneTime", openDoneTime )

        -- How quickly to rotate the door to reach the goal angle in the given time
        local angularVelocityVector = angleDelta * ( 1 / openDuration )
        local angularVelocity = Angle( angularVelocityVector.x, angularVelocityVector.y, angularVelocityVector.z )
        door:SetLocalAngularVelocity( angularVelocity )

        -- Set the door's state to be opening
        door:SetSaveValue( "m_eDoorState", DOOR_STATE_OPENING )

        -- Make the handle and pushbar look broken
        -- Set serverside so that it networks to clients entering PVS
        local handleBone = door:LookupBone( "handle" )
        if handleBone then
            door:ManipulateBoneAngles( handleBone, BBD_BROKEN_HANDLE_ANGLE )
        end
        local pushbarBone = door:LookupBone( "handle02" )
        if pushbarBone then
            door:ManipulateBoneAngles( pushbarBone, BBD_BROKEN_PUSHBAR_ANGLE )
        end

    end

    timer.Simple( conVarRespawnTime:GetFloat(), function()
        HandleDoorRespawn( door )
    end )
end


-- Called when an entity takes damage while door breaching is enabled.
---@param ent Entity Entity that took damage
---@param dmg CTakeDamageInfo Damage dealt
local function HandleDoorDamage( ent, dmg )
    if not ent or not IsValid( ent ) then return end
    if ent:GetClass() ~= "prop_door_rotating" then return end

    local time = CurTime()

    -- Get the current (old) values for the door
    local oldHealth = ent:GetHealthAfterLastDamage()
    if oldHealth == 0 then return end

    -- Calculate the new values for the door
    local newHealth = oldHealth - dmg:GetDamage()

    local damageOpenDirection = dmg:GetDamageForce():Dot( ent:GetForward() ) > 0 and 1 or -1

    -- Update the door's values with the new ones
    ent:SetHealthAfterLastDamage( math.max( newHealth, 0 ) )
    ent:SetDamageTime( time )
    ent:SetDamageDirection( damageOpenDirection )

    if newHealth == 0 then
        HandleDoorDeath( ent, dmg )
    end
end


-- Development hotloading
hook.Remove( "Think", BBD_HOOK_SEND_DAMAGE )
hook.Remove( "EntityTakeDamage", BBD_HOOK_DAMAGE_DETECTION )
hook.Add( "EntityTakeDamage", BBD_HOOK_DAMAGE_DETECTION, HandleDoorDamage )


-- Set up hooks on map load
hook.Add( "InitPostEntity", BBD_HOOK_SETUP, function()
    if conVarEnabled:GetBool() then
        hook.Add( "EntityTakeDamage", BBD_HOOK_DAMAGE_DETECTION, HandleDoorDamage )
    end
end )


-- Don't allow players to use breached doors
hook.Add( "PlayerUse", BBD_HOOK_SUPPRESS_USE, function( ply, ent )
	if not ent or not IsValid( ent ) then return end
    if ent:GetClass() ~= "prop_door_rotating" then return end

    if ent:GetHealthAfterLastDamage() == 0 then
        return false
    end
end)


-- Ensure damage hooks are only active while the system is enabled
cvars.AddChangeCallback( conVarEnabled:GetName(), function( _, oldValue, newValue )
    if newValue == "1" then
        hook.Add( "EntityTakeDamage", BBD_HOOK_DAMAGE_DETECTION, HandleDoorDamage )
    else
        hook.Remove( "EntityTakeDamage", BBD_HOOK_DAMAGE_DETECTION )
        hook.Remove( "Think", BBD_HOOK_SEND_DAMAGE )
    end
end )


-- Update door health when the convar changes
cvars.AddChangeCallback( conVarHealth:GetName(), function( _, oldMaxHealth, newMaxHealth )
    for _, door in pairs( ents.FindByClass( "prop_door_rotating" ) ) do
        if not IsValid( door ) then continue end

        local oldHealth = door:GetHealthAfterLastDamage()
        local wasMaxHealth = oldHealth == tonumber( oldMaxHealth )

        local newHealth = oldHealth

        -- If we were at max health before, keep us at max health
        if wasMaxHealth then
            newHealth = newMaxHealth
        end

        -- Don't let doors have more health than the new max
        newHealth = math.min( newHealth, tonumber( newMaxHealth ) )

        door:SetHealthAfterLastDamage( newHealth )
    end
end )