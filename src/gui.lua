-- The Privileges Manager formspec: searchable player list on the left,
-- toggle-switch privilege rows on the right. Built with formspec version 4
-- (real coordinates) so it renders identically on Minetest Game and
-- Mineclonia / VoxeLibre.

local FORMNAME = "priviledges_manager:main"
local esc = minetest.formspec_escape

-- Per-viewer interface state. Cleared when the form is closed.
local ctx = {}

local function get_ctx(name)
	ctx[name] = ctx[name] or { query = "", target = nil, filtered = {} }
	return ctx[name]
end

-- Theme colours, adapted to the host game's palette.
local THEME = priviledges_manager.is_mcl and {
	bg = "#0d0d0fee",
	panel = "#00000055",
	on = "#3fae54",   -- switch ON  (green)
	off = "#5a5a5e",  -- switch OFF (grey)
	locked = "#3a2a2a", -- not grantable by this viewer
} or {
	bg = "#23232bee",
	panel = "#0000004f",
	on = "#4caf50",
	off = "#6d6d75",
	locked = "#4a3030",
}

-- Layout constants.
local W, H = 16.0, 11.5
local PRIV_ROW_H = 0.95
local CONTENT_X, CONTENT_Y = 6.1, 2.2
local CONTENT_W, CONTENT_H = 8.9, 8.7

local function build_player_list(c)
	local players = priviledges_manager.players.list(c.query)
	c.filtered = players

	local items, selidx = {}, 0
	for i, p in ipairs(players) do
		local marker = p.online and "\u{25CF} " or "\u{25CB} "
		local colour = p.online and "#7fe07f" or "#bfbfbf"
		items[i] = colour .. esc(marker .. p.name)
		if p.name == c.target then
			selidx = i
		end
	end

	return table.concat(items, ","), selidx, #players
end

local function build_priv_rows(c, viewer)
	if not c.target then
		return ("label[%f,%f;%s]"):format(
			CONTENT_X + 0.3, CONTENT_Y + 0.4,
			esc("Select a player on the left to manage their privileges."))
	end

	local privs = priviledges_manager.privs.all()
	local held = minetest.get_player_privs(c.target)
	local content_h = math.max(CONTENT_H, #privs * PRIV_ROW_H + 0.2)

	local fs = {}
	fs[#fs + 1] = "scrollbaroptions[arrows=default;thumbsize=30]"
	fs[#fs + 1] = ("scrollbar[%f,%f;0.35,%f;vertical;privscroll;%d]"):format(
		CONTENT_X + CONTENT_W + 0.05, CONTENT_Y, CONTENT_H, c.scroll or 0)
	fs[#fs + 1] = ("scroll_container[%f,%f;%f,%f;privscroll;vertical;0.1]"):format(
		CONTENT_X, CONTENT_Y, CONTENT_W, CONTENT_H)

	for i, p in ipairs(privs) do
		local y = (i - 1) * PRIV_ROW_H
		local is_on = held[p.name] == true
		local grantable = priviledges_manager.privs.can_grant(viewer, p.name)
		local btn = "t_" .. p.name
		local desc = (p.def and p.def.description) or ""

		-- Row background.
		fs[#fs + 1] = ("box[0.1,%f;%f,%f;#ffffff10]"):format(
			y + 0.05, CONTENT_W - 0.5, PRIV_ROW_H - 0.15)

		-- Privilege name + description.
		fs[#fs + 1] = ("label[0.35,%f;%s]"):format(y + 0.3, esc(p.name))
		if desc ~= "" then
			fs[#fs + 1] = ("label[0.35,%f;%s]"):format(
				y + 0.62, esc("\u{2937} " .. desc):sub(1, 90))
		end

		-- The toggle switch itself: a coloured track + a labelled button.
		local colour = grantable and (is_on and THEME.on or THEME.off) or THEME.locked
		local face = is_on and "ON" or "OFF"
		if not grantable then
			face = "\u{1F512}" -- padlock: cannot change this privilege
		end
		fs[#fs + 1] = ("style[%s;bgcolor=%s;textcolor=#ffffff]"):format(btn, colour)
		fs[#fs + 1] = ("button[%f,%f;1.7,0.7;%s;%s]"):format(
			CONTENT_W - 2.25, y + 0.1, btn, face)

		local tip = desc ~= "" and desc or p.name
		if not grantable then
			tip = tip .. "\nYou are not allowed to change this privilege."
		end
		fs[#fs + 1] = ("tooltip[%s;%s]"):format(btn, esc(tip))
	end

	fs[#fs + 1] = "scroll_container_end[]"
	return table.concat(fs)
end

local function build(viewer)
	local c = get_ctx(viewer)
	local list_items, selidx, count = build_player_list(c)

	local target_label
	if c.target then
		local online = minetest.get_player_by_name(c.target) ~= nil
		local known = priviledges_manager.players.exists(c.target)
		target_label = "Managing: " .. c.target ..
			(online and "  (online)" or known and "  (offline)" or "  (new account)")
	else
		target_label = "No player selected"
	end

	local fs = {
		"formspec_version[4]",
		("size[%f,%f]"):format(W, H),
		("bgcolor[%s;true]"):format(THEME.bg),

		-- Header.
		("label[0.4,0.55;%s]"):format(esc("\u{1F511} Privileges Manager  \u{2014}  " ..
			priviledges_manager.game_title)),

		-- Left panel: search + player list.
		("box[0.3,1.0;5.5,%f;%s]"):format(H - 1.3, THEME.panel),
		"field_close_on_enter[query;false]",
		("field[0.5,1.25;3.7,0.7;query;;%s]"):format(esc(c.query)),
		"button[4.3,1.25;1.3,0.7;search;Search]",
		("tooltip[query;%s]"):format(esc(
			"Type part of a name and press Enter to filter the list.")),
		("textlist[0.5,2.15;5.1,%f;playerlist;%s;%d;false]"):format(
			H - 4.2, list_items, selidx),
		("label[0.5,%f;%s]"):format(H - 1.85,
			esc(count .. " player(s)  \u{25CF} online  \u{25CB} offline")),

		-- Manage an arbitrary (possibly never-seen) account by exact name.
		"field_close_on_enter[newname;true]",
		("field[0.5,%f;3.7,0.7;newname;;]"):format(H - 1.5),
		("button[4.3,%f;1.3,0.7;manage;Open]"):format(H - 1.5),
		("tooltip[newname;%s]"):format(esc(
			"Manage an offline player by exact name, then press Enter / Open.")),

		-- Right panel: privilege toggles.
		("box[6.0,1.0;%f,%f;%s]"):format(W - 6.3, H - 1.3, THEME.panel),
		("label[6.2,1.55;%s]"):format(esc(target_label)),
		build_priv_rows(c, viewer),

		"button_exit[" .. ("%f,%f;2.0,0.7;close;Close]"):format(W - 2.3, H - 0.95),
	}

	return table.concat(fs)
end

function priviledges_manager.show(viewer, target)
	if target and target ~= "" then
		local c = get_ctx(viewer)
		c.target = target
		priviledges_manager.players.remember(target)
	end
	minetest.show_formspec(viewer, FORMNAME, build(viewer))
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORMNAME then
		return
	end
	local viewer = player:get_player_name()

	-- Security: never trust the client. Re-check permission on every action.
	if not priviledges_manager.privs.can_use(viewer) then
		minetest.chat_send_player(viewer, "You may no longer use the Privileges Manager.")
		ctx[viewer] = nil
		return true
	end

	local c = get_ctx(viewer)

	if fields.quit or fields.close then
		ctx[viewer] = nil
		return true
	end

	local rerender = false

	-- Live search (fires on Enter in the query field or the Search button).
	if fields.query ~= nil and fields.query ~= c.query then
		c.query = fields.query
		rerender = true
	end
	if fields.search then
		rerender = true
	end

	-- Player picked from the list.
	if fields.playerlist then
		local ev = minetest.explode_textlist_event(fields.playerlist)
		if ev.type == "CHG" or ev.type == "DCL" then
			local item = c.filtered[ev.index]
			if item then
				c.target = item.name
				rerender = true
			end
		end
	end

	-- Manage an arbitrary account by exact name.
	if (fields.manage or fields.key_enter_field == "newname")
			and fields.newname and fields.newname:trim() ~= "" then
		c.target = fields.newname:trim()
		priviledges_manager.players.remember(c.target)
		rerender = true
	end

	-- A privilege toggle was pressed.
	for key in pairs(fields) do
		local priv = key:match("^t_(.+)$")
		if priv and c.target and minetest.registered_privileges[priv] then
			if priviledges_manager.privs.can_grant(viewer, priv) then
				local held = minetest.get_player_privs(c.target)
				priviledges_manager.privs.set(c.target, priv, not held[priv], viewer)
			else
				minetest.chat_send_player(viewer,
					"You are not allowed to change the '" .. priv .. "' privilege.")
			end
			rerender = true
			break
		end
	end

	if rerender then
		priviledges_manager.show(viewer)
	end
	return true
end)

minetest.register_on_leaveplayer(function(player)
	ctx[player:get_player_name()] = nil
end)
