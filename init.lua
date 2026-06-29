-- Privileges Manager
-- A visual, searchable privilege management GUI.

priviledges_manager = {}

local modpath = minetest.get_modpath("priviledges_manager")
priviledges_manager.modpath = modpath

-- Detect the running game so the GUI can adapt its look between
-- Minetest Game and Mineclonia / VoxeLibre.
local game = (minetest.get_game_info and minetest.get_game_info()) or {}
priviledges_manager.game_id = game.id or "unknown"
priviledges_manager.game_title = game.title or "Luanti"

-- Mineclone family uses a darker UI palette; Minetest Game a lighter one.
local mcl = priviledges_manager.game_id:find("mineclon")
	or priviledges_manager.game_id:find("voxelibre")
	or minetest.get_modpath("mcl_core")
priviledges_manager.is_mcl = mcl ~= nil

local src = modpath .. "/src/"
dofile(src .. "players.lua")
dofile(src .. "privs.lua")
dofile(src .. "gui.lua")
dofile(src .. "integration.lua")
