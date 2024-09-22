-- Indexed by door entity, value is the time the door was breached
local doorBreachTimes = {}
local doorHandleDamageTimes = {}
local doorDamageTimes = {}

local handleAnimationDuration = 0.75

local ANGLE_ZERO = Angle( 0, 0, 0 )

local ease = math.ease.OutElastic
local lerpAngle = LerpAngle
local math_min = math.min

net.Receive( "A1_DoorBreach_OnDoorBreached", function()
    local door = net.ReadEntity()

    doorBreachTimes[door] = CurTime()
end )

net.Receive( "A1_DoorBreach_OnDoorRespawned", function()
    local door = net.ReadEntity()

    doorBreachTimes[door] = nil
end )

net.Receive( "A1_DoorBreach_OnDoorDamaged", function()
    local door = net.ReadEntity()

    doorDamageTimes[door] = CurTime()
end )

net.Receive( "A1_DoorBreach_OnDoorHandleDamaged", function()
    local door = net.ReadEntity()

    doorHandleDamageTimes[door] = CurTime()
end )

local function AnimateHandles( time )
    for door, breachTime in pairs( doorBreachTimes ) do
        local animationProgress = math_min( ( time - breachTime ) / handleAnimationDuration, 1 )

        local handleAngle = lerpAngle( ease( animationProgress ), ANGLE_ZERO, BBD_BROKEN_HANDLE_ANGLE )
        local pushbarAngle = lerpAngle( ease( animationProgress ), ANGLE_ZERO, BBD_BROKEN_PUSHBAR_ANGLE )

        local handleBone = door:LookupBone( "handle" )
        if handleBone then
            door:ManipulateBoneAngles( handleBone, handleAngle )
        end
        local pushbarBone = door:LookupBone( "handle02" )
        if pushbarBone then
            door:ManipulateBoneAngles( pushbarBone, pushbarAngle )
        end
    end
end

local function AnimateDamage( time )
    for door, damageTime in pairs( doorDamageTimes ) do
        local animationProgress = math_min( ( time - damageTime ) / handleAnimationDuration, 1 )

        local damageAngle = lerpAngle( ease( animationProgress ), ANGLE_ZERO, BBD_BROKEN_HANDLE_ANGLE )

        if animationProgress >= 1 then
            doorDamageTimes[door] = nil
        end

        door:RenderAngles( damageAngle )
    end
end

hook.Add( "Think", "A1_DoorBreach_AnimateDoors", function()
    local time = CurTime()

    AnimateHandles( time )
    AnimateDamage( time )
end )