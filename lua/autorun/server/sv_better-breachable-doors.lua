util.AddNetworkString( "A1_DoorBreach_OnDoorBreached" )
util.AddNetworkString( "A1_DoorBreach_OnDoorRespawned" )
util.AddNetworkString( "A1_DoorBreach_OnDoorDamaged" )
util.AddNetworkString( "A1_DoorBreach_OnDoorHandleDamaged" )

local conVarEnabled         = CreateConVar( "doorbreach_enabled",           "1",    FCVAR_ARCHIVE, "Enable or disable the door breach system.", 0, 1 )
local conVarHandleDmg       = CreateConVar( "doorbreach_handlemult",        "2",    FCVAR_ARCHIVE, "Multiplier for damage when a door is shot near the handle.", 0 )
local conVarHealth          = CreateConVar( "doorbreach_health",            "10",  FCVAR_ARCHIVE, "Starting health for doors.", 1 )
local conVarRegen           = CreateConVar( "doorbreach_regen",             "1",    FCVAR_ARCHIVE, "Enable or disable health regeneration on doors that have been partially damaged.", 0, 1 )
local conVarRegenRate       = CreateConVar( "doorbreach_regenrate",         "1",    FCVAR_ARCHIVE, "The rate, in health per second, that door health regenerates", 0 )
local conVarRegenDelay      = CreateConVar( "doorbreach_regendelay",        "5",    FCVAR_ARCHIVE, "The delay, in seconds, before door health starts regenerating after taking damage.", 0 )
local conVarUnlock          = CreateConVar( "doorbreach_unlock",            "1",    FCVAR_ARCHIVE, "Enable or disable locked doors becoming unlocked when breached.", 0, 1 )
local conVarOpen            = CreateConVar( "doorbreach_open",              "1",    FCVAR_ARCHIVE, "Enable or disable doors opening when breached.", 0, 1 )
local conVarOpenSpeed       = CreateConVar( "doorbreach_speed",             "500",  FCVAR_ARCHIVE, "Speed, in degrees per second, at which doors open when breached.", 0 )
local conVarProp            = CreateConVar( "doorbreach_prop",              "1",    FCVAR_ARCHIVE, "Enable or disable doors turning into props when breached.", 0, 1 )
local conVarPropVel         = CreateConVar( "doorbreach_prop_forcemult",    "1.5",  FCVAR_ARCHIVE, "Multiplier for the bullet impact velocity of the prop door when it is spawned.", 0 )
local conVarRespawnTime     = CreateConVar( "doorbreach_respawntime",       "30",   FCVAR_ARCHIVE, "Time, in seconds, before the prop door is removed.", 0 )

-- Door states
local DOOR_STATE_CLOSED     = 0
local DOOR_STATE_OPENING    = 1
local DOOR_STATE_OPEN       = 2
local DOOR_STATE_CLOSING    = 3
local DOOR_STATE_AJAR       = 4

-- Effects Config
-- Amount to tilt the door forward when it's been breached
local brokenDoorTiltAmount = -2.5
-- Amount to rotate the door open more than normal when it's been breached
local brokenDoorExtraRotation = 2.5

-- Networking Config
-- The minimum time between damage events being sent to clients for the same door
local minDamageDelay = 0.15

-- Sound tables
local breakSounds = {}
local damageSounds = {}
local handleDamageSounds = {}

-- These tables are indexed by door entities
local doorHealthsAfterLastDamage = {}
local doorLastDamageTimes = {}
local doorRespawnDirections = {} -- 1 for forward, -1 for backward

local ANGLE_ZERO = Angle( 0, 0, 0 )

-- Called when a door is respawned.
---@param door Entity Door that respawned
local function HandleDoorRespawn( door )
    if not IsValid( door ) then return end

    -- Alert clients that the door has respawned
    net.Start( "A1_DoorBreach_OnDoorRespawned" )
    net.WriteEntity( door )
    net.SendPVS( door:GetPos() )

    -- Reset the door's table values
    doorHealthsAfterLastDamage[ door ] = nil
    doorLastDamageTimes[ door ] = nil

    -- Reset the door's rotation to its normal open position
    local resetRotation
    if doorRespawnDirections[ door ] == 1 then
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

    -- Alert clients that the door has been breached
    net.Start( "A1_DoorBreach_OnDoorBreached" )
    net.WriteEntity( door )
    net.SendPVS( door:GetPos() )

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
        doorRespawnDirections[ door ] = openDirection

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


    -- -- Spawn prop door
    -- if conVarProp:GetBool() then
    --     local propDoor = ents.Create( "prop_physics" )
    --     propDoor:SetModel( door:GetModel() )
    --     propDoor:SetMaterial( door:GetMaterial() )
    --     propDoor:SetColor( door:GetColor() )
    --     propDoor:SetPos( door:GetPos() )
    --     propDoor:SetAngles( door:GetAngles() )
    --     propDoor:SetSkin( door:GetSkin() )

    --     local bodyGroupID = door:FindBodygroupByName( "handle01" )
    --     propDoor:SetBodygroup( bodyGroupID, door:GetBodygroup( bodyGroupID ) )

    --     propDoor:Spawn()

    --     local damageForce = dmg:GetDamageForce() * conVarPropVel:GetFloat()
    --     propDoor:GetPhysicsObject():ApplyForceOffset( damageForce, dmg:GetDamagePosition() )

    --     timer.Simple( conVarPropTime:GetFloat(), function()
    --         if not IsValid( propDoor ) then return end
    --         propDoor:Remove()
    --     end )
    -- end
end


-- Called when an entity takes damage while door breaching is enabled.
---@param ent Entity Entity that took damage
---@param dmg CTakeDamageInfo Damage dealt
local function HandleDoorDamage( ent, dmg )
    if not ent or not IsValid( ent ) then return end
    if ent:GetClass() ~= "prop_door_rotating" then return end

    local health = doorHealthsAfterLastDamage[ ent ] or conVarHealth:GetFloat()

    -- Can't damage a door that's already dead
    if health == 0 then return end

    local openDirection = dmg:GetDamageForce():Dot( ent:GetForward() ) > 0 and 1 or -1

    local time = CurTime()

    local healthAfterDamage = math.max( health - dmg:GetDamage(), 0 )
    doorHealthsAfterLastDamage[ ent ] = healthAfterDamage

    if healthAfterDamage == 0 then
        HandleDoorDeath( ent, dmg )
    else
        -- Don't allow damage to be dealt to the same door too quickly
        if doorLastDamageTimes[ ent ] and time - doorLastDamageTimes[ ent ] < minDamageDelay then
            return
        end

        -- TODO: Handle damage multipliers for shooting near the handle
        local isHandleDamage = false

        net.Start( "A1_DoorBreach_OnDoorDamaged" )
        net.WriteEntity( ent )
        net.WriteInt( openDirection, 3 )
        net.WriteFloat( health / conVarHealth:GetFloat() )
        net.WriteBool( isHandleDamage )
        net.SendPVS( ent:GetPos() )
    end

    doorLastDamageTimes[ ent ] = time
end


-- Development hotloading
hook.Remove( "EntityTakeDamage", "A1_DoorBreach_DamageDetection" )
hook.Add( "EntityTakeDamage", "A1_DoorBreach_DamageDetection", HandleDoorDamage )


-- Ensure damage hooks are only active while the system is enabled
cvars.AddChangeCallback( conVarEnabled:GetName(), function( _, oldValue, newValue )
    if newValue == "1" then
        hook.Add( "EntityTakeDamage", "A1_DoorBreach_DamageDetection", HandleDoorDamage )
    else
        hook.Remove( "EntityTakeDamage", "A1_DoorBreach_DamageDetection" )
    end
end )


-- Set up damage hooks on map load
hook.Add( "InitPostEntity", "A1_DoorBreach_Setup", function()
    if conVarEnabled:GetBool() then
        hook.Add( "EntityTakeDamage", "A1_DoorBreach_DamageDetection", HandleDoorDamage )
    end
end )


-- Don't allow players to use dead doors
hook.Add( "PlayerUse", "A1_DoorBreach_SuppressUse", function( ply, ent )
	if not ent or not IsValid( ent ) then return end
    if ent:GetClass() ~= "prop_door_rotating" then return end

    if doorHealthsAfterLastDamage[ ent ] and doorHealthsAfterLastDamage[ ent ] == 0 then
        return false
    end
end)