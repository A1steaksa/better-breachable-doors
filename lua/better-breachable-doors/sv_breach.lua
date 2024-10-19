-- Cache table for all the doors that are logically connected to a given door
---@type table<Entity, table<Entity>>
BBD.ConnectedDoors = BBD.ConnectedDoors or {}

-- The SOLID_ enum value for doors before they are prop breached
BBD.PreBreachSolidity = BBD.PreBreachSolidity or {}

-- Doors that have respawned but are not yet solid because a Player is standing in them
BBD.NonSolidDoors = BBD.NonSolidDoors or  {}

-- The PhysCollide objects for doors that have been prop breached
-- Used to check if a Player is standing in the door's space when it respawns
-- Keyed by the door's model path
---@type table<string, PhysCollide>
BBD.DoorPhysCollides = BBD.DoorPhysCollides or {}

-- When, relative to CurTime, the last non-solid door collision check was performed
BBD.LastCollisionCheckTime = BBD.LastCollisionCheckTime or 0

-- How frequently, in seconds, to check for non-solid door collisions
BBD.CollisionCheckInterval = 0.5

-- Constants
local ANGLE_ZERO = Angle( 0, 0, 0 )

-- ConVars
local conVarEnabled             = GetConVar( BBD.CONVAR_ENABLED )
local conVarMaxHealth           = GetConVar( BBD.CONVAR_HEALTH_MAX )
local conVarHealthRegenDelay    = GetConVar( BBD.CONVAR_HEALTH_REGEN_DELAY )
local conVarHealthRegenRate     = GetConVar( BBD.CONVAR_HEALTH_REGEN_RATE )
local conVarUnlock              = GetConVar( BBD.CONVAR_UNLOCK )
local conVarBreakHinges         = GetConVar( BBD.CONVAR_BREAK_HINGES )
local conVarHandleMultiplier    = GetConVar( BBD.CONVAR_HANDLE_MULTIPLIER )
local conVarOpenSpeed           = GetConVar( BBD.CONVAR_SPEED )
local conVarExplosiveSpeed      = GetConVar( BBD.CONVAR_EXPLOSIVE_SPEED )
local conVarRespawnTime         = GetConVar( BBD.CONVAR_RESPAWNTIME )
local conVarDamageMin           = GetConVar( BBD.CONVAR_DAMAGE_MIN )
local conVarDamageMax           = GetConVar( BBD.CONVAR_DAMAGE_MAX )

--#region Sound Functions

---@param door BBD.Door
BBD.PlayDamageSound = function( door )

    local soundPos = door:GetPos() - door:OBBCenter()

    local closenessToBreach = 1 - door:GetHealthAfterLastDamage() / conVarMaxHealth:GetFloat()

    -- Exaggerate the sound as the door gets closer to breaching
    closenessToBreach = math.pow( closenessToBreach, 2 )

    local pitch = 100 + ( closenessToBreach * 50 )

    -- Low, bassy impact
    EmitSound( "physics/wood/wood_crate_impact_soft2.wav", soundPos, nil, CHAN_AUTO, 1, 75, 0, pitch )

    -- Less low, bassy impact
    EmitSound( "physics/wood/wood_box_footstep1.wav", soundPos, nil, CHAN_AUTO, 1, 75, 0, pitch )

    -- Low door impact
    EmitSound( "doors/door1_stop.wav", soundPos, nil, CHAN_AUTO, 1, 75, 0, pitch )

    if door:GetIsHandleDamage() then
        -- High, sharp slicing sound
        EmitSound( "physics/metal/metal_solid_impact_bullet4.wav", soundPos, nil, CHAN_AUTO, 1, 80, 0, pitch )
    end
end

---@param door BBD.Door
BBD.PlayRespawnSound = function( door )
    local soundPos = door:GetPos() - door:OBBCenter()

    -- Metalic latch catching
    EmitSound( "plats/hall_elev_door.wav", soundPos, nil, CHAN_AUTO, 1, 66 )

    -- Metallic lid closing
    EmitSound( "items/ammocrate_close.wav", soundPos, nil, CHAN_AUTO, 1, 66 )
end

---@param door BBD.Door
BBD.PlayBreachSound = function( door )
    local soundPos = door:GetPos() - door:OBBCenter()

    -- Forceful and bassy metallic impact
    EmitSound( "doors/vent_open1.wav", soundPos, nil, CHAN_AUTO, 0.75, 80, 0, 75 )

    -- "Dull" wood breaking
    EmitSound( "physics/wood/wood_crate_break4.wav", soundPos, nil, CHAN_AUTO, 1, 80, 0, 85 )

    -- "Sharp" wood breaking
    EmitSound( "physics/wood/wood_box_break1.wav", soundPos, nil, CHAN_AUTO, 1, 80, 0, 85 )
end

--#endregion Sound Functions

--#region Door Connection Functions

-- Finds and returns a list of all doors that are connected to the given door and will open when it does.
---@param door BBD.Door Door to check
---@return table<Entity>? # All doors that are connected to the given door, or `nil` if the door is invalid
BBD.GetConnectedDoors = function ( door )
    if not IsValid( door ) then return end

    -- Check the cache first
    if BBD.ConnectedDoors[ door ] then return BBD.ConnectedDoors[ door ] end

    local result = {}

    local doorName = string.Trim( door:GetName() )
    if doorName ~= "" then
        for _, otherDoor in pairs( ents.FindByClass( "prop_door_rotating" ) ) do
            if not IsValid( otherDoor ) then continue end

            -- Look for another door with the same name
            local otherDoorName = string.Trim( otherDoor:GetName() )
            local doorsHaveSameName = otherDoorName ~= "" and otherDoorName == doorName and otherDoor ~= door
            local doorsHaveSlaveNameConnection = otherDoor:GetInternalVariable( "slavename" ) == doorName

            if doorsHaveSameName or doorsHaveSlaveNameConnection then
                result[ #result + 1 ] = otherDoor
            end
        end
    end

    -- Remove the original door from the list
    table.RemoveByValue( result, door )

    BBD.ConnectedDoors[ door ] = result
    return result
end

-- Returns whether or not the given door has any connected doors.
-- Uses cached connections data if available.
---@param door BBD.Door Door to check
---@return boolean # Whether or not the door has any connected doors
BBD.DoorHasConnections = function( door )
    local connectedDoors = BBD.GetConnectedDoors( door )
    return connectedDoors ~= nil and #connectedDoors > 0
end

--#endregion Door Connection Functions

--#region AngularMove Port

-- Based on `CBaseEntity::GetMoveDoneTime`
---@param ent Entity Entity to get the move done time for
---@return number # The time, in seconds, it will take to move the door or -1 if an error occurred
local function GetMoveDoneTime( ent )
    local moveDoneTime = ent:GetInternalVariable( "m_flMoveDoneTime" )
    return moveDoneTime >= 0 and moveDoneTime - ent:GetInternalVariable( "ltime" ) or -1
end

-- Based on `CBaseEntity::WillSimulateGamePhysics`
---@param ent Entity Entity to check
---@return boolean # Whether or not the entity will simulate game physics
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
---@return number? # The time, in seconds, it will take to move the door or nil if an error occurred
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

--#endregion AngularMove Port

--#region Door Respawn Logic

-- Determines if any Players are standing with any respawning door's space.
---@param door BBD.Door Door to check for colliding players
---@return table<Entity> # All players colliding with the door
BBD.GetCollidingPlayers = function( door )

    local mdl = door:GetModel()
    if not BBD.DoorPhysCollides[ mdl ] then
        BBD.DoorPhysCollides[ mdl ] = CreatePhysCollideBox( door:GetCollisionBounds() )
    end
    local physCollide = BBD.DoorPhysCollides[ mdl ]

    local collidingPlayers = {}

    local doorPos = door:GetPos()
    local doorAngles = door:GetAngles()

    -- Check if any players are standing in the door's space
    for _, ply in player.Iterator() do
        if not IsValid( ply ) then continue end

        local plyPos = ply:GetPos()

        local hit = physCollide:TraceBox( doorPos, doorAngles, plyPos, plyPos, ply:GetHull() )

        if hit then
            collidingPlayers[ #collidingPlayers + 1 ] = ply
        end
    end

    return collidingPlayers
end

-- Called regularly to check if any player is colliding with any door that is respawning.
BBD.CheckPlayerCollisions = function()
    local time = CurTime()

    -- Don't check too often
    if BBD.LastCollisionCheckTime > 0 and time - BBD.LastCollisionCheckTime < BBD.CollisionCheckInterval then return end
    BBD.LastCollisionCheckTime = time

    for door, _ in pairs( BBD.NonSolidDoors ) do
        ---@cast door BBD.Door
        if not IsValid( door ) then continue end

        local collidingPlayers = BBD.GetCollidingPlayers( door )

        -- If no players are colliding with the door, make it solid
        if #collidingPlayers <= 0 then
            door:SetCollisionGroup( COLLISION_GROUP_NONE )
            BBD.NonSolidDoors[ door ] = nil
            door:SetIsDoorSolidifying( false )

            BBD.PlayRespawnSound( door )
        end
    end
end

-- Called when a door is respawned.
---@param door BBD.Door Door that respawned
---@param isPropBreach boolean Whether or not the door was prop breached
BBD.RespawnDoor = function( door, isPropBreach )
    if not IsValid( door ) then return end

    -- Reset the door's rotation to its normal open position
    local dirName = door:GetDamageDirection() == BBD.OPEN_DIRECTION_FORWARD and "m_angRotationOpenForward" or "m_angRotationOpenBack"
    local resetRotation = door:GetInternalVariable( dirName )
    local resetAngle = Angle( resetRotation.x, resetRotation.y, resetRotation.z )
    if not IsValid( door:GetParent() ) then
        -- DarkRP overrides ENT:SetAngle, so we use ENT:SetLocalAngles instead if the door doesn't have a parent
        -- Hopefully they don't decide to override that too in the future...
        door:SetLocalAngles( resetAngle )
    else
        door:SetAngles( resetAngle )
    end

    -- Reset the door's solidity to whatever it was before it was breached
    door:SetSolid( BBD.PreBreachSolidity[ door ] )
    BBD.PreBreachSolidity[ door ] = nil

    -- Make sure the door isn't still trying to move
    door:SetLocalAngularVelocity( ANGLE_ZERO )

    -- Don't retain bullet holes and such when respawning
    door:RemoveAllDecals()

    -- Reset the door's health to the max health
    door:SetHealthAfterLastDamage( conVarMaxHealth:GetFloat() )

    if isPropBreach then
        local propDoor = door:GetPropDoor()
        if IsValid( propDoor ) then
            propDoor:Remove()
        end

        if #BBD.GetCollidingPlayers( door ) > 0 then
            -- Make the door non-solid to avoid trapping the player
            door:SetCollisionGroup( COLLISION_GROUP_PASSABLE_DOOR )
            door:SetIsDoorSolidifying( true )

            -- Start checking to see if the player leaves the door's space
            BBD.NonSolidDoors[ door ] = true
        else
            door:SetCollisionGroup( COLLISION_GROUP_NONE )
            BBD.PlayRespawnSound( door )
        end
    else
        BBD.PlayRespawnSound( door )
    end

    door:NextThink( CurTime() )
end

--#endregion Door Respawn Logic

--#region Door Breach Logic

-- Breaches a door by opening it violently
---@param door BBD.Door Door to breach
---@param dmg CTakeDamageInfo Damage that breached the door
BBD.OpenBreachDoor = function( door, dmg )

    -- Figure out which direction the damage is pushing the door
    local openDirection = BBD.GetDoorOpenDirection( door, dmg )
    door:SetDamageDirection( openDirection )

    -- Get the door's normal open angle in the direction it's being pushed
    local goalAng = door:GetInternalVariable( openDirection == BBD.OPEN_DIRECTION_FORWARD and "m_angRotationOpenForward" or "m_angRotationOpenBack" )

    -- Modify the normal open angle to make the door look broken after it's opened
    goalAng = goalAng + Vector( 0,0, -BBD.BreachedDoorTiltAmount )

    -- Use the correct open speed for the damage type
    local openSpeed = dmg:IsExplosionDamage() and conVarExplosiveSpeed:GetFloat() or conVarOpenSpeed:GetFloat()

    -- Silence the door's opening sound
    local previousSpawnFlags = door:GetSpawnFlags()
    local silentFlags = bit.bor( previousSpawnFlags, 4096 ) -- 4096 is DOOR_FLAG_SILENT
    door:SetKeyValue( "spawnflags", silentFlags )

    -- Open the door to set its MoveDone function
    door:Input( "Open" )

    -- Override the breached door's movement to breach it open
    AngularMove( door, goalAng, openSpeed )

    -- Reset the door's spawnflags to their previous values
    door:SetKeyValue( "spawnflags", previousSpawnFlags )

    BBD.PlayBreachSound( door )
end

-- Breaches a door by replacing it with a prop door and throwing the prop door inward
---@param door BBD.Door The door to replace with a prop door.
---@param dmg CTakeDamageInfo Damage that killed the door.
BBD.PropBreachDoor = function( door, dmg )

    -- Silence the door's opening sound
    local previousSpawnFlags = door:GetSpawnFlags()
    local silentFlags = bit.bor( previousSpawnFlags, 4096 ) -- 4096 is DOOR_FLAG_SILENT
    door:SetKeyValue( "spawnflags", silentFlags )

    -- Open the door to trigger area portals
    door:Input( "Open" )

    -- Reset the door's spawnflags to their previous values
    door:SetKeyValue( "spawnflags", previousSpawnFlags )

    door:SetSolid( SOLID_NONE )

    local prop = ents.Create( "prop_physics" )
    prop:SetModel( door:GetModel() )
    prop:SetPos( door:GetPos() )
    prop:SetAngles( door:GetAngles() )

    -- Done in a timer because props don't exist on the client until the next tick
    timer.Simple( 0, function() door:SetPropDoor( prop ) end )

    -- Copy the Body Group values from the door to the prop
    for i = 0, door:GetNumBodyGroups() - 1 do
        prop:SetBodygroup( i, door:GetBodygroup( i ) )
    end

    prop:SetSkin( door:GetSkin() )

    -- Scale the prop door to be slightly smaller than the original door to mitigate clipping with doorframes
    prop:Spawn()
    prop:SetModelScale( BBD.PropCollisionScale, 0 )
    prop:Activate()
    prop:SetModelScale( 1, 0 )

    local phys = prop:GetPhysicsObject()

    -- We want the prop to hurt if it hits players, and we don't want people to be able to gravity gun the door
    phys:AddGameFlag( FVPHYSICS_NO_PLAYER_PICKUP )
    phys:AddGameFlag( FVPHYSICS_WAS_THROWN )
    phys:AddGameFlag( FVPHYSICS_HEAVY_OBJECT )

    -- Doors have a lot of surface area and we don't want them to slow down from air resistance
    phys:EnableDrag( false )

    -- Apply the damage force to the prop door
    local openDirection = BBD.GetDoorOpenDirection( door, dmg )
    local mass = phys:GetMass()

    local backwardForce = door:GetForward() * -openDirection * 250
    local upwardForce = door:GetUp() * 50

    phys:ApplyForceCenter( mass * ( backwardForce + upwardForce ) )

    -- Double doors get some additional sideways force to make them open more dramatically
    if BBD.DoorHasConnections( door ) then
        local mins = door:OBBMins()
        local maxs = door:OBBMaxs()
        local ySize = maxs.y - mins.y
        local forcePos = door:GetPos() + door:GetRight() * -ySize
        local sideForce = door:GetRight() * 100

        phys:ApplyForceOffset( mass * ( sideForce ), forcePos )
    end


    BBD.PlayBreachSound( door )
end

-- Called when a door has run out of health and is being breached.
---@param door BBD.Door The door that was breached.
---@param dmg CTakeDamageInfo Damage that killed the door.
BBD.OnDoorBreached = function( door, dmg )
    if not door or not dmg or not IsValid( door ) or not IsValid( dmg ) then return end

    if conVarUnlock:GetBool() then
        door:Input( "Unlock" )
    end

    local connectedDoors = BBD.GetConnectedDoors( door )

    -- Set up connected doors to be breached
    if BBD.DoorHasConnections( door ) then
        local time = CurTime()
        for _, connectedDoor in pairs( connectedDoors ) do
            if not IsValid( connectedDoor ) then continue end

            connectedDoor:SetIsHandleDamage( false )
            connectedDoor:SetHealthAfterLastDamage( 0 )
            connectedDoor:SetDamageDirection( BBD.GetDoorOpenDirection( connectedDoor, dmg ) )
            connectedDoor:SetDamageTime( time )

            BBD.PreBreachSolidity[ connectedDoor ] = connectedDoor:GetSolid()
        end
    end

    BBD.PreBreachSolidity[ door ] = door:GetSolid()

    local isPropBreach = conVarBreakHinges:GetBool()

    -- Spawn a prop door amd hide the original door (Prop-Breach)
    if isPropBreach then
        BBD.PropBreachDoor( door, dmg )

        if BBD.DoorHasConnections( door ) then
            for _, connectedDoor in pairs( connectedDoors ) do
                BBD.PropBreachDoor( connectedDoor, dmg )
            end
        end

    else -- Open the door without spawning a prop (Open-Breach)
        BBD.OpenBreachDoor( door, dmg )

        if BBD.DoorHasConnections( door ) then
            for _, connectedDoor in pairs( connectedDoors ) do
                BBD.OpenBreachDoor( connectedDoor, dmg )
            end
        end
    end

    -- Door respawn timer
    timer.Simple( conVarRespawnTime:GetFloat(), function()
        BBD.RespawnDoor( door, isPropBreach )

        if BBD.DoorHasConnections( door ) then
            for _, connectedDoor in pairs( connectedDoors ) do
                BBD.RespawnDoor( connectedDoor, isPropBreach )
            end
        end
    end )
end

--#endregion Door Breach Logic

--#region Door Damage Logic


-- Determines the direction a door should open based on the damage force applied to it.
---@param door BBD.Door Door to check
---@param dmg CTakeDamageInfo|Vector Damage dealt to the door, or the force of the damage as a vector
---@return BBD.OPEN_DIRECTION # The direction the door should open
BBD.GetDoorOpenDirection = function( door, dmg )
    local damageForce = dmg
    if dmg.GetDamageForce then
        damageForce = dmg:GetDamageForce()
    end

    return damageForce:Dot( door:GetForward() ) > 0 and BBD.OPEN_DIRECTION_FORWARD or BBD.OPEN_DIRECTION_BACKWARD
end

-- Called when an entity takes damage while door breaching is enabled.
---@param door BBD.Door Entity that took damage
---@param dmg CTakeDamageInfo Damage dealt
BBD.OnDoorDamaged = function( door, dmg )
    if not door or not IsValid( door ) then return end
    if door:GetClass() ~= "prop_door_rotating" then return end

    local damageToTake = dmg:GetDamage()

    -- Ignore damage below the threshold
    if damageToTake < conVarDamageMin:GetFloat() then return end

    -- Cap damage at the maximum threshold
    local maxDamage = conVarDamageMax:GetFloat()
    if maxDamage > 0 then
        damageToTake = math.min( damageToTake, maxDamage )
    end

    local oldHealth = door:GetHealthAfterLastDamage()

    -- Don't damage doors that are already breached
    if oldHealth <= 0 then return end

    -- Don't damage doors that haven't yet become solid
    if door:GetIsDoorSolidifying() then return end

    -- Double doors
    if BBD.DoorHasConnections( door ) then
        -- Double doors don't take damage when open
        local doorState = door:GetInternalVariable( "m_eDoorState" )
        if doorState == 2 then -- 2 corresponds to DOOR_STATE_OPEN
            return
        end

        -- Double doors don't take damage when any connected door is non-solid
        for _, otherDoor in pairs( BBD.GetConnectedDoors( door ) ) do
            if otherDoor:GetIsDoorSolidifying() then return end
        end
    end

    local damgePos = dmg:GetDamagePosition()

    -- Apply the handle damage multiplier
    local isHandleDamage = false
    local isBaseGameDoor = door:GetBodygroupCount( 1 ) == 3 and door:GetBodygroupName( 1 ) == "handle01" -- Probably a better way to do this
    if isBaseGameDoor then
        local activeHandleSubModelId = door:GetBodygroup( 1 )

        -- Doors without handles aren't supposed to be openable by players
        if activeHandleSubModelId == 0 then return end

        -- Apply the handle damage multiplier if the handle was hit
        local handlePos = door:GetBonePosition( 1 )
        if damgePos:Distance( handlePos ) <= BBD.HandleHitboxRadius then
            damageToTake = damageToTake * conVarHandleMultiplier:GetFloat()
            isHandleDamage = true
        end
    else
        local handleBone = door:LookupBone( "handle" )
        if handleBone then
            local handlePos = door:GetBonePosition( handleBone )

            -- Apparently the bone position can be the entity's position if the bone cache is empty
            if handlePos == door:GetPos() then
                handlePos = door:GetBoneMatrix( handleBone ):GetTranslation()
            end

            -- Apply the handle damage multiplier if the handle was hit
            if damgePos:Distance( handlePos ) <= BBD.HandleHitboxRadius then
                damageToTake = damageToTake * conVarHandleMultiplier:GetFloat()
                isHandleDamage = true
            end
        end
    end

    local time = CurTime()

    -- Apply health regeneration
    local regenStartTime = door:GetDamageTime() + conVarHealthRegenDelay:GetFloat()
    local secondsSinceRegenStart = time - regenStartTime
    local healthWithRegen = oldHealth
    if secondsSinceRegenStart > 0 then
        local healthToRegen = conVarHealthRegenRate:GetFloat() * secondsSinceRegenStart
        healthWithRegen = math.min( oldHealth + healthToRegen, conVarMaxHealth:GetFloat() )
    end

    -- Apply damage
    local healthAfterDamage = healthWithRegen - damageToTake

    -- Update the door's Data Table Network Variables
    door:SetIsHandleDamage( isHandleDamage )
    door:SetHealthAfterLastDamage( healthAfterDamage )
    door:SetDamageTime( time )
    door:SetDamageDirection( BBD.GetDoorOpenDirection( door, dmg ) )

    if healthAfterDamage <= 0 then
        BBD.OnDoorBreached( door, dmg )
    else
        BBD.PlayDamageSound( door )
    end
end

--#endregion Door Damage Logic

BBD.UpdateMaxHealths = function( _, oldMaxHealth, newMaxHealth )
    for _, door in pairs( ents.FindByClass( "prop_door_rotating" ) ) do
        if not IsValid( door ) then continue end

        local oldHealth = door:GetHealthAfterLastDamage()
        local wasMaxHealth = oldHealth == tonumber( oldMaxHealth )

        -- Purely for variable name clarity
        local newHealth = oldHealth

        -- Keep full-health doors at full health
        if wasMaxHealth then
            newHealth = newMaxHealth
        end

        -- Don't let doors have more health than the new max
        newHealth = math.min( newHealth, tonumber( newMaxHealth ) )

        door:SetHealthAfterLastDamage( newHealth )
    end
end

BBD.OnDoorUsed = function( ply, door )
    if not door or not IsValid( door ) then return end
    if door:GetClass() ~= "prop_door_rotating" then return end

    -- If the door is breached, don't allow interaction
    if door:GetHealthAfterLastDamage() <= 0 then
        return false
    end

    -- If any connected doors are breached, don't allow interaction
    if BBD.DoorHasConnections( door ) then
        for _, connectedDoor in pairs( BBD.GetConnectedDoors( door ) ) do
            if not IsValid( connectedDoor ) then continue end

            if connectedDoor:GetHealthAfterLastDamage() <= 0 then
                return false
            end
        end
    end
end

local hotloaded = false
if BBD.Enable then hotloaded = true BBD.Disable() end

-- Enable the door breach system
BBD.Enable = function()
    -- Tracking door damage
    hook.Add( "EntityTakeDamage", BBD.HOOK_DAMAGE_DETECTION, BBD.OnDoorDamaged )

    -- Check for player's colliding with respawning doors
    hook.Add( "Think", BBD.HOOK_CHECK_COLLISIONS, BBD.CheckPlayerCollisions )

    -- Don't allow players to use breached doors
    hook.Add( "PlayerUse", BBD.HOOK_SUPPRESS_USE, BBD.OnDoorUsed )

    -- Update the max health of all doors when the ConVar changes
    cvars.AddChangeCallback( conVarMaxHealth:GetName(), BBD.UpdateMaxHealths, BBD.CONVAR_CALLBACK_HEALTH )

    -- Ensure all doors are marked as usable to DarkRP's prop protection system
    -- Otherwise, the PlayerUse hook will not be called
    for _, door in pairs( ents.FindByClass( "prop_door_rotating" ) ) do
        door.PlayerUse = true
    end
end

-- Disable the door breach system
BBD.Disable = function()
    hook.Remove( "EntityTakeDamage", BBD.HOOK_DAMAGE_DETECTION )
    hook.Remove( "Think", BBD.HOOK_CHECK_COLLISIONS )
    hook.Remove( "PlayerUse", BBD.HOOK_SUPPRESS_USE )

    cvars.RemoveChangeCallback( conVarMaxHealth:GetName(), BBD.CONVAR_CALLBACK_HEALTH )

    for _, door in pairs( ents.FindByClass( "prop_door_rotating" ) ) do
        door.PlayerUse = nil
    end
end

-- Enable the system when the map loads
hook.Add( "InitPostEntity", BBD.HOOK_ENABLE, function()
    if conVarEnabled:GetBool() then BBD.Enable() end
end )

-- Enable or disable the system when the ConVar changes
cvars.AddChangeCallback( conVarEnabled:GetName(), function( _, oldValue, newValue )
    if newValue == "1" then BBD.Enable() else BBD.Disable() end
end )

if hotloaded then BBD.Enable() end