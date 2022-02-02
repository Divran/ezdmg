AddCSLuaFile()

ezdmg = {}

if SERVER then
	local damaged_ents = {}

	local indestructible_entities = {}
	local function make_indestructible()
		timer.Simple(0,function()
			indestructible_entities = ents.FindByClass( "prop_physics" )
		end)
	end

	hook.Add("InitPostEntity", "ezdmg_init1", make_indestructible)
	hook.Add("PostCleanupMap", "ezdmg_init2", make_indestructible)
	hook.Add("Initialize", "ezdmg_init3", function() timer.Simple(1, make_indestructible) end)

	function ezdmg.init( ent )
		if not IsValid( ent )  then return false end
		if indestructible_entities[ent] then return false end

		if not ent.ezdmg then
			local hp, bullet_resistance, explosive_resistance = ezdmg.getInitial( ent )

			ent.ezdmg = {
				health = hp,
				max_health = hp,
				bullet_resistance = bullet_resistance,
				explosive_resistance = explosive_resistance,
				destroyed = false,
				original_color = ent:GetColor(),
				original_material = ent:GetMaterial()
			}

			damaged_ents[ent] = true
			ent:CallOnRemove(function()
				damaged_ents[ent] = nil
			end)
		end

		return true
	end

	util.AddNetworkString( "ezdmg_damage_report" )
	local count = 0
	local function sendReport( ent, position, damage )
		if count > 50 then return end
		local lpos = ent:WorldToLocal( position )

		net.Start( "ezdmg_damage_report" )
			net.WriteEntity( ent )
			net.WriteFloat( lpos.x )
			net.WriteFloat( lpos.y )
			net.WriteFloat( lpos.z )
			net.WriteInt( damage, 32 )
		net.SendPVS( position )

		count = count + 1
	end
	hook.Add( "Think", "ezdmg_damage_report_antispam", function() count = 0 end)

	function ezdmg.damage( ent, damage, is_explosive, position )
		damage = math.floor(damage)
		if damage == 0 then return end
		if not ezdmg.init( ent ) then return end
		if ent.ezdmg.destroyed then return end

		if is_explosive then
			position = ent:NearestPoint( position )
			damage = damage * ent.ezdmg.explosive_resistance
		else
			damage = damage * ent.ezdmg.bullet_resistance
		end

		damage = math.floor(damage)
		if damage == 0 then return end

		ent.ezdmg.health = math.max(ent.ezdmg.health - damage,0)
		
		local percent = ent.ezdmg.health / ent.ezdmg.max_health
		local r,g,b = ent.ezdmg.original_color.r, ent.ezdmg.original_color.g, ent.ezdmg.original_color.b
		ent:SetColor(Color(r*percent,g*percent,b*percent))

		sendReport( ent, position, damage )

		if ent.ezdmg.health <= 0 then
			ezdmg.destroy( ent )
		end
	end

	function ezdmg.heal( ent, heal, heal_position )
		if not ezdmg.init( ent ) then return end
		if ent.ezdmg.health >= ent.ezdmg.max_health then return end

		ent.ezdmg.health = math.min(ent.ezdmg.health + heal,ent.ezdmg.max_health)

		local percent = ent.ezdmg.health / ent.ezdmg.max_health
		local r,g,b = ent.ezdmg.original_color.r, ent.ezdmg.original_color.g, ent.ezdmg.original_color.b
		ent:SetColor(Color(r*percent,g*percent,b*percent))

		sendReport( ent, heal_position, -heal )

		if ent.ezdmg.destroyed and ent.ezdmg.health >= ent.ezdmg.max_health then
			ent:SetMaterial( ent.ezdmg.original_material )
			ent:SetColor( ent.ezdmg.original_color )
			ent:SetNotSolid( false )

			ent.ezdmg = nil
			damaged_ents[ent] = nil
		end
	end

	concommand.Add( "ezdmg_heal_all", function(ply)
		if not ply:IsAdmin() then return end

		for ent,_ in pairs( damaged_ents ) do
			if ent.ezdmg then
				ezdmg.heal( ent, ent.ezdmg.max_health, ent:GetPos() )
			end
		end
	end)

	local function do_heal( ply )
		local shoot_pos = ply:GetShootPos()
		-- detect range is quite large, because it must detect the center of the prop
		-- and some props can be big
		local entities = ents.FindInSphere( shoot_pos, 1024 )

		for i=1,#entities do
			local ent = entities[i]

			if ent.ezdmg then
				local nearest = ent:NearestPoint( shoot_pos )

				if nearest:Distance( shoot_pos ) < 80 then -- the actual heal distance is here
					local percent = ent.ezdmg.max_health * 0.05 -- 5%
					ezdmg.heal( ent, math.max(percent,50), nearest )
				end
			end
		end
	end

	timer.Remove( "ezdmg_heal_loop" ) -- clear to be sure
	timer.Create( "ezdmg_heal_loop", 0.5, 0, function()
		local plys = player.GetHumans()
		for i=1,#plys do
			if plys[i]:KeyDown( IN_USE ) then
				do_heal( plys[i] )
			end
		end
	end)

	function ezdmg.destroy( ent )
		if not ezdmg.init( ent ) then return end

		ent.ezdmg.destroyed = true

		ent:SetColor(Color(0,0,0))
		ent:SetMaterial("models/wireframe")

		ent:SetNotSolid( true )

		local phys = ent:GetPhysicsObject()
		if IsValid( phys ) then
			phys:EnableMotion( false )
		end
		-- todo
	end

	local armor_types = {
		[MAT_WARPSHIELD] = 0.95,
		[MAT_METAL] = 0.9,
		[MAT_GRATE] = 0.8,
		[MAT_CONCRETE] = 0.7,
		[MAT_TILE] = 0.6,
		[MAT_VENT] = 0.6,
		[MAT_SAND] = 0.6,
		[MAT_WOOD] = 0.55,
		[MAT_DIRT] = 0.5,
		[MAT_GRASS] = 0.5,
		[MAT_PLASTIC] = 0.4,
		[MAT_DEFAULT] = 0.3,
		[MAT_COMPUTER] = 0.2,
		[MAT_ALIENFLESH] = 0.1,
		[MAT_ANTLION] = 0.1,
		[MAT_BLOODYFLESH] = 0.1,
		[MAT_CLIP] = 0.1,
		[MAT_FLESH] = 0.1,
		[MAT_FOLIAGE] = 0.1,
		[MAT_SLOSH] = 0.1,
		[MAT_SNOW] = 0.05,
		[MAT_GLASS] = 0,
		[MAT_EGGSHELL] = -0.4, -- lmao what
	}

	--[[
	local lookup_debug = {}
	for k,v in pairs( _G ) do
		if string.sub( k, 1,4 ) == "MAT_" then
			lookup_debug[v] = k
		end
	end
	concommand.Add( "ezdmg_debug_material_type", function( ply )
		local ent = ply:GetEyeTraceNoCursor().Entity
		if IsValid(ent) and ent.GetMaterialType then
			local mat = ent:GetMaterialType()
			ply:ChatPrint( lookup_debug[mat] .. " (bullet resistance: " .. (armor_types[mat]*100) .. "%)" )
		else
			ply:ChatPrint( "Invalid entity" )
		end
	end)
	]]

	function ezdmg.getInitial( ent )
		local health = 0

		local phys = ent:GetPhysicsObject()
		if IsValid( phys ) then
			health = health + phys:GetVolume() / 400
		end

		local resistance = 1 - (armor_types[ent:GetMaterialType()] or 0.3)

		return math.ceil(health), resistance, resistance * 2
	end
	
	local whitelist = {
		"gmod_wire.*",
		"prop_physics"
	}
	hook.Add( "EntityTakeDamage", "ezdmg", function( target, dmginfo )
		local class = target:GetClass()
		local found = false
		for i=1,#whitelist do
			local str = whitelist[i]

			if string.match( class, str ) ~= nil then found = true end
		end
		if not found then return end

		ezdmg.damage( target, dmginfo:GetDamage(), dmginfo:IsDamageType( DMG_BLAST ), dmginfo:GetDamagePosition() )
	end)
else
	local damages = {}
	hook.Add( "HUDPaint", "ezdmg_damage_draw", function()
		for i=#damages,1,-1 do
			local ent = damages[i].ent
			if not IsValid( ent ) then
				table.remove( damages, i )
			else
				local pos = damages[i].pos
				local damage = damages[i].damage
				local offset = damages[i].offset

				local scr_pos = ent:LocalToWorld( pos ):ToScreen()

				local fade = 1
				if offset > 100 then
					fade = 1 - (offset-100) / 50
				end

				if fade <= 0 then
					table.remove( damages, i )
				else
					if scr_pos.visible then
						local str = tostring(math.abs(damage))

						surface.SetFont( "Trebuchet24" )

						if damage > 0 then str = "-" .. str
						else str = "+" .. str end
						
						surface.SetTextColor(Color(0,0,0,255*fade))
						surface.SetTextPos( scr_pos.x+1, scr_pos.y - offset+1 )
						surface.DrawText( str )

						if damage > 0 then
							surface.SetTextColor(Color(175,40,40,255*fade))
						else
							surface.SetTextColor(Color(40,175,40,255*fade))
						end

						surface.SetTextPos( scr_pos.x, scr_pos.y - offset )
						surface.DrawText( str )
					end

					offset = offset + 120 * FrameTime()
					damages[i].offset = offset
				end
			end
		end
	end)

	net.Receive( "ezdmg_damage_report", function( len )
		local ent = net.ReadEntity()

		if not IsValid( ent ) then return end

		local pos = Vector(net.ReadFloat(),net.ReadFloat(),net.ReadFloat())
		local damage = net.ReadInt(32)

		damages[#damages+1] = {
			ent = ent,
			pos = pos, -- + Vector(math.random(-5,5),math.random(-5,5),math.random(-5,5)),
			damage = damage,
			offset = 0
		}
	end)

end