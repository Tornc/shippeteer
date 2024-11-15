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
            async.pause_until(puppeteer.move_to(comp, pos, reverse))
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

--- @param comp table
--- @param weapon_name string If nil, fire all weapons.
--- @param duration number
--- @param firerate integer Only applies to continuous weapons
function puppeteer.fire(comp, weapon_name, duration, firerate)
    error("Not implemented.")
end

--- @param comp table
--- @param target table Vector or component
--- @param fire_function function Silly detail: `fire_function` can also be something completely unrelated to `fire()`.
--- @param fire_parameters table Parameters of the fire function in the form of: {p1, p2, ...}.
--- @param timeout number?
function puppeteer.fire_at(comp, target, fire_function, fire_parameters, timeout)
    return async.action().create(function()
        async.pause_until(puppeteer.aim_at(comp, target))
        local lock_on_action = puppeteer.lock_on(comp, target)
        local fire_action = fire_function(table.unpack(fire_parameters))
        async.pause_until(fire_action)
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
        async.pause_until(puppeteer.unfreeze(comp))
        for name, pos in pairs(comp.get_field("start_pos")) do
            print("vs " .. name .. " teleport " .. pos.x .. " " .. pos.y .. " " .. pos.z)
            -- commands.exec("vs " .. name .. " teleport " .. pos.x .. " " .. pos.y .. " " .. pos.z)
        end
        puppeteer.freeze(comp)
    end)
end

return puppeteer
