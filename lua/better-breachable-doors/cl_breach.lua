local doorsToAnimate = {}

local handleAnimationDuration = 0.75

local doorDamageAnimationDuration = 0.05
local doorDamageRattleDistance = 5

local VECTOR_ZERO = Vector( 0, 0, 0 )
local ANGLE_ZERO = Angle( 0, 0, 0 )

local ease_outElastic = math.ease.OutElastic
local lerpAngle = LerpAngle
local lerpVector = LerpVector
local math_min = math.min
local pi = math.pi

local function AnimateBrokenHandles( time )
    for door, _ in pairs( doorsToAnimate ) do
        local animationProgress = math_min( ( time - door:GetDamageTime() ) / handleAnimationDuration, 1 )

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

    for door, _ in pairs( doorsToAnimate ) do
        ---@cast door Entity

        -- Animation progress from 0 to 1
        local animationProgress = math_min( ( time - door:GetDamageTime() ) / doorDamageAnimationDuration, 1 )
        -- Animation progress remapped from -0.25 to 1 and back to -0.25
        local reboundingProgress = ( 0.5 + math.sin( animationProgress * 2 * pi + pi / 2 ) / 2 ) * 1.25 + 0.25

        local doorAngleOffset = lerpAngle(
            reboundingProgress,
            Angle( 0, 5, 0 ), -- The door's angle offset when the animation is at its peak
            ANGLE_ZERO        -- The door's angle offset when the animation is at its start and end
        )
        * -door:GetDamageDirection()

        -- If the animation is done
        if animationProgress >= 1 then
            doorsToAnimate[door] = nil

            -- Remove renderer overrides
            door:SetRenderOrigin( nil )
            door:SetRenderAngles( nil )
        else

            door:SetRenderAngles( nil )
            local angles = door:GetAngles()
            door:SetRenderAngles( angles + doorAngleOffset )

        end
    end
end

hook.Add( "Think", BBD_HOOK_ANIMATE_DOORS, function()
    local time = CurTime()

hook.Remove( "NotifyShouldTransmit", BBD_HOOK_CHANGE_PVS )
hook.Add( "NotifyShouldTransmit", BBD_HOOK_CHANGE_PVS, function( ent, shouldTransmit )
    if not ent or not IsValid( ent ) then return end
    if ent:GetClass() ~= "prop_door_rotating" then return end
    if not shouldTransmit then return end

    -- As doors enter the PVS, mark them for animation
    -- If they don't actually need to animate, they will be quickly removed from the list
    doorsToAnimate[ent] = true
end )
    doorsToAnimate[door] = true
end

hook.Add( "PostDoorCreated", BBD_HOOK_SETUP_CALLBACKS, function( door )
    door:NetworkVarNotify( "DamageTime", HandleDamageCallback )
end )