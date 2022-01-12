local sound = require('play_sound')
local clear_embeds = require('clear_embeds')
local DIFFICULTY = require('difficulty')

define_tile_code("skull")

local dwelling = {
    identifier = "dwelling",
    title = "Dwelling",
    theme = THEME.DWELLING,
    width = 6,
    height = 5,
    file_name = "dwell.lvl",
}

local level_state = {
    loaded = false,
    callbacks = {},
}

local overall_state = {
    difficulty = DIFFICULTY.NORMAL,
}

local function update_file_name()
    if overall_state.difficulty == DIFFICULTY.HARD then
        dwelling.file_name = "dwell-hard.lvl"
    elseif overall_state.difficulty == DIFFICULTY.EASY then
        dwelling.file_name = "dwell-easy.lvl"
    else
        dwelling.file_name = "dwell.lvl"
    end
end

dwelling.set_difficulty = function(difficulty)
    overall_state.difficulty = difficulty
    update_file_name()
end

dwelling.load_level = function()
    if level_state.loaded then return end
    level_state.loaded = true

    local skull;
    level_state.callbacks[#level_state.callbacks+1] = set_pre_tile_code_callback(function(x, y, layer)
        local skull_id = spawn_entity(ENT_TYPE.ITEM_SKULL, x, y, layer, 0, 0)
        skull = get_entity(skull_id)
        return true
    end, "skull")

    level_state.callbacks[#level_state.callbacks+1] = set_post_entity_spawn(function (entity)
        entity.health = 10
        --Caveman carries torch
        local torch_uid = spawn_entity(ENT_TYPE.ITEM_TORCH, entity.x, entity.y, entity.layer, 0, 0)
        spawn_entity(ENT_TYPE.ITEM_TORCHFLAME, entity.x, entity.y, entity.layer, 0, 0)
        --get_entity(torch_uid).is_lit = true
        pick_up(entity.uid, torch_uid)
    end, SPAWN_TYPE.ANY, 0, ENT_TYPE.MONS_CAVEMAN)

    -- Creates walls that will be destroyed when the totem_switch is switched. Don't ask why these are called totems, they're just walls.
    local moving_totems = {}
    level_state.callbacks[#level_state.callbacks+1] = set_pre_tile_code_callback(function(x, y, layer)
        clear_embeds.perform_block_without_embeds(function()
            local totem_uid = spawn_entity(ENT_TYPE.FLOOR_GENERIC, x, y, layer, 0, 0)
            moving_totems[#moving_totems + 1] = get_entity(totem_uid)
        end)
        return true
    end, "moving_totem")

    local totem_switch;
    level_state.callbacks[#level_state.callbacks+1] = set_pre_tile_code_callback(function(x, y, layer)
        local switch_id = spawn_entity(ENT_TYPE.ITEM_SLIDINGWALL_SWITCH, x, y, layer, 0, 0)
        totem_switch = get_entity(switch_id)
        return true
    end, "totem_switch")

    local has_activated_totem = false
    level_state.callbacks[#level_state.callbacks+1] = set_callback(function()
        if not totem_switch then return end
        if totem_switch.timer > 0 and not has_activated_totem then
            has_activated_totem = true
            for _, moving_totem in ipairs(moving_totems) do
                kill_entity(moving_totem.uid)
            end
            moving_totems = {}
        end
    end, ON.FRAME)

end

dwelling.unload_level = function()
    if not level_state.loaded then return end

    local callbacks_to_clear = level_state.callbacks
    level_state.loaded = false
    level_state.callbacks = {}
    for _,callback in ipairs(callbacks_to_clear) do
        clear_callback(callback)
    end
end

return dwelling
