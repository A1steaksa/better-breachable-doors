-- Shared global variable to store the Better Breachable Doors library.
BBD = BBD or {}

-- Amount, in degrees, to tilt the door forward when it's been breached
BBD.BreachedDoorTiltAmount  = 1.5

-- Amount, in degrees, to roll the door sideways when it's been breached
BBD.BreachedDoorRollAmount = 1.5

-- How large the handle hitbox's radius should be
BBD.HandleHitboxRadius = 5

-- How large prop door collisions should be scaled to when they're created
BBD.PropCollisionScale = 0.95

---@alias DOOR_DIRECTION
---| `DOOR_DIRECTION_FORWARD`
---| `DOOR_DIRECTION_BACKWARD`
DOOR_DIRECTION_FORWARD  = -1 -- Forward relative to the door's orientation.
DOOR_DIRECTION_BACKWARD =  1 -- Backward relative to the door's orientation.

---@alias DOOR_STATE
---| `DOOR_STATE_CLOSED`
---| `DOOR_STATE_OPENING`
---| `DOOR_STATE_OPEN`
---| `DOOR_STATE_CLOSING`
---| `DOOR_STATE_AJAR`
DOOR_STATE_CLOSED     = 0
DOOR_STATE_OPENING    = 1
DOOR_STATE_OPEN       = 2
DOOR_STATE_CLOSING    = 3
DOOR_STATE_AJAR       = 4

---@alias DOOR_FLAG
---| `DOOR_FLAG_START_OPEN`
---| `DOOR_FLAG_START_LOCKED`
---| `DOOR_FLAG_SILENT`
---| `DOOR_FLAG_USE_CLOSES`
---| `DOOR_FLAG_SILENT_NPC`
---| `DOOR_FLAG_IGNORE_USE`
DOOR_FLAG_START_OPEN    = 1
DOOR_FLAG_START_LOCKED  = 2048
DOOR_FLAG_SILENT        = 4096
DOOR_FLAG_USE_CLOSES    = 8192
DOOR_FLAG_SILENT_NPC    = 16384
DOOR_FLAG_IGNORE_USE    = 32768

CreateConVar( "doorbreach_enabled",             "1",    {FCVAR_ARCHIVE,FCVAR_REPLICATED}, "Enable or disable the door breach system.", 0, 1 )
CreateConVar( "doorbreach_health",              "100",  {FCVAR_ARCHIVE,FCVAR_REPLICATED}, "Starting health for doors.", 1 )
CreateConVar( "doorbreach_health_regen_delay",  "5",    {FCVAR_ARCHIVE,FCVAR_REPLICATED}, "Time, in seconds, before a door starts regenerating health after being damaged.", 0 )
CreateConVar( "doorbreach_health_regen_rate",   "10",   {FCVAR_ARCHIVE,FCVAR_REPLICATED}, "Rate, in health per second, at which doors regenerate health after being damaged.  Set to 0 to disable health regen.", 0 )
CreateConVar( "doorbreach_unlock",              "1",    {FCVAR_ARCHIVE,FCVAR_REPLICATED}, "Set to 1 to unlock doors when breached.", 0, 1 )
CreateConVar( "doorbreach_break_hinges",        "1",    {FCVAR_ARCHIVE,FCVAR_REPLICATED}, "Set to 1 to break doors off of their hinges and turn them into a physics prop when breached, or set to 0 to instead violently force doors to open.", 0, 1 )
CreateConVar( "doorbreach_handle_multiplier",   "1.5",  {FCVAR_ARCHIVE,FCVAR_REPLICATED}, "Multiplier for damage dealt to a door's handle.", 0 )
CreateConVar( "doorbreach_speed",               "500",  {FCVAR_ARCHIVE,FCVAR_REPLICATED}, "Speed, in degrees per second, at which doors open when breached by bullets or impacts.", 0 )
CreateConVar( "doorbreach_explosive_speed",     "1000", {FCVAR_ARCHIVE,FCVAR_REPLICATED}, "Speed, in degrees per second, at which doors open when breached by explosives.", 0 )
CreateConVar( "doorbreach_respawntime",         "30",   {FCVAR_ARCHIVE,FCVAR_REPLICATED}, "Time, in seconds, before the prop door is removed.", 0 )
CreateConVar( "doorbreach_damage_min",          "0",   {FCVAR_ARCHIVE,FCVAR_REPLICATED}, "Any damage dealt below this amount will be ignored. Set to 0 to disable.", 0 )
CreateConVar( "doorbreach_damage_max",          "0",  {FCVAR_ARCHIVE,FCVAR_REPLICATED}, "All damage dealt will be capped at this maximum amount.  Set to 0 to disable.", 0 )

local ID_PREFIX = "A1_DoorBreach_"

-- Hook IDs
local BBD_HOOK_SETUP_DATATABLES     = ID_PREFIX .. "SetupDataTables"
BBD_HOOK_ENABLE                     = ID_PREFIX .. "Enable"

hook.Add( "OnEntityCreated", BBD_HOOK_SETUP_DATATABLES, function( ent )
    if ent:GetClass() ~= "prop_door_rotating" then return end

    -- Manually install data tables because engine entities don't get them by default
    ent:InstallDataTable()

    ent:NetworkVar( "Float",    "DamageTime" )
    ent:NetworkVar( "Bool",     "IsHandleDamage" )
    ent:NetworkVar( "Bool",     "IsPropBreachDoorRespawning" )
    ent:NetworkVar( "Int",      "DamageDirection" )
    ent:NetworkVar( "Float",    "HealthAfterLastDamage" )
    ent:NetworkVar( "Entity",   "PropDoor" )

    if SERVER then
        ent:SetHealthAfterLastDamage( GetConVar( "doorbreach_health" ):GetFloat() )
        ent:SetDamageTime( -1 )
    end

    if CLIENT then
        hook.Run( "PostDoorCreated", ent )
    end
end )

if SERVER then
    AddCSLuaFile( "better-breachable-doors/cl_breach.lua" )

    -- Hook IDs
    BBD_HOOK_DAMAGE_DETECTION       = ID_PREFIX .. "DamageDetection"
    BBD_HOOK_SUPPRESS_USE           = ID_PREFIX .. "SuppressUse"
    BBD_HOOK_CHECK_COLLISIONS       = ID_PREFIX .. "CheckPlayerCollisions"

    -- Convar Callback IDs
    BBD_CONVAR_CALLBACK_HEALTH      = ID_PREFIX .. "Health"

    include( "better-breachable-doors/sv_breach.lua" )
end

if CLIENT then
    -- Hook IDs
    BBD_HOOK_ANIMATE_DOORS          = ID_PREFIX .. "AnimateDoors"
    BBD_HOOK_CHANGE_PVS             = ID_PREFIX .. "ChangePVS"
    BBD_HOOK_PROP_REMOVAL           = ID_PREFIX .. "PropRemoval"

    include( "better-breachable-doors/cl_breach.lua" )
end