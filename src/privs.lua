-- Privilege model: which privileges exist, who may grant them, and the
-- safe online/offline grant + revoke operations.

priviledges_manager.privs = {}

-- Sorted array of { name = string, def = table } for every registered
-- privilege. Works on any game because privileges are an engine concept.
function priviledges_manager.privs.all()
	local list = {}
	for name, def in pairs(minetest.registered_privileges) do
		list[#list + 1] = { name = name, def = def }
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

-- The set of privileges a "basic_privs" holder is allowed to manage.
local function basic_set()
	local set = {}
	local conf = minetest.settings:get("basic_privs") or "interact,shout"
	for _, priv in ipairs(conf:split(",")) do
		set[priv:trim()] = true
	end
	return set
end
priviledges_manager.privs.basic_set = basic_set

-- May `granter` toggle privilege `priv`? Mirrors the engine's /grant rules:
--   * "privs"       -> may manage any privilege
--   * "basic_privs" -> may manage only privileges in the basic_privs setting
function priviledges_manager.privs.can_grant(granter, priv)
	local gp = minetest.get_player_privs(granter)
	if gp.privs then
		return true
	end
	if gp.basic_privs then
		return basic_set()[priv] == true
	end
	return false
end

-- May `name` open the manager at all? (Has any granting capability.)
function priviledges_manager.privs.can_use(name)
	local gp = minetest.get_player_privs(name)
	return gp.privs == true or gp.basic_privs == true
end

-- Apply a single privilege change. `value` true = grant, false = revoke.
-- Works for offline players via the auth handler. set_player_privs runs the
-- registered on_grant / on_revoke callbacks itself, so we must not double-run.
function priviledges_manager.privs.set(target, priv, value, caller)
	local privs = minetest.get_player_privs(target)

	-- Revoking must remove the key entirely; the engine warns on a `false`
	-- value passed through set_player_privs.
	privs[priv] = value and true or nil
	minetest.set_player_privs(target, privs)

	-- Keep our own seen-list in sync so freshly created accounts show up.
	priviledges_manager.players.remember(target)

	-- Notify the affected player if they are online.
	if minetest.get_player_by_name(target) then
		local verb = value and "granted to" or "revoked from"
		minetest.chat_send_player(target,
			minetest.colorize("#f5d76e",
				("[Privileges] '%s' was %s you by %s."):format(priv, verb, caller)))
	end

	minetest.log("action",
		("[priviledges_manager] %s %s '%s' for %s"):format(
			caller, value and "granted" or "revoked", priv, target))
end
