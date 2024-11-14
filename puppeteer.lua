-- Written by Ton, with love. Feel free to modify, consider this under the MIT license.

--[[
    PUPPETEER MODULE
]]

local async = require("async_actions")
local utils = require("utils")

local pretty = require("cc.pretty")

local puppeteer = setmetatable({}, {})

--- @TODO: some update function OR put that stuff in the component module.

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

function puppeteer.aim_at(comp, target_pos, timeout)
    error("Not implemented.")
end

function puppeteer.lock_on(comp, target_pos, timeout)
    error("Not implemented.")
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

--- @param comp any
--- @param target_pos any
--- @param fire_action any
--- @param timeout any
--- @TODO if target is a vehicle, then pos_target should be: `function() return veh_pos end` (a variable_ref).
--- @TODO actually, where the FUCK do we get veh_pos from?
function puppeteer.fire_at(comp, target_pos, fire_action, timeout)
    error("Not implemented.")
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
