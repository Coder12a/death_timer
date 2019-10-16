local death_timer = {}
local players = {}
local player_objs = {}
local loops = {}

local initial_timeout = tonumber(minetest.settings:get("death_timer.initial_timeout")) or 8
local timeout = tonumber(minetest.settings:get("death_timer.timeout")) or 1
local timeout_reduce_loop = tonumber(minetest.settings:get("death_timer.timeout_reduce_loop")) or 3600
local timeout_reduce_rate = tonumber(minetest.settings:get("death_timer.timeout_reduce_rate")) or 1
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
	local obj = player_objs[name]
	if player and obj then
		local pos = player:get_pos()
		player:set_attach(obj, "", {x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
		obj:get_luaentity().owner = name
		obj:set_pos(pos)
		player_objs[name] = obj
	elseif player and not obj then
		local pos = player:get_pos()
		obj = minetest.add_entity(pos, "death_timer:death")
		player:set_attach(obj, "", {x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
		obj:get_luaentity().owner = name
		obj:set_pos(pos)
		player_objs[name] = obj
	end
end

minetest.register_on_joinplayer(function(player)
	minetest.after(5, function(name)
		local p = players[name]
		if p and p.time and p.time > 1 then
			local player = minetest.get_player_by_name(name)
			if not player then
				return
			end
			death_timer.hide(player, name)
			death_timer.create_deathholder(player, name)
			death_timer.create_loop(name)
		end
	end, player:get_player_name())
end)

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

function death_timer.reduce_loop()
	for k, v in pairs(players) do
		if players[k].longtime > 0 then
			players[k].longtime = players[k].longtime - timeout_reduce_rate
			if players[k].longtime < 0 then
				minetest.after(0, function(k) players[k] = nil end, k)
			end
		else
			minetest.after(0, function(k) players[k] = nil end, k)
		end
	end
	minetest.after(timeout_reduce_loop, death_timer.reduce_loop)
end

function death_timer.create_loop(name)
	if not loops[name] then
		loops[name] = true
		death_timer.loop(name)
	end
end

function death_timer.loop(name)
	local p = players[name]
	if not p or not p.time or p.time < 1 then
		death_timer.show(player, name)
		loops[name] = nil
		local formspec = "size[11,5.5]bgcolor[#320000b4;true]" ..
		"label[5.15,1.35;Wait" ..
		"]button_exit[4,3;3,0.5;death_button;Play" .."]"
		minetest.show_formspec(name, "death_timer:death_screen", formspec)
		local obj = player_objs[name]
		if obj then
			obj:set_detach()
			obj:remove()
			obj = nil
			player_objs[name] = nil
		end
		if p then
			if p.interact then
				local privs = minetest.get_player_privs(name)
				privs.interact = p.interact
				minetest.set_player_privs(name, privs)
			end
			if timeout == 0 or timeout_reduce_loop == 0 or timeout_reduce_rate == 0 then
				players[name] = nil
			end
		else
			local privs = minetest.get_player_privs(name)
			privs.interact = true
			minetest.set_player_privs(name, privs)
			players[name] = nil
		end
	else
		p.time = p.time - 1
		local formspec = "size[11,5.5]bgcolor[#320000b4;true]" ..
			"label[5.15,1.35;Wait" ..
			"]button[4,3;3,0.5;death_button;" .. p.time .."]"
		minetest.show_formspec(name, "death_timer:death_screen", formspec)
		minetest.after(1, death_timer.loop, name)
	end
end

minetest.register_on_leaveplayer(function(player)
	local name = player:get_player_name()

	if player_objs[name] then
		player_objs[name]:set_detach()
		player_objs[name]:remove()
		player_objs[name] = nil
	end
end)

minetest.register_on_dieplayer(function(player)
	local name = player:get_player_name()
	local p = players[name]
	local privs = minetest.get_player_privs(name)
	if not p then
		p = {}
		p.longtime = initial_timeout
		p.time = initial_timeout
	else
		p.time = p.longtime + timeout
		p.longtime = p.time
	end
	p.interact = privs.interact
	players[name] = p
	death_timer.hide(player, name)
	privs.interact = nil
	minetest.set_player_privs(name, privs)
end)

minetest.register_on_mods_loaded(function()
	minetest.register_on_respawnplayer(function(player)
		if player:get_hp() < 1 then
			return
		end
		local name = player:get_player_name()
		minetest.after(1, function(name)
			local player = minetest.get_player_by_name(name)
			death_timer.create_deathholder(player, name)
		end, name)
		local formspec
		if players[name] and players[name].time then
			formspec = "size[11,5.5]bgcolor[#320000b4;true]" ..
			"label[5.15,1.35;Wait" ..
			"]button[4,3;3,0.5;death_button;" .. players[name].time .."]"
		else
			formspec = "size[11,5.5]bgcolor[#320000b4;true]" ..
			"label[5.15,1.35;Wait" ..
			"]button_exit[4,3;3,0.5;death_button;Play" .."]"
		end
		minetest.after(1, minetest.show_formspec, name, "death_timer:death_screen", formspec)
		minetest.after(2, death_timer.create_loop, name)
	end)
end)

minetest.register_on_player_hpchange(function(player, hp_change, reason)
	local p = players[player:get_player_name()]
	if p and p.time and p.time > 1 then
		return 100
	end
	return hp_change
end, true)

if timeout ~= 0 and timeout_reduce_loop ~= 0 and timeout_reduce_rate ~= 0 then
	minetest.after(timeout_reduce_loop, death_timer.reduce_loop)
end
