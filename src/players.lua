-- Player discovery: online players, plus every account the auth backend
-- knows about (so offline players can be managed too).

priviledges_manager.players = {}

local storage = minetest.get_mod_storage()
local STORE_KEY = "seen_players"

-- A fallback set of names we have personally seen join. This is only used
-- when the active auth handler does not support iterate() (most custom
-- auth handlers). The builtin handler does support it, covering everyone.
local seen = minetest.deserialize(storage:get_string(STORE_KEY)) or {}

local function persist()
	storage:set_string(STORE_KEY, minetest.serialize(seen))
end

local function remember(name)
	if name and name ~= "" and not seen[name] then
		seen[name] = true
		persist()
	end
end
priviledges_manager.players.remember = remember

minetest.register_on_joinplayer(function(player)
	remember(player:get_player_name())
end)

-- Returns a set { [name] = true } of every account we can discover.
local function all_known_names()
	local names = {}

	-- 1. Currently connected players.
	for _, player in ipairs(minetest.get_connected_players()) do
		names[player:get_player_name()] = true
	end

	-- 2. Offline accounts via the auth handler, if it supports iteration.
	local handler = minetest.get_auth_handler and minetest.get_auth_handler()
	if handler and handler.iterate then
		-- iterate() returns the full pairs() triple (generator, state, control);
		-- capture all three so the for-loop has its iterator state.
		local ok, gen, state, control = pcall(handler.iterate)
		if ok and type(gen) == "function" then
			for name in gen, state, control do
				names[name] = true
			end
		end
	end

	-- 3. Anyone we have remembered ourselves (fallback / extra safety).
	for name in pairs(seen) do
		names[name] = true
	end

	return names
end

-- Returns a sorted array of { name = string, online = bool } filtered by
-- a case-insensitive substring query. Online players are listed first.
function priviledges_manager.players.list(query)
	query = (query or ""):lower()

	local online = {}
	for _, player in ipairs(minetest.get_connected_players()) do
		online[player:get_player_name()] = true
	end

	local result = {}
	for name in pairs(all_known_names()) do
		if query == "" or name:lower():find(query, 1, true) then
			result[#result + 1] = { name = name, online = online[name] == true }
		end
	end

	table.sort(result, function(a, b)
		if a.online ~= b.online then
			return a.online -- online players bubble to the top
		end
		return a.name:lower() < b.name:lower()
	end)

	return result
end

-- True if the account exists in the auth database (used to warn when a
-- never-seen name is opened, which would create a fresh account on grant).
function priviledges_manager.players.exists(name)
	local handler = minetest.get_auth_handler and minetest.get_auth_handler()
	if handler and handler.get_auth then
		local ok, auth = pcall(handler.get_auth, name)
		if ok and auth then
			return true
		end
	end
	return seen[name] == true or minetest.get_player_by_name(name) ~= nil
end
