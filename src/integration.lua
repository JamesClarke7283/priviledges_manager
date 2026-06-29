-- Entry points: chat command, plus optional inventory buttons for the two
-- common inventory frameworks (sfinv on Minetest Game, unified_inventory).

local function open_for(name, target)
	if not priviledges_manager.privs.can_use(name) then
		return false, "You need the 'privs' (or 'basic_privs') privilege to manage privileges."
	end
	priviledges_manager.show(name, target ~= "" and target or nil)
	return true
end

minetest.register_chatcommand("privman", {
	params = "[player]",
	description = "Open the visual Privileges Manager (optionally for a player)",
	-- No priv requirement here so basic_privs holders can open it too;
	-- the real check happens in open_for and on every toggle.
	func = function(name, param)
		return open_for(name, param:trim())
	end,
})

minetest.register_chatcommand("privileges_manager", {
	params = "[player]",
	description = "Alias for /privman",
	func = function(name, param)
		return open_for(name, param:trim())
	end,
})

-- sfinv tab (Minetest Game and games that use sfinv).
if minetest.get_modpath("sfinv") and sfinv and sfinv.register_page then
	sfinv.register_page("priviledges_manager:tab", {
		title = "Privileges",
		is_in_nav = function(self, player, context)
			return priviledges_manager.privs.can_use(player:get_player_name())
		end,
		get = function(self, player, context)
			return sfinv.make_formspec(player, context,
				"button[2.5,3;5,1;privman_open;Open Privileges Manager]"
					.. "label[0.5,1;Manage player privileges visually.]",
				false)
		end,
		on_player_receive_fields = function(self, player, context, fields)
			if fields.privman_open then
				priviledges_manager.show(player:get_player_name())
			end
		end,
	})
end

-- unified_inventory button (used by many games incl. some Mineclone setups).
if minetest.get_modpath("unified_inventory") and unified_inventory
		and unified_inventory.register_button then
	unified_inventory.register_button("privman", {
		type = "image",
		image = "ui_skins_button.png", -- generic; falls back gracefully if missing
		tooltip = "Privileges Manager",
		action = function(player)
			if priviledges_manager.privs.can_use(player:get_player_name()) then
				priviledges_manager.show(player:get_player_name())
			end
		end,
		condition = function(player)
			return priviledges_manager.privs.can_use(player:get_player_name())
		end,
	})
end
