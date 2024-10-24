-- Shared global variable to store the Better Breachable Doors library.
BBD = _G.BBD or {}

--#region Classes

---@class BBD.Door : Entity
---@field GetDamageTime fun( self: BBD.Door ): number Get the time, relative to CurTime, when the door was last damaged.
---@field SetDamageTime fun( self: BBD.Door, time: number ) Set the time, relative to CurTime, when the door was last damaged.
---@field GetIsHandleDamage fun( self: BBD.Door ): boolean Get whether the door's handle was damaged.
---@field SetIsHandleDamage fun( self: BBD.Door, isHandleDamage: boolean ) Set whether the door's handle was damaged.
---@field GetIsDoorSolidifying fun( self: BBD.Door ): boolean Get whether the door is in the process of respawning but is not yet able to be made solid due to a player being in the way.
---@field SetIsDoorSolidifying fun( self: BBD.Door, isSolidifying: boolean ) Set whether the door is in the process of respawning but is not yet able to be made solid due to a player being in the way.
---@field GetDamageDirection fun( self: BBD.Door ): BBD.OPEN_DIRECTION Get the direction of the damage dealt to the door.
---@field SetDamageDirection fun( self: BBD.Door, direction: BBD.OPEN_DIRECTION ) Set the direction of the damage dealt to the door.
---@field GetHealthAfterLastDamage fun( self: BBD.Door ): number Get the door's health after the last time it was damaged.
---@field SetHealthAfterLastDamage fun( self: BBD.Door, health: number ) Set the door's health after the last time it was damaged.
---@field GetPropDoor fun( self: BBD.Door ): Entity Get the prop door spawned when the door was breached.
---@field SetPropDoor fun( self: BBD.Door, propDoor: Entity ) Set the prop door spawned when the door was breached.
---@field RenderOverride fun( self: BBD.Door, flags: number ) Override for rendering the door.  This function is called every frame until the door is done animating.

--#endregion Classes

--#region Constants

-- Amount, in degrees, to tilt the door forward when it's been breached
BBD.BreachedDoorTiltAmount  = 1.5

-- Amount, in degrees, to roll the door sideways when it's been breached
BBD.BreachedDoorRollAmount = 1.5

-- How large the handle hitbox's radius should be
BBD.HandleHitboxRadius = 5

-- How large prop door collisions should be scaled to when they're created
BBD.PropCollisionScale = 0.95

--#endregion Constants

--#region Enums

---@alias BBD.OPEN_DIRECTION
---| `BBD.OPEN_DIRECTION_FORWARD`
---| `BBD.OPEN_DIRECTION_BACKWARD`
BBD.OPEN_DIRECTION_FORWARD  = -1 -- Forward relative to the door.
BBD.OPEN_DIRECTION_BACKWARD =  1 -- Backward relative to the door.

--#endregion Enums

--#region ConVars, Hooks, and Callbacks

-- Identifier Prefixes
BBD.PREFIX_CONVAR   = "doorbreach_"
BBD.PREFIX_HOOK     = "A1_DoorBreach_"
BBD.PREFIX_CALLBACK = "A1_DoorBreach_"

-- Convar Names
BBD.CONVAR_ENABLED            = BBD.PREFIX_CONVAR .. "enabled"
BBD.CONVAR_HEALTH_MAX         = BBD.PREFIX_CONVAR .. "health_max"
BBD.CONVAR_HEALTH_REGEN_DELAY = BBD.PREFIX_CONVAR .. "health_regen_delay"
BBD.CONVAR_HEALTH_REGEN_RATE  = BBD.PREFIX_CONVAR .. "health_regen_rate"
BBD.CONVAR_UNLOCK             = BBD.PREFIX_CONVAR .. "unlock"
BBD.CONVAR_BREAK_HINGES       = BBD.PREFIX_CONVAR .. "break_hinges"
BBD.CONVAR_HANDLE_MULTIPLIER  = BBD.PREFIX_CONVAR .. "handle_multiplier"
BBD.CONVAR_SPEED              = BBD.PREFIX_CONVAR .. "speed"
BBD.CONVAR_EXPLOSIVE_SPEED    = BBD.PREFIX_CONVAR .. "explosive_speed"
BBD.CONVAR_RESPAWNTIME        = BBD.PREFIX_CONVAR .. "respawntime"
BBD.CONVAR_DAMAGE_MIN         = BBD.PREFIX_CONVAR .. "damage_min"
BBD.CONVAR_DAMAGE_MAX         = BBD.PREFIX_CONVAR .. "damage_max"

-- Convars
local flags = {FCVAR_ARCHIVE,FCVAR_REPLICATED}
CreateConVar( BBD.CONVAR_ENABLED,             "1",    flags, "Enable or disable the door breach system.", 0, 1 )
CreateConVar( BBD.CONVAR_HEALTH_MAX,          "100",  flags, "The maximum health for doors.", 1 )
CreateConVar( BBD.CONVAR_HEALTH_REGEN_DELAY,  "5",    flags, "Time, in seconds, before a door starts regenerating health after being damaged.", 0 )
CreateConVar( BBD.CONVAR_HEALTH_REGEN_RATE,   "10",   flags, "Rate, in health per second, at which doors regenerate health after being damaged.  Set to 0 to disable health regen.", 0 )
CreateConVar( BBD.CONVAR_UNLOCK,              "1",    flags, "Set to 1 to unlock doors when breached.", 0, 1 )
CreateConVar( BBD.CONVAR_BREAK_HINGES,        "1",    flags, "Set to 1 to break doors off of their hinges and turn them into a physics prop when breached, or set to 0 to instead violently force doors to open.", 0, 1 )
CreateConVar( BBD.CONVAR_HANDLE_MULTIPLIER,   "1.5",  flags, "Multiplier for damage dealt to a door's handle.", 0 )
CreateConVar( BBD.CONVAR_SPEED,               "500",  flags, "Speed, in degrees per second, at which doors open when breached by bullets or impacts.", 0 )
CreateConVar( BBD.CONVAR_EXPLOSIVE_SPEED,     "1000", flags, "Speed, in degrees per second, at which doors open when breached by explosives.", 0 )
CreateConVar( BBD.CONVAR_RESPAWNTIME,         "30",   flags, "Time, in seconds, before the prop door is removed.", 0 )
CreateConVar( BBD.CONVAR_DAMAGE_MIN,          "0",    flags, "Any damage dealt below this amount will be ignored. Set to 0 to disable.", 0 )
CreateConVar( BBD.CONVAR_DAMAGE_MAX,          "0",    flags, "All damage dealt will be capped at this maximum amount.  Set to 0 to disable.", 0 )

-- Hook IDs
BBD.HOOK_SETUP_DATATABLES     = BBD.PREFIX_HOOK .. "SetupDataTables"
BBD.HOOK_ENABLE               = BBD.PREFIX_HOOK .. "Enable"

hook.Add( "OnEntityCreated", BBD.HOOK_SETUP_DATATABLES, function( ent )
    if ent:GetClass() ~= "prop_door_rotating" then return end

    -- Manually install data tables because engine entities don't get them by default
    ent:InstallDataTable()

    ent:NetworkVar( "Float",    "DamageTime" )
    ent:NetworkVar( "Bool",     "IsHandleDamage" )
    ent:NetworkVar( "Bool",     "IsDoorSolidifying" )
    ent:NetworkVar( "Int",      "DamageDirection" )
    ent:NetworkVar( "Float",    "HealthAfterLastDamage" )
    ent:NetworkVar( "Entity",   "PropDoor" )

    if SERVER then
        ent:SetHealthAfterLastDamage( GetConVar( BBD.CONVAR_HEALTH_MAX ):GetFloat() )
        ent:SetDamageTime( -1 )
    end

    if CLIENT then
        hook.Run( "PostDoorCreated", ent )
    end
end )

if SERVER then
    AddCSLuaFile( "better-breachable-doors/cl_breach.lua" )

    -- Hook IDs
    BBD.HOOK_DAMAGE_DETECTION       = BBD.PREFIX_HOOK .. "DamageDetection"
    BBD.HOOK_SUPPRESS_USE           = BBD.PREFIX_HOOK .. "SuppressUse"
    BBD.HOOK_CHECK_COLLISIONS       = BBD.PREFIX_HOOK .. "CheckPlayerCollisions"

    -- Convar Callback IDs
    BBD.CONVAR_CALLBACK_HEALTH      = BBD.PREFIX_HOOK .. "Health"

    include( "better-breachable-doors/sv_breach.lua" )
end

if CLIENT then
    -- Hook IDs
    BBD.HOOK_ANIMATE_DOORS          = BBD.PREFIX_HOOK .. "AnimateDoors"
    BBD.HOOK_CHANGE_PVS             = BBD.PREFIX_HOOK .. "ChangePVS"
    BBD.HOOK_PROP_REMOVAL           = BBD.PREFIX_HOOK .. "PropRemoval"

    include( "better-breachable-doors/cl_breach.lua" )
end

--#endregion ConVars, Hooks, and Callbacks