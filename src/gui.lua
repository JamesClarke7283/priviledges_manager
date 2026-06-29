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

-- Layout constants. The formspec is deliberately wide so that long
-- privilege descriptions fit on the right without being clipped.
local W, H = 19.0, 12.0
local PRIV_ROW_H = 1.15
local CONTENT_X, CONTENT_Y = 6.1, 2.2
local CONTENT_W, CONTENT_H = 12.0, 9.0

-- Word-wrap `text` into at most `maxlines` lines of about `maxchars`
-- characters each, appending an ellipsis if it had to be cut short. This is
-- deterministic (no reliance on a widget auto-wrapping), so descriptions can
-- never spill under the toggle button.
local function wrap(text, maxchars, maxlines)
	local words = {}
	for w in tostring(text or ""):gmatch("%S+") do
		words[#words + 1] = w
	end

	local lines, cur, i = {}, "", 1
	while i <= #words do
		local cand = cur == "" and words[i] or (cur .. " " .. words[i])
		if #cand <= maxchars then
			cur = cand
			i = i + 1
		elseif cur == "" then
			-- A single word longer than the line: hard-cut it.
			cur = words[i]:sub(1, maxchars - 1) .. "\u{2026}"
			i = i + 1
		else
			lines[#lines + 1] = cur
			cur = ""
			if #lines == maxlines then
				break
			end
		end
	end
	if #lines < maxlines and cur ~= "" then
		lines[#lines + 1] = cur
		cur = ""
	end

	-- Words still remaining means we ran out of lines: mark a truncation.
	if i <= #words then
		local last = lines[#lines] or ""
		if #last + 1 > maxchars then
			last = last:sub(1, maxchars - 1)
		end
		lines[#lines] = last .. "\u{2026}"
	end

	return lines
end

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

	-- Geometry shared by every row. The toggle is pinned to the right and the
	-- text is wrapped to end well before it, so they can never overlap.
	local btn_w, btn_h = 1.7, 0.7
	local btn_x = CONTENT_W - btn_w - 0.5      -- toggle pinned to the right
	local text_right = btn_x - 0.3             -- text must end before here
	local text_w = text_right - 0.5
	-- Conservative character budget for the wrapped description (tuned for the
	-- default font so it stays inside even if the smaller font is unavailable).
	local desc_chars = math.max(12, math.floor(text_w / 0.23))
	local LINE_H = 0.27

	-- First pass: wrap every description (no truncation) and work out each
	-- row's height so the full text always fits. Rows grow as tall as needed.
	local rows = {}
	local y = 0.1
	for i, p in ipairs(privs) do
		local desc = (p.def and p.def.description) or ""
		local dlines = desc ~= "" and wrap(desc, desc_chars, math.huge) or {}
		local row_h = #dlines > 0
			and (0.52 + #dlines * LINE_H + 0.12) or 0.72
		rows[i] = { p = p, desc = desc, dlines = dlines, y = y, h = row_h }
		y = y + row_h + 0.06
	end
	local content_h = y + 0.05

	-- Size the scrollbar to the actual content so the full list is reachable
	-- and the thumb reflects how much is visible.
	local scroll_factor = 0.1
	local overflow = math.max(0, content_h - CONTENT_H)
	local max_units = math.ceil(overflow / scroll_factor)
	local thumb = overflow > 0
		and math.max(1, math.floor(max_units * CONTENT_H / overflow)) or 0
	local value = math.min(c.scroll or 0, max_units)

	local fs = {}
	fs[#fs + 1] = ("scrollbaroptions[arrows=default;max=%d;thumbsize=%d]"):format(
		max_units, thumb)
	fs[#fs + 1] = ("scrollbar[%f,%f;0.35,%f;vertical;privscroll;%d]"):format(
		CONTENT_X + CONTENT_W + 0.05, CONTENT_Y, CONTENT_H, value)
	fs[#fs + 1] = ("scroll_container[%f,%f;%f,%f;privscroll;vertical;%f]"):format(
		CONTENT_X, CONTENT_Y, CONTENT_W, CONTENT_H, scroll_factor)

	-- Slightly smaller text for the privilege rows. Only affects labels emitted
	-- after this point (the rows + nothing else of note before the container end).
	fs[#fs + 1] = "style_type[label;font_size=*0.9]"

	for _, r in ipairs(rows) do
		local p, desc, row_h = r.p, r.desc, r.h
		local is_on = held[p.name] == true
		local grantable = priviledges_manager.privs.can_grant(viewer, p.name)
		local btn = "t_" .. p.name

		-- Row background.
		fs[#fs + 1] = ("box[0.1,%f;%f,%f;#ffffff10]"):format(
			r.y, CONTENT_W - 0.5, row_h)

		-- Privilege name.
		fs[#fs + 1] = ("label[0.35,%f;%s]"):format(r.y + 0.27, esc(p.name))

		-- Full description, wrapped across as many lines as it needs.
		for k, line in ipairs(r.dlines) do
			fs[#fs + 1] = ("label[0.5,%f;%s]"):format(
				r.y + 0.52 + (k - 1) * LINE_H, esc(line))
		end

		-- The toggle switch itself: a coloured button, vertically centred.
		local colour = grantable and (is_on and THEME.on or THEME.off) or THEME.locked
		local face = is_on and "ON" or "OFF"
		if not grantable then
			face = "\u{1F512}" -- padlock: cannot change this privilege
		end
		fs[#fs + 1] = ("style[%s;bgcolor=%s;textcolor=#ffffff]"):format(btn, colour)
		fs[#fs + 1] = ("button[%f,%f;%f,%f;%s;%s]"):format(
			btn_x, r.y + (row_h - btn_h) / 2, btn_w, btn_h, btn, face)

		-- Full description on hover: an area tooltip over the text, plus the
		-- same text on the toggle itself.
		local tip = desc ~= "" and desc or p.name
		if not grantable then
			tip = tip .. "\nYou are not allowed to change this privilege."
		end
		fs[#fs + 1] = ("tooltip[%f,%f;%f,%f;%s]"):format(
			0.1, r.y, text_right, row_h, esc(tip))
		fs[#fs + 1] = ("tooltip[%s;%s]"):format(btn, esc(tip))
	end

	fs[#fs + 1] = "scroll_container_end[]"
	fs[#fs + 1] = "style_type[label;font_size=*1.0]"
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

	-- Remember the scroll position so toggling a switch doesn't jump to top.
	if fields.privscroll then
		local ev = minetest.explode_scrollbar_event(fields.privscroll)
		if ev.type == "CHG" then
			c.scroll = ev.value
		end
	end

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
