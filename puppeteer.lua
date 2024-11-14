-- Written by Ton, with love. Feel free to modify, consider this under the MIT license.

--[[
    PUPPETEER MODULE
]]

local async = require("async_actions")
local components = require("components")
local utils = require("utils")

local pretty = require("cc.pretty")

local puppeteer = setmetatable({}, {})

-- TODO: some update function OR put that stuff in the component module.

function puppeteer.move_to(comp, pos, reverse, timeout)
    error("Not implemented.")
end

--- @param comp any
--- @param waypoints table Format: `{vector1:, {vector2, true}, ...}`
--- @param timeout any
function puppeteer.path_move_to(comp, waypoints, timeout)
    error("Not implemented.")
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

-- TODO: Swap print() out for commented code.
--- `/vs ship set-static true` for component and all its children.
--- @param comp table
--- @return table
function puppeteer.freeze(comp)
    return async.action().create(function()
        if comp.child_components then
            for _, name in pairs(comp.get_fields("name")) do
                print("vs " .. name .. " set-static true")
                -- commands.exec("vs " .. name .. " set-static true")
            end
        else
            print("vs " .. comp.name .. " set-static true")
            -- commands.exec("vs " .. comp.name .. " set-static true")
        end
    end)
end

--- `/vs ship set-static false` for component and all its children.
--- @param comp table
--- @return table
function puppeteer.unfreeze(comp)
    return async.action().create(function()
        if comp.child_components then
            for _, name in pairs(comp.get_fields("name")) do
                print("vs " .. name .. " set-static false")
                -- commands.exec("vs " .. name .. " set-static false")
            end
        else
            print("vs " .. comp.name .. " set-static false")
            -- commands.exec("vs " .. comp.name .. " set-static false")
        end
    end)
end

--- `/vs ship teleport x y z` for component and all its children.
--- @param comp table
--- @return table
function puppeteer.reset(comp)
    return async.action().create(function()
        async.pause_until(puppeteer.unfreeze(comp))

        if comp.child_components then
            for name, pos in pairs(comp.get_fields("start_pos")) do
                print("vs " .. name .. " teleport " .. pos.x .. " " .. pos.y .. " " .. pos.z)
                -- commands.exec("vs " .. name .. " teleport " .. pos.x .. " " .. pos.y .. " " .. pos.z)
            end
        else
            if comp.start_pos then
                print("vs " .. comp.name .. " teleport " .. comp.pos.x .. " " .. comp.pos.y .. " " .. comp.pos.z)
                -- commands.exec("vs " .. comp.name .. " teleport " .. comp.pos.x .. " " .. comp.pos.y .. " " .. comp.pos.z)
            end
        end

        puppeteer.freeze(comp)
    end)
end

return puppeteer
