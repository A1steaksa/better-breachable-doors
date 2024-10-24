# Door Breaching Task Tracking

**Legend:**  
🟢 - Complete  
🟠 - Contains open items  
🔴 - Open Item

## Features

* 🟢 All Doors
    * 🟢 Health Regeneration
        * Health regeneration is now applied during damage calculation
    * 🟢 Minimum damage threshold
    * 🟢 Maximum damage threshold
* 🟢 Prop-Breaching
    * 🟢 Prop door velocity
* 🟢 Open-Breaching

## Bugs

* 🟢 All Doors
    * 🟢 All Doors
        * 🟢 Door didn't animate properly when respawning and appears to be disconnected from its serverside position
            * Doors weren't being told to animate on respawn.  They are, now.
        * 🟢 Some doors don't play play sounds
            * Sound was being emitted from behind the door, not the center of it.
        * 🟢 Doors aren't playing respawn sounds
            * The logic to play them was removed at some point and never properly replaced
        * 🟢 When attacked after not receiving damage for a while, doors freak out
            * It's definitely something to do with the animations
            * The issue stemmed from health regen not being networked to the Client. When doors took damage, the new health might be higher than the old health because it regenerated, but it did still take damage.  
              The fix is to calculate door health, including regen, on the Client and use that calculated health to determine how much damage the door took.
            
* 🟢 Prop-Breaching Doors
    * 🟢 All Doors
        * 🟢 One door is facing the wrong direction after respawn
            * Removed RespawnDirection table and rely on DamageDirection NetworkVar
        * 🟢 Doors that are not blocked are still briefly made non-solid when respawning
            * Check for collisions before respawning and only make non-solid if players are actually in the way
        * 🟢 In DarkRP, Doors are usable after being breached
            * Falco's Prop Protection returns a value to the PlayerUse hook for engine entities by default
            Setting the `PlayerUse` key to `true` on every `prop_door_rotating`'s table tells FPP to allow use.
    * 🟢 Double Doors
        * ❔ When respawning, one of the doors does not properly check for player collisions
            * Can not reproduce.  May have been fixed by something else?
    * 🟢 Single Doors
        * 🟢 Doors don't close correctly after being prop-breached
            * Adding an `ENT:NextThink()` of `CurTime` seems to fix the issue.  Not sure why it was happening.

* 🟢 Open-Breaching Doors
    * 🟢 All Doors
        * 🟢 Open-Breached doors don't roll in the right direction
            * Apparently the door open direction enums got set to 1 and 2 instead of -1 and 1
        * 🟢 Open-breached doors shouldn't become non-solid when respawning
            * Only trigger non-solid respawning when the door has a valid prop door 
        * 🟢 Open-breached doors don't always animate when breached
            * The case where the Client's `CurTime` was ahead of the Server's, it was stopping further animation.  The fix is to not animate that frame, but try again next frame.
        * 🟢 Doors do not respawn as solid
            * Seems to be the second time they respawn that has the issue
    * 🟢 Double Doors
        * 🟢 In DarkrP, double doors sometimes rotate the wrong direction when +use'd
            * DarkRP overrides `ENT:SetAngles` to prevent crashes, apparently.
            The bandaid fix is to check if the entity has a parent and, if it doesn't, use `ENT:SetLocalAngles` instead.
    * 🟢 Single Doors