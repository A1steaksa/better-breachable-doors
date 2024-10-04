-- Effects Config
-- Amount to tilt the door forward when it's been breached
local brokenDoorTiltAmount = -2.5

-- Which direction the door is being pushed when it's breached
---@type table<Entity, DOOR_DIRECTION>
local respawnDirection      = {}

-- The doors that are connected to area portals
--- Key: Door, Value: Area Portals
---@type table<Entity, Entity[]>
local doorAreaPortals = {}

-- Constants
local ANGLE_ZERO = Angle( 0, 0, 0 )

-- ConVars
local conVarEnabled         = GetConVar( "doorbreach_enabled" )
local conVarHealth          = GetConVar( "doorbreach_health" )
local conVarUnlock          = GetConVar( "doorbreach_unlock" )
local conVarOpen            = GetConVar( "doorbreach_open" )
local conVarOpenSpeed       = GetConVar( "doorbreach_speed" )
local conVarExplosiveSpeed  = GetConVar( "doorbreach_explosive_speed" )
local conVarRespawnTime     = GetConVar( "doorbreach_respawntime" )

-- Based on `CBaseEntity::GetMoveDoneTime`
local function GetMoveDoneTime( ent )
    local moveDoneTime = ent:GetInternalVariable( "m_flMoveDoneTime" )
    return moveDoneTime >= 0 and moveDoneTime - ent:GetInternalVariable( "ltime" ) or -1
end

-- Based on `CBaseEntity::WillSimulateGamePhysics`
---@param ent Entity Entity to check
local function WillSimulateGamePhysics( ent )
    if not ent:IsPlayer() then
        local moveType = ent:GetMoveType()

        if moveType == MOVETYPE_NONE or moveType == MOVETYPE_VPHYSICS then
            return false
        end

        if SERVER then
            -- MOVETYPE_PUSH is only valid on the server
            if moveType == MOVETYPE_PUSH and GetMoveDoneTime( ent ) <= 0 then
                return false
            end
        end
    end

    return true
end

-- Based on `CBaseEntity::CheckHasGamePhysicsSimulation`
---@param ent Entity Door to check
local function CheckHasGamePhysicsSimulation( ent )
    if not IsValid( ent ) then return end

    local isSimulating = WillSimulateGamePhysics( ent )

    if isSimulating ~= ent:IsEFlagSet( EFL_NO_GAME_PHYSICS_SIMULATION ) then
        return
    end

    if isSimulating then
        ent:RemoveEFlags( EFL_NO_GAME_PHYSICS_SIMULATION )
    else
        ent:AddEFlags( EFL_NO_GAME_PHYSICS_SIMULATION )
    end
end

-- Based on `CBaseEntity::SetMoveDoneTime`
---@param ent Entity Door to set the move done time for
---@param delay number Time, in seconds, to set the move done time to
local function SetMoveDoneTime( ent, delay )
    if not IsValid( ent ) then return end
    if not delay then return end

    if delay >= 0 then
        local localTime = ent:GetInternalVariable( "ltime" ) -- Called m_flLocalTime in baseentity.h
        ent:SetSaveValue( "m_flMoveDoneTime", localTime + delay )
    else
        ent:SetSaveValue( "m_flMoveDoneTime", -1 )
    end

    CheckHasGamePhysicsSimulation( ent )
end

-- Moves a door to a given angle at a given speed.  
-- Based on `CPropDoorRotating::AngularMove`
---@param ent Entity Door to move
---@param goalAng Angle|Vector Angle to move the door to
---@param speed number Speed at which to move the door
---@return number # The time, in seconds, it will take to move the door
local function AngularMove( ent, goalAng, speed )
    if not IsValid( ent ) then return end
    if not goalAng or not speed then return end
    if speed <= 0 then return end
    if isvector( goalAng ) then goalAng = Angle( goalAng.x, goalAng.y, goalAng.z ) end

    local goalAngVector = Vector( goalAng.p, goalAng.y, goalAng.r )

    ent:SetSaveValue( "m_angGoal", goalAngVector )

    local localAngles = ent:GetLocalAngles()

    -- If we're already there
    if localAngles == goalAng then return end

    -- The delta we'll need to move to reach the goal angle
    local delta = goalAng - localAngles
    local deltaVector = Vector( delta.p, delta.y, delta.r )

    -- Divide by speed to get the time it will take to reach the goal angle
    local travelTime = deltaVector:Length() / speed

    -- When the door will be done moving
    SetMoveDoneTime( ent, travelTime )

    -- Scale the delta by travel time to get the velocity
    ent:SetLocalAngularVelocity( delta * ( 1 / travelTime ) )

    -- Doors don't move unless they're thinking, and they don't think by default
    ent:NextThink( CurTime() )

    return travelTime
end


---@param door Entity Door to breach
---@param dmg CTakeDamageInfo Damage that breached the door
local function BreachDoor( door, dmg )
    -- Figure out which direction the damage is pushing the door
    local openDirection = dmg:GetDamageForce():Dot( door:GetForward() ) > 0 and DOOR_DIRECTION_FORWARD or DOOR_DIRECTION_BACKWARD
    respawnDirection[ door ] = openDirection

    -- Get the door's normal open angle in the direction it's being pushed
    local goalAng = door:GetInternalVariable( openDirection == DOOR_DIRECTION_FORWARD and "m_angRotationOpenForward" or "m_angRotationOpenBack" )

    -- Modify the normal open angle to make the door look broken after it's opened
    goalAng = goalAng + Vector( 0,0, brokenDoorTiltAmount )

    -- Use the correct open speed for the damage type
    local openSpeed = dmg:IsExplosionDamage() and conVarExplosiveSpeed:GetFloat() or conVarOpenSpeed:GetFloat()

    -- Get all the doors with the same name as the breached door
    local partnerDoors = ents.FindByName( door:GetName() )

    -- Silence this door and all other doors with the same name
    local previousSpawnFlags = {}
    for _, partner in pairs( partnerDoors ) do
        if not IsValid( partner ) then continue end

        local spawnFlags = door:GetSpawnFlags()
        local silentFlags = bit.bor( spawnFlags, DOOR_FLAG_SILENT )

        partner:SetKeyValue( "spawnflags", silentFlags )

        previousSpawnFlags[partner] = spawnFlags
    end

    -- Find the master door, which is the door with the same name but either no owner or an owner with a different name
    local masterDoor = NULL
    for _, partner in pairs( partnerDoors ) do
        if not IsValid( partner ) then continue end

        if not IsValid( partner:GetOwner() ) or partner:GetOwner():GetName() ~= door:GetName() then
            masterDoor = partner
            break
        end
    end

    if not IsValid( masterDoor ) then
        error( "No master door found for door " .. door:GetName() )
        return
    end

    -- Open the master door, which will open all other partner doors
    -- This sets the correct door states and the MoveDone callback
    masterDoor:Input( "Open" )

    -- Override the breached door's movement to breach it open
    AngularMove( door, goalAng, openSpeed )

    -- Reset the spawn flags for the doors
    for _, partner in pairs( partnerDoors ) do
        if not IsValid( partner ) then continue end

        partner:SetKeyValue( "spawnflags", previousSpawnFlags[partner] )
    end
end


-- Called when a door is respawned.
---@param door Entity Door that respawned
local function HandleDoorRespawn( door )
    if not IsValid( door ) then return end

    door:SetHealthAfterLastDamage( conVarHealth:GetFloat() )

    -- Reset the door's rotation to its normal open position
    local dirName = respawnDirection[ door ] == DOOR_DIRECTION_FORWARD and "m_angRotationOpenForward" or "m_angRotationOpenBack"
    local resetRotation = door:GetInternalVariable( dirName )
    door:SetAngles( Angle( resetRotation.x, resetRotation.y, resetRotation.z ) )

    door:SetLocalAngularVelocity( ANGLE_ZERO )

    door:SetSaveValue( "m_eDoorState", DOOR_STATE_OPEN )
end

-- Called when a door is breached.
---@param door Entity Door that died
---@param dmg CTakeDamageInfo Damage that killed the door
local function HandleDoorBreach( door, dmg )
    if not door or not dmg or not IsValid( door ) or not IsValid( dmg ) then return end

    -- Unlock the door
    if conVarUnlock:GetBool() then
        door:Input( "Unlock" )
    end

    -- Open the door
    if conVarOpen:GetBool() then
        BreachDoor( door, dmg )
    end

    timer.Simple( conVarRespawnTime:GetFloat(), function()
        HandleDoorRespawn( door )
    end )
end


-- Called when an entity takes damage while door breaching is enabled.
---@param door Entity Entity that took damage
---@param dmg CTakeDamageInfo Damage dealt
local function HandleDoorDamage( door, dmg )
    if not door or not IsValid( door ) then return end
    if door:GetClass() ~= "prop_door_rotating" then return end

    local time = CurTime()

    -- Get the current (old) values for the door
    local oldHealth = door:GetHealthAfterLastDamage()
    if oldHealth == 0 then return end

    -- Calculate the new values for the door
    local newHealth = oldHealth - dmg:GetDamage()

    local damageOpenDirection = dmg:GetDamageForce():Dot( door:GetForward() ) > 0 and 1 or -1

    -- Update the door's values with the new ones
    door:SetHealthAfterLastDamage( math.max( newHealth, 0 ) )
    door:SetDamageTime( time )
    door:SetDamageDirection( damageOpenDirection )

    if newHealth <= 0 then
        HandleDoorBreach( door, dmg )
    end
end


-- Development hotloading
hook.Remove( "Think", BBD_HOOK_SEND_DAMAGE )
hook.Remove( "EntityTakeDamage", BBD_HOOK_DAMAGE_DETECTION )
hook.Remove( "InitPostEntity", BBD_HOOK_SETUP )
hook.Add( "EntityTakeDamage", BBD_HOOK_DAMAGE_DETECTION, HandleDoorDamage )
hook.Add( "PlayerSpawn", "A1_DoorBreach_SpawnMove", function( player, _ )
    if game.GetMap() == "raidz_lobby" then
        player:SetPos( Vector( -5930,-8101, 64.5 ) )
    end
end )


local function SetupAreaPortalConnections()
    local areaPortals = ents.FindByClass( "func_areaportal" )
    local doors = ents.FindByClass( "prop_door_rotating" )

    for _, portal in pairs( areaPortals ) do
        local portalTargetName = portal:GetInternalVariable( "target" )

        if not portalTargetName or portalTargetName == "" then continue end

        -- Find the door(s) that this area portal is connected to
        for _, door in pairs( doors ) do
            if not IsValid( door ) then continue end
            if door:GetName() ~= portalTargetName then continue end

            doorAreaPortals[ door ] = doorAreaPortals[ door ] or {}
            table.insert( doorAreaPortals[ door ], portal )
        end
    end
end
SetupAreaPortalConnections()


-- Called when the map is done loading and entities are all spawned
hook.Add( "InitPostEntity", BBD_HOOK_SETUP, function()
    if conVarEnabled:GetBool() then
        hook.Add( "EntityTakeDamage", BBD_HOOK_DAMAGE_DETECTION, HandleDoorDamage )
    end

    SetupAreaPortalConnections()
end )


-- Don't allow players to use breached doors
hook.Add( "PlayerUse", BBD_HOOK_SUPPRESS_USE, function( ply, ent )
	if not ent or not IsValid( ent ) then return end
    if ent:GetClass() ~= "prop_door_rotating" then return end

    if ent:GetHealthAfterLastDamage() == 0 then
        return false
    end
end )


-- Ensure damage hooks are only active while the system is enabled
cvars.AddChangeCallback( conVarEnabled:GetName(), function( _, oldValue, newValue )
    if newValue == "1" then
        hook.Add( "EntityTakeDamage", BBD_HOOK_DAMAGE_DETECTION, HandleDoorDamage )
    else
        hook.Remove( "EntityTakeDamage", BBD_HOOK_DAMAGE_DETECTION )
        hook.Remove( "Think", BBD_HOOK_SEND_DAMAGE )
    end
end )


-- Update door health when the door health convar changes
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