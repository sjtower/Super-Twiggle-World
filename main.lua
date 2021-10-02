meta.name = 'Jumplunky'
meta.version = '1.5'
meta.description = 'Challenging platforming puzzles'
meta.author = 'JayTheBusinessGoose'

local level_sequence = require("LevelSequence/level_sequence")
local SIGN_TYPE = level_sequence.SIGN_TYPE
local telescopes = require("Telescopes/telescopes")
local button_prompts = require("ButtonPrompts/button_prompts")
local idols = require('idols')
local sound = require('play_sound')
local journal = require('journal')
local win_ui = require('win')
local bottom_hud = require('bottom_hud')
local clear_embeds = require('clear_embeds')
local DIFFICULTY = require('difficulty')

local dwelling = require("dwelling")
local volcana = require("volcana")
local temple = require("temple")
local ice_caves = require("ice_caves")
local sunken_city = require("sunken_city")

level_sequence.set_levels({dwelling, volcana, temple, ice_caves, sunken_city})

-- Forward declare local function
local update_continue_door_enabledness

-- Store the save context in a local var so we can save whenever we want.
local save_context

local initial_bombs = 0
local initial_ropes = 0

local current_difficulty = DIFFICULTY.NORMAL

-- overall state
local total_idols = 0
local idols_collected = {}
local hardcore_enabled = false
local hardcore_previously_enabled = false

local create_stats = require('stats')
local stats = create_stats()
local hardcore_stats = create_stats()
local legacy_stats = create_stats(true)
local legacy_hardcore_stats = create_stats(true)

function stats.current_stats()
	return stats.stats_for_difficulty(current_difficulty)
end
function legacy_stats.current_stats()
	return legacy_stats.stats_for_difficulty(current_difficulty)
end
function hardcore_stats.current_stats()
	return hardcore_stats.stats_for_difficulty(current_difficulty)
end
function legacy_hardcore_stats.current_stats()
	return legacy_hardcore_stats.stats_for_difficulty(current_difficulty)
end

-- True if the player has seen ana dead in the sunken city level.
local has_seen_ana_dead = false

local idols = 0
local run_idols_collected = {}

-- saved run state for the default difficulty.
local easy_saved_run = {
	has_saved_run = false,
	saved_run_attempts = nil,
	saved_run_time = nil,
	saved_run_level = nil,
	saved_run_idol_count = nil,
	saved_run_idols_collected = {},
}
-- saved run state for the easy difficulty.
local normal_saved_run = {
	has_saved_run = false,
	saved_run_attempts = nil,
	saved_run_time = nil,
	saved_run_level = nil,
	saved_run_idol_count = nil,
	saved_run_idols_collected = {},
}
-- saved run state for the hard difficulty.
local hard_saved_run = {
	has_saved_run = false,
	saved_run_attempts = nil,
	saved_run_time = nil,
	saved_run_level = nil,
	saved_run_idol_count = nil,
	saved_run_idols_collected = {},
}
-- saved run state for the current difficulty.
local function current_saved_run()
	if current_difficulty == DIFFICULTY.EASY then
		return easy_saved_run
	elseif current_difficulty == DIFFICULTY.HARD then
		return hard_saved_run
	else
		return normal_saved_run
	end
end

local function set_hardcore_enabled(enabled)
	hardcore_enabled = enabled
	bottom_hud.update_stats(
		hardcore_enabled and hardcore_stats.current_stats() or stats.current_stats(),
		hardcore_enabled,
		current_difficulty)
	level_sequence.set_keep_progress(not hardcore_enabled)
	update_continue_door_enabledness()
end

local function set_difficulty(difficulty)
	current_difficulty = difficulty
	bottom_hud.update_stats(
		hardcore_enabled and hardcore_stats.current_stats() or stats.current_stats(),
		hardcore_enabled,
		current_difficulty)
	bottom_hud.update_saved_run(current_saved_run())
	update_continue_door_enabledness()
end

---------------
---- SOUNDS ---
---------------

-- Make spring traps quieter.
set_vanilla_sound_callback(VANILLA_SOUND.TRAPS_SPRING_TRIGGER, VANILLA_SOUND_CALLBACK_TYPE.STARTED, function(playing_sound)
	playing_sound:set_volume(.3)
end)

-- Mute the vocal sound that was playing on the signs when they "say" something.
set_vanilla_sound_callback(VANILLA_SOUND.UI_NPC_VOCAL, VANILLA_SOUND_CALLBACK_TYPE.STARTED, function(playing_sound)
	playing_sound:set_volume(0)
end)

----------------
---- /SOUNDS ---
----------------

--------------
---- CAMP ----
--------------

local continue_door

function update_continue_door_enabledness()
	if not continue_door then return end
	local saved_run = current_saved_run()
	continue_door.update_door(saved_run.saved_run_level, saved_run.saved_run_attempts, saved_run.saved_run_time)
end

-- Spawn an idol that is not interactible in any way. Only spawns the idol if it has been collected
-- from the level it is being spawned for.
function spawn_camp_idol_for_level(level, x, y, layer)
	if not idols_collected[level.identifier] then return end
	
	local idol_uid = spawn_entity(ENT_TYPE.ITEM_IDOL, x, y, layer, 0, 0)
	local idol = get_entity(idol_uid)
	idol.flags = clr_flag(idol.flags, ENT_FLAG.THROWABLE_OR_KNOCKBACKABLE)
	idol.flags = clr_flag(idol.flags, ENT_FLAG.PICKUPABLE)
end

-- Creates a "room" for the Volcana shortcut, with a door, a sign, and an idol if it has been collected.
define_tile_code("volcana_shortcut")
set_pre_tile_code_callback(function(x, y, layer)
	level_sequence.spawn_shortcut(x, y, layer, volcana, SIGN_TYPE.RIGHT)
	spawn_camp_idol_for_level(volcana, x + 1, y, layer)
	return true
end, "volcana_shortcut")

-- Creates a "room" for the Temple shortcut, with a door, a sign, and an idol if it has been collected.
define_tile_code("temple_shortcut")
set_pre_tile_code_callback(function(x, y, layer)
	level_sequence.spawn_shortcut(x, y, layer, temple, SIGN_TYPE.RIGHT)
	spawn_camp_idol_for_level(temple, x + 1, y, layer)
	return true
end, "temple_shortcut")

-- Creates a "room" for the Ice Caves shortcut, with a door, a sign, and an idol if it has been collected.
define_tile_code("ice_shortcut")
set_pre_tile_code_callback(function(x, y, layer)
	level_sequence.spawn_shortcut(x, y, layer, ice_caves, SIGN_TYPE.LEFT)
	spawn_camp_idol_for_level(ice_caves, x - 1, y, layer)
	return true
end, "ice_shortcut")

-- Creates a "room" for the Sunken City shortcut, with a door, a sign, and an idol if it has been collected.
define_tile_code("sunken_shortcut")
set_pre_tile_code_callback(function(x, y, layer)
	level_sequence.spawn_shortcut(x, y, layer, sunken_city, SIGN_TYPE.LEFT)
	spawn_camp_idol_for_level(sunken_city, x - 1, y, layer)
	return true
end, "sunken_shortcut")

-- Creates a "room" for the continue entrance, with a door and a sign.
define_tile_code("continue_run")
set_pre_tile_code_callback(function(x, y, layer)
	continue_door = level_sequence.spawn_continue_door(
		x,
		y,
		layer,
		current_saved_run().saved_run_level,
		current_saved_run().saved_run_attempts,
		current_saved_run().saved_run_time,
		SIGN_TYPE.RIGHT)
	return true
end, "continue_run")

-- Spawns an idol if collected from the dwelling level, since there is no Dwelling shortcut.
define_tile_code("dwelling_idol")
set_pre_tile_code_callback(function(x, y, layer)
	spawn_camp_idol_for_level(dwelling, x, y, layer)
	return true
end, "dwelling_idol")

local tunnel_x, tunnel_y, tunnel_layer
local hardcore_sign, easy_sign, normal_sign, hard_sign, stats_sign, legacy_stats_sign
local hardcore_tv, easy_tv, normal_tv, hard_tv, stats_tv, legacy_stats_tv
-- Spawn tunnel, and spawn the difficulty and mode signs relative to her position.
define_tile_code("tunnel_position")
set_pre_tile_code_callback(function(x, y, layer)
	tunnel_x, tunnel_y, tunnel_layer = x, y, layer
	
	hardcore_sign = spawn_entity(ENT_TYPE.ITEM_SPEEDRUN_SIGN, x + 3, y, layer, 0, 0)
	local hardcore_sign_entity = get_entity(hardcore_sign)
	-- This stops the sign from displaying its default toast text when pressing the door button.
	hardcore_sign_entity.flags = clr_flag(hardcore_sign_entity.flags, ENT_FLAG.ENABLE_BUTTON_PROMPT)
	hardcore_tv = button_prompts.spawn_button_prompt(button_prompts.PROMPT_TYPE.INTERACT, x + 3, y, layer)
	
	easy_sign = spawn_entity(ENT_TYPE.ITEM_SPEEDRUN_SIGN, x + 6, y, layer, 0, 0)
	local easy_sign_entity = get_entity(easy_sign)
	-- This stops the sign from displaying its default toast text when pressing the door button.
	easy_sign_entity.flags = clr_flag(easy_sign_entity.flags, ENT_FLAG.ENABLE_BUTTON_PROMPT)
	easy_tv = button_prompts.spawn_button_prompt(button_prompts.PROMPT_TYPE.INTERACT, x + 6, y, layer)
	
	normal_sign = spawn_entity(ENT_TYPE.ITEM_SPEEDRUN_SIGN, x + 7, y, layer, 0, 0)
	local normal_sign_entity = get_entity(normal_sign)
	-- This stops the sign from displaying its default toast text when pressing the door button.
	normal_sign_entity.flags = clr_flag(normal_sign_entity.flags, ENT_FLAG.ENABLE_BUTTON_PROMPT)
	normal_tv = button_prompts.spawn_button_prompt(button_prompts.PROMPT_TYPE.INTERACT, x + 7, y, layer)
	
	hard_sign = spawn_entity(ENT_TYPE.ITEM_SPEEDRUN_SIGN, x + 8, y, layer, 0, 0)
	local hard_sign_entity = get_entity(hard_sign)
	-- This stops the sign from displaying its default toast text when pressing the door button.
	hard_sign_entity.flags = clr_flag(hard_sign_entity.flags, ENT_FLAG.ENABLE_BUTTON_PROMPT)
	hard_tv = button_prompts.spawn_button_prompt(button_prompts.PROMPT_TYPE.INTERACT, x + 8, y, layer)
	
	stats_sign = spawn_entity(ENT_TYPE.ITEM_SPEEDRUN_SIGN, x + 10, y, layer, 0, 0)
	local stats_sign_entity = get_entity(stats_sign)
	-- This stops the sign from displaying its default toast text when pressing the door button.
	stats_sign_entity.flags = clr_flag(stats_sign_entity.flags, ENT_FLAG.ENABLE_BUTTON_PROMPT)
	stats_tv = button_prompts.spawn_button_prompt(button_prompts.PROMPT_TYPE.VIEW, x + 10, y, layer)
	
	if legacy_stats.normal and
			legacy_stats.easy and
			legacy_stats.hard and
			legacy_hardcore_stats.normal and
			legacy_hardcore_stats.easy and
			legacy_hardcore_stats.hard then
		legacy_stats_sign = spawn_entity(ENT_TYPE.ITEM_SPEEDRUN_SIGN, x + 11, y, layer, 0, 0)
		local legacy_stats_sign_entity = get_entity(legacy_stats_sign)
		-- This stops the sign from displaying its default toast text when pressing the door button.
		legacy_stats_sign_entity.flags = clr_flag(legacy_stats_sign_entity.flags, ENT_FLAG.ENABLE_BUTTON_PROMPT)
		legacy_stats_tv = button_prompts.spawn_button_prompt(button_prompts.PROMPT_TYPE.VIEW, x + 11, y, layer)
	end
end, "tunnel_position")

local tunnel
set_callback(function()
	-- Spawn tunnel in the mode room and turn the normal tunnel invisible so the player doesn't see her.
	if state.theme ~= THEME.BASE_CAMP then return end
	local tunnels = get_entities_by_type(ENT_TYPE.MONS_MARLA_TUNNEL)
	if #tunnels > 0 then
		local tunnel_uid = tunnels[1]
		local tunnel = get_entity(tunnel_uid)
		tunnel.flags = set_flag(tunnel.flags, ENT_FLAG.INVISIBLE)
		tunnel.flags = clr_flag(tunnel.flags, ENT_FLAG.ENABLE_BUTTON_PROMPT)
	end
	local tunnel_id = spawn_entity(ENT_TYPE.MONS_MARLA_TUNNEL, tunnel_x, tunnel_y, tunnel_layer, 0, 0)
	tunnel = get_entity(tunnel_id)
	
	tunnel.flags = clr_flag(tunnel.flags, ENT_FLAG.ENABLE_BUTTON_PROMPT)
	tunnel.flags = set_flag(tunnel.flags, ENT_FLAG.FACING_LEFT)
	--end
end, ON.CAMP)

function unique_idols_collected()
	local unique_idol_count = 0
	for i, lvl in ipairs(level_sequence.levels()) do
		if idols_collected[lvl.identifier] then
			unique_idol_count = unique_idol_count + 1
		end
	end
	return unique_idol_count
end

function hardcore_available()
	return unique_idols_collected() == #level_sequence.levels()
end

-- STATS

set_journal_enabled(false)
set_callback(function()
	if #players < 1 then return end
	local player = players[1]
	local buttons = read_input(player.uid)
	-- 8 = Journal
	if test_flag(buttons, 8) and not journal.showing_stats() then
		journal.show(stats, hardcore_stats, current_difficulty, 8)

		-- Cancel speech bubbles so they don't show above stats.
		cancel_speechbubble()
		-- Hide the prompt so it doesn't show above stats.
		button_prompts.hide_button_prompts(true)
	end
end, ON.GAMEFRAME)

journal.set_on_journal_closed(function()
	button_prompts.hide_button_prompts(false)
end)

set_callback(function()
	if #players < 1 then return end
	local player = players[1]
	
	-- Show the stats journal when pressing the door button by the sign.
	if player:is_button_pressed(BUTTON.DOOR) and 
			stats_sign and get_entity(stats_sign) and
			player.layer == get_entity(stats_sign).layer and 
			distance(player.uid, stats_sign) <= .5 then
		journal.show(stats, hardcore_stats, current_difficulty, 6)

		-- Cancel speech bubbles so they don't show above stats.
		cancel_speechbubble()
		-- Hide the prompt so it doesn't show above stats.
		button_prompts.hide_button_prompts(true)
	end

	-- Show the legacy stats journal when pressing the door button by the sign.
	if player:is_button_pressed(BUTTON.DOOR) and
			legacy_stats_sign and 
			player.layer == get_entity(legacy_stats_sign).layer and
			distance(player.uid, legacy_stats_sign) <= .5 then
		journal.show(legacy_stats, legacy_hardcore_stats, current_difficulty, 6)

		-- Cancel speech bubbles so they don't show above stats.
		cancel_speechbubble()
		-- Hide the prompt so it doesn't show above stats.
		button_prompts.hide_button_prompts(true)
	end
end, ON.GAMEFRAME)

local tunnel_enter_displayed
local tunnel_exit_displayed
local tunnel_enter_hardcore_state
local tunnel_enter_difficulty
local tunnel_exit_hardcore_state
local tunnel_exit_difficulty
local tunnel_exit_ready
set_callback(function()
	if state.theme ~= THEME.BASE_CAMP then return end
	if #players < 1 then return end
	local player = players[1]
	local x, y, layer = get_position(player.uid)
	if layer == LAYER.FRONT then
		-- Reset tunnel dialog states when exiting the back layer so the dialog shows again.
		tunnel_enter_displayed = false
		tunnel_exit_displayed = false
		tunnel_enter_hardcore_state = hardcore_enabled
		tunnel_exit_hardcore_state = hardcore_enabled
		tunnel_enter_difficulty = current_difficulty
		tunnel_exit_difficulty = current_difficulty
		tunnel_exit_ready = false
	elseif tunnel_enter_displayed and x > tunnel_x + 2 then
		-- Do not show Tunnel's exit dialog until the player moves a bit to her right.
		tunnel_exit_ready = true
	end
end, ON.GAMEFRAME)

local player_near_hardcore_sign = false
local player_near_easy_sign = false
local player_near_normal_sign = false
local player_near_hard_sign = false
local player_near_stats_sign = false
local player_near_legacy_stats_sign = false

set_callback(function()
	if state.theme ~= THEME.BASE_CAMP then return end
	if #players < 1 then return end
	local player = players[1]
	
	-- Show a toast when pressing the door button on the signs near shortcut doors and continue door.
	if player:is_button_pressed(BUTTON.DOOR) then
		if player.layer == LAYER.BACK and hardcore_sign and distance(player.uid, hardcore_sign) <= .5 then
			if hardcore_available() then
				set_hardcore_enabled(not hardcore_enabled)
				hardcore_previously_enabled = true
				save_data()
				if hardcore_enabled then
					toast("Hardcore mode enabled")
				else
					toast("Hardcore mode disabled")
				end
			else
				toast("Collect more idols to unlock hardcore mode")
			end
		elseif player.layer == get_entity(easy_sign).layer and distance(player.uid, easy_sign) <= .5 then
			if current_difficulty ~= DIFFICULTY.EASY then
				set_difficulty(DIFFICULTY.EASY)
				save_data()
				toast("Easy mode enabled")
			end
		elseif player.layer == get_entity(hard_sign).layer and distance(player.uid, hard_sign) <= .5 then
			if hardcore_available() then
				if current_difficulty ~= DIFFICULTY.HARD then
					set_difficulty(DIFFICULTY.HARD)
					save_data()
					toast("Hard mode enabled")
				end
			else 
				toast("collect more idols to unlock hard mode")
			end
		elseif player.layer == get_entity(normal_sign).layer and distance(player.uid, normal_sign) <= .5 then
			if current_difficulty ~= DIFFICULTY.NORMAL then
				if current_difficulty == DIFFICULTY.EASY then
					toast("Easy mode disabled")
				elseif current_difficulty == DIFFICULTY.HARD then
					toast("Hard mode disabled")
				end
				set_difficulty(DIFFICULTY.NORMAL)
				save_data()
			end
		end
	end
	
	-- Speech bubbles for Tunnel and mode signs.
	if tunnel and player.layer == tunnel.layer and distance(player.uid, tunnel.uid) <= 1 then
		if not tunnel_enter_displayed then
			-- Display a different Tunnel text on entering depending on how many idols have been collected and the hardcore state.
			tunnel_enter_displayed = true
			tunnel_enter_hardcore_state = hardcore_enabled
			tunnel_enter_difficulty = current_difficulty
			if unique_idols_collected() == 0 then
				say(tunnel.uid, "Looking to turn down the heat?", 0, true)
			elseif unique_idols_collected() < 2 then
				say(tunnel.uid, "Come back when you're seasoned for a more difficult challenge.", 0, true)
			elseif hardcore_enabled then
				say(tunnel.uid, "Maybe that was too much. Go back over to disable hardcore mode.", 0, true)
			elseif current_difficulty == DIFFICULTY.HARD then
				say(tunnel.uid, "Maybe that was too much. Go back over to disable hard mode.", 0, true)
			elseif hardcore_previously_enabled then
				say(tunnel.uid, "Back to try again? Step on over.", 0, true)
			elseif hardcore_available() then
				say(tunnel.uid, "This looks too easy for you. Step over there to enable hardcore mode.", 0, true)
			else
				say(tunnel.uid, "You're quite the adventurer. Collect the rest of the idols to unlock a more difficult challenge.", 0, true)
			end
		elseif (not tunnel_exit_displayed or tunnel_exit_hardcore_state ~= hardcore_enabled or tunnel_exit_difficulty ~= current_difficulty) and tunnel_exit_ready and (hardcore_available() or (current_difficulty == DIFFICULTY.EASY and tunnel_exit_difficulty ~=DIFFICULTY.EASY)) then
			-- On exiting, display a Tunnel dialog depending on whether hardcore mode has been enabled/disabled or the difficulty changed.
			cancel_speechbubble()
			tunnel_exit_displayed = true
			tunnel_exit_hardcore_state = hardcore_enabled
			tunnel_exit_difficulty = current_difficulty
			set_timeout(function()
				if hardcore_enabled and not tunnel_enter_hardcore_state or current_difficulty > tunnel_enter_difficulty then
					say(tunnel.uid, "Good luck out there!", 0, true)
				elseif not hardcore_enabled and tunnel_enter_hardcore_state or current_difficulty < tunnel_enter_difficulty then
					say(tunnel.uid, "Take it easy.", 0, true)
				elseif hardcore_enabled or current_difficulty == DIFFICULTY.HARD then
					say(tunnel.uid, "Sticking with it. I like your guts!", 0, true)
				else
					say(tunnel.uid, "Maybe another time.", 0, true)
				end
			end, 1)
		end
	end
	if hardcore_sign and player.layer == get_entity(hardcore_sign).layer and distance(player.uid, hardcore_sign) <= .5 then
		-- When passing by the sign, read out what the sign is for.
		if not player_near_hardcore_sign then
			cancel_speechbubble()
			player_near_hardcore_sign = true
			set_timeout(function()
				if hardcore_enabled then
					say(hardcore_sign, "Hardcore mode (enabled)", 0, true)
				else
					say(hardcore_sign, "Hardcore mode", 0, true)
				end
			end, 1)
		end
	else
		player_near_hardcore_sign = false
	end
	if easy_sign and player.layer == get_entity(easy_sign).layer and distance(player.uid, easy_sign) <= .5 then
		-- When passing by the sign, read out what the sign is for.
		if not player_near_easy_sign then
			cancel_speechbubble()
			player_near_easy_sign = true
			set_timeout(function()
				if current_difficulty == DIFFICULTY.EASY then
					say(easy_sign, "Easy mode (enabled)", 0, true)
				else
					say(easy_sign, "Easy mode", 0, true)
				end
			end, 1)
		end
	else
		player_near_easy_sign = false
	end
	if normal_sign and player.layer == get_entity(normal_sign).layer and distance(player.uid, normal_sign) <= .5 then
		-- When passing by the sign, read out what the sign is for.
		if not player_near_normal_sign then
			cancel_speechbubble()
			player_near_normal_sign = true
			set_timeout(function()
				if current_difficulty == DIFFICULTY.NORMAL then
					say(normal_sign, "Normal mode (enabled)", 0, true)
				else
					say(normal_sign, "Normal mode", 0, true)
				end
			end, 1)
		end
	else
		player_near_normal_sign = false
	end
	if hard_sign and player.layer == get_entity(hard_sign).layer and distance(player.uid, hard_sign) <= .5 then
		-- When passing by the sign, read out what the sign is for.
		if not player_near_hard_sign then
			cancel_speechbubble()
			player_near_hard_sign = true
			set_timeout(function()
				if current_difficulty == DIFFICULTY.HARD then
					say(hard_sign, "Hard mode (enabled)", 0, true)
				else
					say(hard_sign, "Hard mode", 0, true)
				end
			end, 1)
		end
	else
		player_near_hard_sign = false
	end
	if stats_sign and player.layer == get_entity(stats_sign).layer and distance(player.uid, stats_sign) <= .5 then
		-- When passing by the sign, read out what the sign is for.
		if not player_near_stats_sign then
			cancel_speechbubble()
			player_near_stats_sign = true
			set_timeout(function()
				say(stats_sign, "Stats", 0, true)
			end, 1)
		end
	else
		player_near_stats_sign = false
	end
	if legacy_stats_sign and player.layer == get_entity(legacy_stats_sign).layer and distance(player.uid, legacy_stats_sign) <= .5 then
		-- When passing by the sign, read out what the sign is for.
		if not player_near_legacy_stats_sign then
			cancel_speechbubble()
			player_near_legacy_stats_sign = true
			set_timeout(function()
				say(legacy_stats_sign, "Legacy Stats", 0, true)
			end, 1)
		end
	else
		player_near_legacy_stats_sign = false
	end
end, ON.GAMEFRAME)

-- Sorry, Ana...
set_post_entity_spawn(function (entity)
	if has_seen_ana_dead then
		if state.screen == 11 then
			entity.x = 1000
		else
			entity:set_texture(TEXTURE.DATA_TEXTURES_CHAR_CYAN_0)
		end
	end
end, SPAWN_TYPE.ANY, MASK.ANY, ENT_TYPE.CHAR_ANA_SPELUNKY)

---------------
---- /CAMP ----
---------------

--------------------------------------
---- LEVEL SEQUENCE
--------------------------------------

level_sequence.set_on_level_will_load(function(level)
	level.set_difficulty(current_difficulty)
	if level == sunken_city then
		level.set_idol_collected(idols_collected[level.identifier])
		level.set_run_idol_collected(run_idols_collected[level.identifier])
		level.set_ana_callback(function()
			has_seen_ana_dead = true
		end)
	elseif level == ice_caves then
		level.set_idol_collected(idols_collected[level.identifier])
		level.set_run_idol_collected(run_idols_collected[level.identifier])
	end
end)

level_sequence.set_on_post_level_generation(function(level)
	if #players == 0 then return end
	
	players[1].inventory.bombs = initial_bombs
	players[1].inventory.ropes = initial_ropes
	if players[1]:get_name() == "Roffy D. Sloth" or level == ice_caves then
		players[1].health = 1
	else
		players[1].health = 2
	end
end)

level_sequence.set_on_completed_level(function(completed_level, next_level)
	if not next_level then return end
	-- Update stats for the current difficulty mode.
	local current_stats = stats.current_stats()
	local stats_hardcore = hardcore_stats.current_stats()
	local best_level_index = level_sequence.index_of_level(current_stats.best_level)
	local hardcore_best_level_index = level_sequence.index_of_level(stats_hardcore.best_level)
	local current_level_index = level_sequence.index_of_level(next_level)
	-- Update the PB if the new level has not been reached yet.
	if (not best_level_index or current_level_index > best_level_index) and
			not level_sequence.took_shortcut() then
				current_stats.best_level = next_level
	end
	if hardcore_enabled and
			(not hardcore_best_level_index or current_level_index > hardcore_best_level_index) and
			not level_sequence.took_shortcut() then
		stats_hardcore.best_level = next_level
	end
end)

level_sequence.set_on_win(function(attempts, total_time)
	print(f'attempts: {attempts} total_time: {total_time}')
	local current_stats = stats.current_stats()
	local stats_hardcore = hardcore_stats.current_stats()
	if not level_sequence.took_shortcut() then
		local deaths = attempts - 1

		current_stats.completions = current_stats.completions + 1
		if hardcore_enabled then
			stats_hardcore.completions = stats_hardcore.completions + 1
		else
			-- Clear the saved run for the current difficulty if hardcore is disabled.
			local saved_run = current_saved_run()
			saved_run.has_saved_run = false
			saved_run.saved_run_attempts = nil
			saved_run.saved_run_idol_count = nil
			saved_run.saved_run_idols_collected = {}
			saved_run.saved_run_level = nil
			saved_run.saved_run_time = nil
		end
			
		local new_time_pb = false
		if not current_stats.best_time or
				current_stats.best_time == 0 or
				total_time < current_stats.best_time then
			current_stats.best_time = total_time
			new_time_pb = true
			if current_difficulty ~= DIFFICULTY.EASY then
				current_stats.best_time_idol_count = idols
			end
			current_stats.best_time_death_count = deaths
		end

		if hardcore_enabled and
				(not stats_hardcore.best_time or
				stats_hardcore.best_time == 0 or
				total_time < stats_hardcore.best_time) then
			stats_hardcore.best_time = total_time
			new_time_pb = true
			if current_difficulty ~= DIFFICULTY.EASY then
				stats_hardcore.best_time_idol_count = idols
			end
		end
		
		if idols == #level_sequence.levels() and current_difficulty ~= DIFFICULTY.EASY then
			current_stats.max_idol_completions = current_stats.max_idol_completions + 1
			if not current_stats.max_idol_best_time or
					current_stats.max_idol_best_time == 0 or
					total_time < current_stats.max_idol_best_time then
				current_stats.max_idol_best_time = total_time
			end
			if hardcore_enabled then
				stats_hardcore.max_idol_completions = stats_hardcore.max_idol_completions + 1
				if not stats_hardcore.max_idol_best_time or
						stats_hardcore.max_idol_best_time == 0 or
						total_time < stats_hardcore.max_idol_best_time then
					stats_hardcore.max_idol_best_time = total_time
				end
			end
		end
		
		local new_deaths_pb = false
		if not current_stats.least_deaths_completion or
				deaths < current_stats.least_deaths_completion or
				(deaths == current_stats.least_deaths_completion and
				 total_time < current_stats.least_deaths_completion_time) then
			if not current_stats.least_deaths_completion or
					deaths < current_stats.least_deaths_completion then
				new_deaths_pb = true
			end
			current_stats.least_deaths_completion = deaths
			current_stats.least_deaths_completion_time = total_time
			if attempts == 1 then
				current_stats.deathless_completions = current_stats.deathless_completions + 1
			end
		end 

		win_ui.win(
			total_time,
			deaths,
			idols,
			current_difficulty,
			stats,
			hardcore_stats,
			hardcore_enabled,
			#level_sequence.levels(),
			new_time_pb,
			new_deaths_pb)
		bottom_hud.update_win_state(true)
		win_ui.set_on_dismiss(function()
			bottom_hud.update_win_state(false)
		end)
	end 
	warp(1, 1, THEME.BASE_CAMP)
end)

set_callback(function ()
	-- Update the PB if the new level has not been reached yet. This is only really for the first time entering Dwelling,
	-- since other times ON.RESET will not have an increased level from the best_level.
	local current_stats = stats.current_stats()
	local stats_hardcore = hardcore_stats.current_stats()
	local best_level_index = level_sequence.index_of_level(current_stats.best_level)
	local hardcore_best_level_index = level_sequence.index_of_level(stats_hardcore.best_level)
	local current_level = level_sequence.get_run_state().current_level
	local current_level_index = level_sequence.index_of_level(current_level)
	if (not best_level_index or current_level_index > best_level_index) and
			not level_sequence.took_shortcut() then
		current_stats.best_level = current_level
	end
	if hardcore_enabled and
			(not hardcore_best_level_index or current_level_index > hardcore_best_level_index) and
			not level_sequence.took_shortcut() then
		stats_hardcore.best_level = current_level
	end
end, ON.RESET)

local function update_hud_run_entry(continuing)
	local run_state = level_sequence.get_run_state()
	local took_shortcut = level_sequence.took_shortcut()
	bottom_hud.update_run_entry(run_state.initial_level, took_shortcut, continuing)
end

local function update_hud_run_state()
	local run_state = level_sequence.get_run_state()
	bottom_hud.update_run(idols, run_state.attempts, run_state.total_time)
end

level_sequence.set_on_reset_run(function()
	run_idols_collected = {}
	idols = 0
	update_hud_run_state()
end)

level_sequence.set_on_prepare_initial_level(function(level, continuing)
	local saved_run = current_saved_run()
	if continuing then
		idols = saved_run.saved_run_idol_count
		run_idols_collected = saved_run.saved_run_idols_collected
	else
		idols = 0
		run_idols_collected = {}
	end
	update_hud_run_state()
	update_hud_run_entry(continuing)
end)

level_sequence.set_on_level_start(function(level)
	update_hud_run_state()
end)

--------------------------------------
---- /LEVEL SEQUENCE
--------------------------------------

--------------
---- IDOL ----
--------------

set_post_entity_spawn(function(entity)
	-- Set the price to 0 so the player doesn't get gold for returning the idol.
	entity.price = 0
end, SPAWN_TYPE.ANY, 0, ENT_TYPE.ITEM_IDOL, ENT_TYPE.ITEM_MADAMETUSK_IDOL)

function idol_collected_state_for_level(level)
	if run_idols_collected[level.identifier] then
		return IDOL_COLLECTED_STATE.COLLECTED_ON_RUN
	elseif idols_collected[level.identifier] then
		return IDOL_COLLECTED_STATE.COLLECTED
	end
	return IDOL_COLLECTED_STATE.NOT_COLLECTED
end

define_tile_code("idol_reward")
set_pre_tile_code_callback(function(x, y, layer)
	return spawn_idol(
		x,
		y,
		layer,
		idol_collected_state_for_level(level_sequence.get_run_state().current_level),
		current_difficulty == DIFFICULTY.EASY)
end, "idol_reward")

set_vanilla_sound_callback(VANILLA_SOUND.UI_DEPOSIT, VANILLA_SOUND_CALLBACK_TYPE.STARTED, function()
	-- Consider the idol collected when the deposit sound effect plays.
	idols_collected[level_sequence.get_run_state().current_level.identifier] = true
	run_idols_collected[level_sequence.get_run_state().current_level.identifier] = true
	idols = idols + 1
	total_idols = total_idols + 1
	update_hud_run_state()
end)

---------------
---- /IDOL ----
---------------

----------------------------
---- DO NOT SPAWN GHOST ----
----------------------------

set_ghost_spawn_times(-1, -1)

-----------------------------
---- /DO NOT SPAWN GHOST ----
-----------------------------

--------------------
---- SAVE STATE ----
--------------------

-- Manage saving data and keeping the time in sync during level transitions and resets.

function save_data()
	if save_context then
		force_save(save_context)
	end
end

-- Since we are keeping track of time for the entire run even through deaths and resets, we must track
-- what the time was on resets and level transitions.
set_callback(function ()
    if state.theme == THEME.BASE_CAMP then return end
	if level_sequence.run_in_progress() then
		if not hardcore_enabled then
			save_current_run_stats()
		end
		save_data()
	end
end, ON.RESET)

set_callback(function ()
	if state.theme == THEME.BASE_CAMP then return end
	if level_sequence.run_in_progress() and not win_ui.won() then
		save_current_run_stats()
		save_data()
	end
end, ON.TRANSITION)

-- Saves the current state of the run so that it can be continued later if exited.
function save_current_run_stats()
	local run_state = level_sequence.get_run_state()
	-- Save the current run only if there is a run in progress that did not start from a shorcut, and harcore mode is disabled.
	if not level_sequence.took_shortcut() and
			not hardcore_enabled and
			state.theme ~= THEME.BASE_CAMP and
			level_sequence.run_in_progress() then
		local saved_run = current_saved_run()
		saved_run.saved_run_attempts = run_state.attempts
		saved_run.saved_run_idol_count = idols
		saved_run.saved_run_level = run_state.current_level
		saved_run.saved_run_time = run_state.total_time
		saved_run.saved_run_idols_collected = run_idols_collected
		saved_run.has_saved_run = true
	end
end

set_callback(function()
	if level_sequence.run_in_progress() and state.theme ~= THEME.BASE_CAMP then
		-- This doesn't actually save to file every frame, it just updates the properties that will be saved.
		save_current_run_stats()
	end
end, ON.FRAME)

---------------------
---- /SAVE STATE ----
---------------------

--------------------------
---- STATE MANAGEMENT ----
--------------------------

-- Leaving these variables set between resets can lead to undefined behavior due to the high likelyhood of entities being reused.
function clear_variables()
	continue_door = nil

	hard_sign = nil
	easy_sign = nil
	normal_sign = nil
	hardcore_sign = nil
	stats_sign = nil
	legacy_stats_sign = nil
	tunnel_x = nil
	tunnel_y = nil
	tunnel_layer = nil
	tunnel = nil
	
	player_near_easy_sign = false
	player_near_hard_sign = false
	player_near_normal_sign = false
	player_near_hardcore_sign = false
end

set_callback(function()
	clear_variables()
end, ON.PRE_LOAD_LEVEL_FILES)

---------------------------
---- /STATE MANAGEMENT ----
---------------------------

-------------------
---- SAVE DATA ----
-------------------

set_callback(function (ctx)
    local load_data_str = ctx:load()

    if load_data_str ~= '' then
        local load_data = json.decode(load_data_str)
		local load_version = load_data.version
		if load_data.difficulty then
			set_difficulty(load_data.difficulty)
		end
		if not load_version then 
			normal_stats.best_time = load_data.best_time
			normal_stats.best_time_idol_count = load_data.best_time_idols
			normal_stats.best_time_death_count = load_data.best_time_death_count
			normal_stats.best_level = level_sequence.levels()[load_data.best_level+1]
			normal_stats.completions = load_data.completions or 0
			normal_stats.max_idol_completions = load_data.max_idol_completions or 0
			normal_stats.max_idol_best_time = load_data.max_idol_best_time or 0
			normal_stats.deathless_completions = load_data.deathless_completions or 0
			normal_stats.least_deaths_completion = load_data.least_deaths_completion
			normal_stats.least_deaths_completion_time = load_data.least_deaths_completion_time
		elseif load_version == '1.3' then
			local function legacy_stat_convert(stats)
				local new_stats = {}
				for k,v in pairs(stats) do new_stats[k] = v end
				local best_level = stats.best_level
				if best_level then
					if best_level == 3 then
						best_level = 4
					end
					new_stats.best_level = level_sequence.levels()[best_level + 1]
				end
				return new_stats
			end
			if load_data.stats then
				legacy_stats.normal = legacy_stat_convert(load_data.stats)
			end
			if load_data.easy_stats then
				legacy_stats.easy = legacy_stat_convert(load_data.easy_stats)
			end
			if load_data.hard_stats then
				legacy_stats.hard = legacy_stat_convert(load_data.hard_stats)
			end
			if load_data.hardcore_stats then
				legacy_hardcore_stats.normal = legacy_stat_convert(load_data.hardcore_stats)
			end
			if load_data.hardcore_stats_easy then
				legacy_hardcore_stats.easy = legacy_stat_convert(load_data.hardcore_stats_easy)
			end
			if load_data.hardcore_stats_hard then
				legacy_hardcore_stats.hard = legacy_stat_convert(load_data.hardcore_stats_hard)
			end
		else
			local function stat_convert(stats)
				local new_stats = {}
				for k,v in pairs(stats) do new_stats[k] = v end
				if stats.best_level then
					new_stats.best_level = level_sequence.levels()[stats.best_level + 1]
				end
				return new_stats
			end
			if load_data.stats then
				stats.normal = stat_convert(load_data.stats)
			end
			if load_data.easy_stats then
				stats.easy = stat_convert(load_data.easy_stats)
			end
			if load_data.hard_stats then
				stats.hard = stat_convert(load_data.hard_stats)
			end
			if load_data.legacy_stats then
				legacy_stats.normal = stat_convert(load_data.legacy_stats)
			end
			if load_data.legacy_easy_stats then
				legacy_stats.easy = stat_convert(load_data.legacy_easy_stats)
			end
			if load_data.legacy_hard_stats then
				legacy_stats.hard = stat_convert(load_data.legacy_hard_stats)
			end
			
			
			if load_data.hardcore_stats then
				hardcore_stats.normal = stat_convert(load_data.hardcore_stats)
			end
			if load_data.hardcore_stats_easy then
				hardcore_stats.easy = stat_convert(load_data.hardcore_stats_easy)
			end
			if load_data.hardcore_stats_hard then
				hardcore_stats.hard = stat_convert(load_data.hardcore_stats_hard)
			end
			
			if load_data.legacy_hardcore_stats then
				legacy_hardcore_stats.normal = stat_convert(load_data.legacy_hardcore_stats)
			end
			if load_data.legacy_hardcore_stats_easy then
				legacy_hardcore_stats.easy = stat_convert(load_data.legacy_hardcore_stats_easy)
			end
			if load_data.legacy_hardcore_stats_hard then
				legacy_hardcore_stats.hard = stat_convert(load_data.legacy_hardcore_stats_hard)
			end
		end

		idols_collected = load_data.idol_levels
		total_idols = load_data.total_idols
		set_hardcore_enabled(load_data.hardcore_enabled)
		hardcore_previously_enabled = load_data.hpe
		
		function load_saved_run_data(saved_run, saved_run_data)
			saved_run.has_saved_run = saved_run_data.has_saved_run or not load_version
			saved_run.saved_run_level = level_sequence.levels()[saved_run_data.level+1]
			saved_run.saved_run_attempts = saved_run_data.attempts
			saved_run.saved_run_idol_count = saved_run_data.idols
			saved_run.saved_run_time = saved_run_data.run_time
			saved_run.saved_run_idols_collected = saved_run_data.idol_levels
		end
		
		local easy_saved_run_data = load_data.easy_saved_run
		local saved_run_data = load_data.saved_run_data
		local hard_saved_run_data = load_data.hard_saved_run
		if saved_run_data then
			load_saved_run_data(normal_saved_run, saved_run_data)
		end
		if easy_saved_run_data then
			load_saved_run_data(easy_saved_run, easy_saved_run_data)
			print(inspect(easy_saved_run))
		end
		if hard_saved_run_data then
			load_saved_run_data(hard_saved_run, hard_saved_run_data)
		end
		has_seen_ana_dead = load_data.has_seen_ana_dead
    end
end, ON.LOAD)

function force_save(ctx)
	function saved_run_datar(saved_run)
		if not saved_run or not saved_run.has_saved_run then return nil end
		local saved_run_data = {
			has_saved_run = saved_run.has_saved_run,
			level = level_sequence.index_of_level(saved_run.saved_run_level) - 1,
			attempts = saved_run.saved_run_attempts,
			idols = saved_run.saved_run_idol_count,
			idol_levels = saved_run.saved_run_idols_collected,
			run_time = saved_run.saved_run_time,
		}
		return saved_run_data
	end
	local normal_saved_run_data = saved_run_datar(normal_saved_run)
	local easy_saved_run_data = saved_run_datar(easy_saved_run)
	local hard_saved_run_data = saved_run_datar(hard_saved_run)
	local function convert_stats(stats)
		if not stats then return nil end
		local new_stats = {}
		for k,v in pairs(stats) do new_stats[k] = v end
		local best_level = level_sequence.index_of_level(stats.best_level)
		if best_level then
			new_stats.best_level = best_level - 1
		else
			new_stats.best_level = nil
		end
		return new_stats
	end
    local save_data = {
		version = '1.5',
		idol_levels = idols_collected,
		total_idols = total_idols,
		saved_run_data = normal_saved_run_data,
		easy_saved_run = easy_saved_run_data,
		hard_saved_run = hard_saved_run_data,
		stats = convert_stats(stats.normal),
		easy_stats = convert_stats(stats.easy),
		hard_stats = convert_stats(stats.hard),
		legacy_stats = convert_stats(legacy_stats.normal),
		legacy_easy_stats = convert_stats(legacy_stats.easy),
		legacy_hard_stats = convert_stats(legacy_stats.hard),
		has_seen_ana_dead = has_seen_ana_dead,
		hardcore_enabled = hardcore_enabled,
		difficulty = current_difficulty,
		hpe = hardcore_previously_enabled,
		hardcore_stats = convert_stats(hardcore_stats.normal),
		hardcore_stats_easy = convert_stats(hardcore_stats.easy),
		hardcore_stats_hard = convert_stats(hardcore_stats.hard),
		legacy_hardcore_stats = convert_stats(legacy_hardcore_stats.normal),
		legacy_hardcore_stats_easy = convert_stats(legacy_hardcore_stats.easy),
		legacy_hardcore_stats_hard = convert_stats(legacy_hardcore_stats.hard),
    }

    ctx:save(json.encode(save_data))
end
	
set_callback(function (ctx)
	save_context = ctx
	force_save(ctx)
end, ON.SAVE)

--------------------
---- /SAVE DATA ----
--------------------

set_hardcore_enabled(hardcore_enabled)
set_difficulty(current_difficulty)
