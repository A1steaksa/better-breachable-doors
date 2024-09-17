--Whether or not it's enabled
CreateConVar( "doorbreach_enabled", 1 )

--Starting health for doors
CreateConVar( "doorbreach_health", 100 )

--Damage multiplier for handle shots
CreateConVar( "doorbreach_handlemultiplier", 2 )

--Time, in seconds, to wait before respawning the door
CreateConVar( "doorbreach_respawntime", 30 )

--When spawning a prop door, this is the scale its damage velocity should be set at
CreateConVar( "doorbreach_velocitymultiplier", 1.5 )

--Max distance from the handle to still count as a handle shot
local maxHandleDistance = 5

--Classname for doors
local entityType = "prop_door_rotating"

--Handles breaking doors down
hook.Add( "EntityTakeDamage", "DoorBreachDamageDetection", function( ent, dmg )
	if not IsValid( ent ) then return end
	
	if not GetConVar( "doorbreach_enabled" ):GetBool() then return end
	
	--If it's a door that has been damaged
	if ( ent:GetClass() == entityType ) then
	
		--If this door hasn't been set up yet, set it up.
		if not ent.DoorBreachHealth then 
			ent.DoorBreachHealth = GetConVar( "doorbreach_health"):GetFloat()
		end
	
		-- and if it hasn't been breached already
		if ( not ent.DoorBreachExploded ) then
			
			--Store the damage here so it can be modified by the handle code later
			local dam = dmg:GetDamage()
			
			--Stores where the damage hit
			local damPos = dmg:GetDamagePosition()
			
			--Stores the position of the handle if it exists
			local bone = ent:LookupBone( "handle" )
			if ( bone ) then
				local handlePos = ent:GetBonePosition( bone )
			
				--If the damage is happening near the handle, multiply the damage
				if handlePos:Distance( damPos ) <= maxHandleDistance then
					dam = dam * GetConVar( "doorbreach_handlemultiplier"):GetFloat()
				end
			
			end
			
			
			--Apply damage to the door
			ent.DoorBreachHealth = ent.DoorBreachHealth - dam
			
			--If the door has died
			if ent.DoorBreachHealth <= 0 then
				
				--Set it as having died
				ent.DoorBreachExploded = true
				
				--Set the door to be, as far as the player knows, non-existant
				ent:SetNotSolid( true )
				ent:SetNoDraw( true )
				
				--Create the fake, exploded "prop door" and make sure it matches the original door as closely as possible
				local propDoor = ents.Create( "prop_physics" )
				propDoor:SetModel( ent:GetModel() )
				propDoor:SetMaterial( ent:GetMaterial() )
				propDoor:SetColor( ent:GetColor() )
				propDoor:SetPos( ent:GetPos() )
				propDoor:SetAngles( ent:GetAngles() )
				propDoor:SetSkin( ent:GetSkin() )
				
				--Ensures that the handle on the prop door is the same as the one on the real door
				local bodyGroupID = ent:FindBodygroupByName( "handle01" )
				propDoor:SetBodygroup( bodyGroupID, ent:GetBodygroup( bodyGroupID ) )
				
				propDoor:Spawn()
				
				--Unlock the door
				ent:Fire("unlock", "", 0)
				
				--Set the door's velocity on the prop door like it was the original door
				local damageForce = dmg:GetDamageForce() * GetConVar( "doorbreach_velocitymultiplier"):GetFloat()
				propDoor:GetPhysicsObject():ApplyForceOffset( damageForce, dmg:GetDamagePosition() )
				
				--Set a timer to respawn the door after the appropriate time
				timer.Simple( GetConVar( "doorbreach_respawntime"):GetFloat(), function()
					if not IsValid( ent ) then return end
						
					--Start sending information to players again
					for k,v in pairs( player.GetAll() ) do
						ent:SetPreventTransmit( v, false )
					end
				
					--Set the door to alive
					ent.DoorBreachExploded = nil
					
					--Reset the door's health
					ent.DoorBreachHealth = GetConVar( "doorbreach_health"):GetFloat()
					
					--"respawn" the door by resetting it to it's standard values
					ent:SetNotSolid( false )
					ent:SetNoDraw( false )
					
					--If it exists, remove the prop door
					if IsValid( propDoor ) then
						propDoor:Remove()
					end
					
				end)
			end
		end
	end
end)

--Handles players trying to use breached doors
hook.Add( "PlayerUse", "DoorBreachSuppressUse", function( ply, ent )
	if not IsValid( ent ) then return end
	
	--If the door has been destroyed already, stop the player from trying to open or close it
	if ent.DoorBreachExploded then
		return false
	end
end)