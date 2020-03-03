local death_timer = {}
local players = {}

local timeout = tonumber(minetest.settings:get("death_timer.timeout")) or 20
local cloaking_mod = minetest.global_exists("cloaking")

function death_timer.show(player, name)
	if not cloaking_mod then
		local p = players[name]
		if p and p.properties then
			local player = minetest.get_player_by_name(name)
			if player then
				local props = p.properties
				player:set_properties({
					visual_size    = props.visual_size,
					["selectionbox"] = props["selectionbox"],
				})
			end
			p.properties = nil
			players[name] = p
		end
	elseif minetest.get_player_by_name(name) then
		cloaking.unhide_player(name)
	end
end
function death_timer.hide(player, name)
	if not cloaking_mod then
		if not players[name].properties then
			players[name].properties = player:get_properties()
		end
		player:set_properties({
			visual_size    = {x = 0, y = 0},
			["selectionbox"] = {0, 0, 0, 0, 0, 0},
		})
	else
		cloaking.hide_player(name)
	end
end
function death_timer.create_deathholder(player, name)
	local obj = players[name].obj
	if not obj then
		obj = minetest.add_entity({x = 0, y = 0, z = 0}, "death_timer:death")
	end
	if player then
		player:set_attach(obj, "", {x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
		obj:get_luaentity().owner = name
		obj:set_pos(player:get_pos())
		players[name].obj = obj
	end
end
function death_timer.formspec(name, text)
	local formspec = "size[11,5.5]bgcolor[#320000b4;true]" ..
		"label[5.15,1.35;Wait" ..
		"]button_exit[4,3;3,0.5;death_button;" .. text .."]"
	minetest.show_formspec(name, "death_timer:death_screen", formspec)
end

minetest.register_entity("death_timer:death", {
	is_visible = false,
	on_step = function(self, dtime)
		self.timer= self.timer + dtime
		if self.timer >= 10 then
			self.timer = 0
			if not (self.owner and minetest.get_player_by_name(self.owner)) then
				self.object:remove()
			end
		end
	end,
	on_activate = function(self, staticdata)
		self.timer = 0
		self.object:set_armor_groups({immortal = 1, ignore = 1, do_not_delete = 1})
	end
})

function death_timer.create_loop(player, name)
	if not players[name].loop then
		players[name].loop = true
		death_timer.loop(player, name)
	end
end
function death_timer.loop(player, name)
	local p = players[name]
	if not p.time or p.time < 1 then
		death_timer.show(player, name)
		death_timer.formspec(name, "Play")
		local obj = p.obj
		if obj then
			obj:set_detach()
			obj:remove()
			obj = nil
		end
		if p.interact then
			local privs = minetest.get_player_privs(name)
			privs.interact = p.interact
			minetest.set_player_privs(name, privs)
		end
		players[name] = nil
	elseif p then
		p.time = p.time - 1
		death_timer.formspec(name, p.time)
		minetest.after(1, death_timer.loop, player, name)
	end
end

minetest.register_on_prejoinplayer(function(name, ip)
		local p = players[name]
		if p and p.time and p.time > 0 then
			return "You have to wait out the death ban for " .. p.time .. " seconds."
		end
end)
minetest.register_on_leaveplayer(function(player)
	local name = player:get_player_name()

	if players[name] and players[name].obj then
		players[name].obj:set_detach()
		players[name].obj:remove()
		players[name].obj = nil
	end
end)
minetest.register_on_dieplayer(function(player)
	local name = player:get_player_name()
	local p = players[name]
	local privs = minetest.get_player_privs(name)
	if not p then
		p = {time = timeout}
	else
		p.time = timeout
	end
	p.interact = privs.interact
	players[name] = p
	death_timer.hide(player, name)
	privs.interact = nil
	minetest.set_player_privs(name, privs)
end)
minetest.register_on_mods_loaded(function()
	minetest.register_on_respawnplayer(function(player)
		local name = player:get_player_name()
		if player:get_hp() < 1 or not players[name] then
			return
		end
		minetest.after(0, function(name)
			local player = minetest.get_player_by_name(name)
			death_timer.create_deathholder(player, name)
			minetest.after(1, death_timer.create_loop, player, name)
		end, name)
	end)
end)
minetest.register_on_player_hpchange(function(player, hp_change, reason)
	local p = players[player:get_player_name()]
	if p and p.time and p.time > 1 then
		return 100
	end
	return hp_change
end, true)
