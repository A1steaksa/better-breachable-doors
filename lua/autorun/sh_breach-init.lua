---@alias DOOR_DIRECTION
---| `DOOR_DIRECTION_FORWARD`
---| `DOOR_DIRECTION_BACKWARD`
DOOR_DIRECTION_FORWARD = 1 -- Forward relative to the door's orientation.
DOOR_DIRECTION_BACKWARD = 2 -- Backward relative to the door's orientation.

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

local ID_PREFIX = "A1_DoorBreach_"

-- Hook IDs
BBD_HOOK_SETUP_DATATABLES       = ID_PREFIX .. "SetupDataTables"

CreateConVar( "doorbreach_enabled",       "1",    {FCVAR_ARCHIVE,FCVAR_REPLICATED}, "Enable or disable the door breach system.", 0, 1 )
CreateConVar( "doorbreach_health",        "100",  {FCVAR_ARCHIVE,FCVAR_REPLICATED}, "Starting health for doors.", 1 )
CreateConVar( "doorbreach_unlock",        "1",    {FCVAR_ARCHIVE,FCVAR_REPLICATED}, "Enable or disable locked doors becoming unlocked when breached.", 0, 1 )
CreateConVar( "doorbreach_open",          "1",    {FCVAR_ARCHIVE,FCVAR_REPLICATED}, "Enable or disable doors opening when breached.", 0, 1 )
CreateConVar( "doorbreach_speed",         "500",  {FCVAR_ARCHIVE,FCVAR_REPLICATED}, "Speed, in degrees per second, at which doors open when breached.", 0 )
CreateConVar( "doorbreach_respawntime",   "30",   {FCVAR_ARCHIVE,FCVAR_REPLICATED}, "Time, in seconds, before the prop door is removed.", 0 )

if SERVER then
    AddCSLuaFile( "better-breachable-doors/cl_breach.lua" )

    -- Hook IDs
    BBD_HOOK_SEND_DAMAGE        = ID_PREFIX .. "SendAggregatedDamage"
    BBD_HOOK_DAMAGE_DETECTION   = ID_PREFIX .. "DamageDetection"
    BBD_HOOK_SETUP              = ID_PREFIX .. "Setup"
    BBD_HOOK_SUPPRESS_USE       = ID_PREFIX .. "SuppressUse"

    include( "better-breachable-doors/sv_breach.lua" )
end

if CLIENT then
    -- Hook IDs
    BBD_HOOK_ANIMATE_DOORS      = ID_PREFIX .. "AnimateDoors"
    BBD_HOOK_SETUP_CALLBACKS    = ID_PREFIX .. "SetupCallbacks"
    BBD_HOOK_CHANGE_PVS         = ID_PREFIX .. "ChangePVS"

    include( "better-breachable-doors/cl_breach.lua" )
end

hook.Add( "OnEntityCreated", BBD_HOOK_SETUP_DATATABLES, function( ent )
    if ent:GetClass() ~= "prop_door_rotating" then return end
    ent:InstallDataTable()

    ent:NetworkVar( "Float", "DamageTime" )
    ent:NetworkVar( "Int", "DamageDirection" )
    ent:NetworkVar( "Float", "HealthAfterLastDamage" )

    if SERVER then
        local startingHealth = GetConVar( "doorbreach_health" ):GetFloat()
        ent:SetHealthAfterLastDamage( startingHealth )
    end

    if CLIENT then
        hook.Run( "PostDoorCreated", ent )
    end
end )