-- Indexed by door entity, value is the time the door was breached
local doorBreachTimes = {}
local doorHandleDamageTimes = {}
local doorDamageTimes = {}
local doorDamageDirections = {}
local doorHealthPercentages = {}

local handleAnimationDuration = 0.75

local doorDamageAnimationDuration = 0.05
local doorDamageRattleDistance = 2

local VECTOR_ZERO = Vector( 0, 0, 0 )
local ANGLE_ZERO = Angle( 0, 0, 0 )

local ease_outElastic = math.ease.OutElastic
local lerpAngle = LerpAngle
local lerpVector = LerpVector
local math_min = math.min
local pi = math.pi

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
    local damageDirection = net.ReadInt( 3 )
    local healthPercent = net.ReadFloat()
    local isHandleDamage = net.ReadBool()

    if isHandleDamage then
        doorHandleDamageTimes[door] = CurTime()
    else
        doorDamageTimes[door] = CurTime()
    end

    doorDamageDirections[door] = damageDirection
    doorHealthPercentages[door] = healthPercent
end )

net.Receive( "A1_DoorBreach_OnDoorHandleDamaged", function()
    local door = net.ReadEntity()

    doorHandleDamageTimes[door] = CurTime()
end )

local function AnimateBrokenHandles( time )
    for door, breachTime in pairs( doorBreachTimes ) do
        local animationProgress = math_min( ( time - breachTime ) / handleAnimationDuration, 1 )

        local handleAngle = lerpAngle( ease_outElastic( animationProgress ), ANGLE_ZERO, BBD_BROKEN_HANDLE_ANGLE )
        local pushbarAngle = lerpAngle( ease_outElastic( animationProgress ), ANGLE_ZERO, BBD_BROKEN_PUSHBAR_ANGLE )

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
        ---@cast door Entity
        ---@cast damageTime number
        
        local healthPercent = 1 - doorHealthPercentages[door]

        -- Animation progress from 0 to 1
        local animationProgress = math_min( ( time - damageTime ) / doorDamageAnimationDuration, 1 )
        -- Animation progress remapped from -0.25 to 1 and back to -0.25
        local reboundingProgress = ( 0.5 + math.sin( animationProgress * 2 * pi + pi / 2 ) / 2 ) * 1.25 + 0.25

        ---@type Vector?
        local doorPosOffset = lerpVector(
            reboundingProgress,
            door:GetForward() * doorDamageRattleDistance, -- The door's position offset when the animation is at its peak
            VECTOR_ZERO                                     -- The door's position offset when the animation is at its start and end
        )
        * -doorDamageDirections[door]
        * healthPercent

        -- If the animation is done
        if animationProgress >= 1 then
            doorDamageTimes[door] = nil
            doorDamageDirections[door] = nil

            -- Remove render origin override
            door:SetRenderOrigin( nil )
        else

            door:SetRenderOrigin( nil )
            local pos = door:GetPos()

            door:SetRenderOrigin( pos + doorPosOffset )
        end
    end
end

hook.Add( "Think", "A1_DoorBreach_AnimateDoors", function()
    local time = CurTime()

    AnimateBrokenHandles( time )
    AnimateDamage( time )
end )