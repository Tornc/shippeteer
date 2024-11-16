-- Written by Ton, with love. Feel free to modify, consider this under the MIT license.

--[[
    PUPPETEER MODULE
]]

local async = require("async_actions")
local utils = require("utils")

local pretty = require("cc.pretty")

local puppeteer = setmetatable({}, {})

--- @TODO: some update function OR put that stuff in the component module.

--- @TODO: confirm if this actually works correctly in-game.
local function calculate_yaw(comp_x, comp_z, target_x, target_z)
    local delta_x = target_x - comp_x
    local delta_z = target_z - comp_z
    return math.deg(math.atan2(delta_z, delta_x))
end

--- Only works because Vector has the metamethod(?) __name.
--- @param var any
--- @return boolean
local function is_vector(var)
    return type(var) == "table" and getmetatable(var).__name == "vector"
end

function puppeteer.move_to(comp, pos, reverse, timeout)
    error("Not implemented.")
end

--- @param comp table
--- @param waypoints table Format: `{vector1:, {vector2, true}, ...}`
--- @param timeout number?
function puppeteer.path_move_to(comp, waypoints, timeout)
    return async.action().create(function()
        for _, waypoint in pairs(waypoints) do
            local pos, reverse
            if waypoint[2] then
                pos, reverse = waypoint[1], waypoint[2]
            else
                pos = waypoint
            end
            async.pause_until_terminated(puppeteer.move_to(comp, pos, reverse))
        end
    end, timeout)
end

--- comment
--- @param comp any
--- @param target table Vector or component
--- @param timeout any
function puppeteer.aim_at(comp, target, timeout)
    error("Not implemented.")
end

--- comment
--- @param comp any
--- @param target table Vector or component
--- @param timeout any
--- @return table
--- @TODO actually, where the FUCK do we get veh_pos from?
--- @TODO OR: target_pos -> target, which can be vector() or a component --> is_vector()
function puppeteer.lock_on(comp, target, timeout)
    error("Not implemented.")
    return async.action().create(function()
        error("Not implemented.")
        while true do

        end
    end, timeout)
end

function puppeteer.turret_to_idle(comp, timeout)
    error("Not implemented.")
end

local function fire_continuous(weapon, duration)
    -- Table being passed by reference is really covering my ass here.
    assert(weapon.get_type() == "continuous", "Weapon is not continuous!")
    return async.action().create(function()
        local links = utils.ensure_is_table(weapon.get_links())
        for _, link in pairs(links) do rs.setAnalogOutput(link, weapon.get_fire_rate()) end
        async.pause(duration)
        for _, link in pairs(links) do rs.setOutput(link, false) end
    end)
end

--- @param weapon table
--- @param end_time number? Optional
--- @return table
local function fire_non_continuous(weapon, end_time)
    assert(weapon.get_type() == "non_continuous", "Weapon is not non_continuous!")
    return async.action().create(function()
        -- Wait until reloaded
        while utils.current_time_seconds() < weapon.get_time_last_fired() + weapon.get_reload_time() do
            if end_time and utils.current_time_seconds() > end_time then return end
            async.pause()
        end
        -- Firing sequence.
        local links = utils.ensure_is_table(weapon.get_links())
        for _, link in pairs(links) do rs.setOutput(link, true) end
        weapon.set_time_last_fired(utils.current_time_seconds())
        async.pause(0.25) -- Just on/off shenanigans.
        for _, link in pairs(links) do rs.setOutput(link, false) end
    end)
end

local function fire_non_continuous_duration(weapon, duration)
    assert(weapon.get_type() == "non_continuous", "Weapon is not non_continuous!")
    return async.action().create(function()
        local current_time = utils.current_time_seconds()
        local end_time = current_time + duration
        while current_time < end_time do
            async.pause_until_terminated(fire_non_continuous(weapon, end_time))
            current_time = utils.current_time_seconds()
        end
    end)
end

local function select_fire_action(weapon, duration)
    local act
    local weapon_type = weapon.get_type()
    if weapon_type == "continuous" then
        act = fire_continuous(weapon, duration)
    end
    if weapon_type == "non_continuous" then
        if not duration then
            act = fire_non_continuous(weapon)
        else
            act = fire_non_continuous_duration(weapon, duration)
        end
    end
    return act
end

local function fire_all(comp, duration)
    return async.action().create(function()
        local sub_actions = {}
        for _, weapon in pairs(comp.weapons) do
            local sub_action = select_fire_action(weapon, duration)
            table.insert(sub_actions, sub_action)
        end
        async.pause_until_terminated(table.unpack(sub_actions))
    end)
end

--- @param comp table
--- @param weapon_name string? If nil, then fire all weapons.
--- @param duration number Required if your component has a continuous weapon.
--- @param timeout number?
--- @return table
function puppeteer.fire(comp, weapon_name, duration, timeout)
    return async.action().create(function()
        local act
        if not weapon_name then
            act = fire_all(comp, duration)
        else
            local weapon = comp.get_weapon(weapon_name)
            assert(weapon ~= nil, "Weapon \"" .. weapon_name .. "\" doesn't exist!")
            act = select_fire_action(weapon, duration)
        end
        async.pause_until_terminated(act)
    end, timeout)
end

--- @param comp table
--- @param target table Vector or component
--- @param fire_function function Silly detail: `fire_function` can also be something completely unrelated to `fire()`.
--- @param fire_parameters table Parameters of the fire function in the form of: {p1, p2, ...}.
--- @param timeout number?
function puppeteer.fire_at(comp, target, fire_function, fire_parameters, timeout)
    return async.action().create(function()
        async.pause_until_terminated(puppeteer.aim_at(comp, target))
        local lock_on_action = puppeteer.lock_on(comp, target)
        local fire_action = fire_function(table.unpack(fire_parameters))
        async.pause_until_terminated(fire_action)
        lock_on_action.terminate()
    end, timeout)
end

--- `/vs ship set-static true` for component and all its children.
--- @param comp table
--- @return table
--- @TODO: Swap print() out for commented code.
function puppeteer.freeze(comp)
    return async.action().create(function()
        for _, name in pairs(comp.get_field("name")) do
            print("vs " .. name .. " set-static true")
            -- commands.exec("vs " .. name .. " set-static true")
        end
    end)
end

--- `/vs ship set-static false` for component and all its children.
--- @param comp table
--- @return table
--- @TODO: Swap print() out for commented code.
function puppeteer.unfreeze(comp)
    return async.action().create(function()
        for _, name in pairs(comp.get_field("name")) do
            print("vs " .. name .. " set-static false")
            -- commands.exec("vs " .. name .. " set-static false")
        end
    end)
end

--- `/vs ship teleport x y z` for component and all its children.
--- @param comp table
--- @return table
--- @TODO: Swap print() out for commented code.
function puppeteer.reset(comp)
    return async.action().create(function()
        async.pause_until_terminated(puppeteer.unfreeze(comp))
        for name, pos in pairs(comp.get_field("start_pos")) do
            print("vs " .. name .. " teleport " .. pos.x .. " " .. pos.y .. " " .. pos.z)
            -- commands.exec("vs " .. name .. " teleport " .. pos.x .. " " .. pos.y .. " " .. pos.z)
        end
        puppeteer.freeze(comp)
    end)
end

return puppeteer
