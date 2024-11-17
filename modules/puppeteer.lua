-- Written by Ton, with love. Feel free to modify, consider this under the MIT license.

--[[
    PUPPETEER MODULE
]]

local async = require("async_actions")
local lqr = require("lqr")
local utils = require("utils")
local pretty = require("cc.pretty")

local puppeteer = setmetatable({}, {})

local MAX_RPM = 64             -- Maybe set it to 128.
local YAW_DEGREE_THRESHOLD = 1 -- Is 1 degree too much or too little?

function puppeteer.init(dt)
    puppeteer.dt = dt
    lqr.init(puppeteer.dt)
end

--- @TODO: confirm if this actually works correctly in-game.
--- @param comp_pos table Vector
--- @param target_pos table Vector
--- @return number result In degrees
local function calculate_yaw(comp_pos, target_pos)
    local delta_x = target_pos.x - comp_pos.x
    local delta_z = target_pos.z - comp_pos.z
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

--- Note: This assumes everything is in degrees, not radians.
--- @param desired_yaw number
--- @param comp_info table
--- @param rot_controller table Peripheral
--- @param threshold number? Optional
--- @return boolean?
local function manage_target_rpm(desired_yaw, comp_info, rot_controller, threshold)
    local current_yaw = comp_info["orientation"]["yaw"]
    local delta_yaw = (desired_yaw - current_yaw + 180) % 360 - 180
    local omega_yaw = comp_info["omega"]["yaw"] * puppeteer.dt / 20 -- math.deg(ship.getOmega().y); degrees/tick
    local new_rpm = utils.round(lqr.get_turret_yaw_rpm(delta_yaw, omega_yaw))

    -- Note: It's very important to round the rpm, as otherwise it'd be the rpm checks wouldn't work
    -- properly, leading to this just about never returning true and lots of unnecessary peripheral calls.
    if threshold and delta_yaw < threshold and new_rpm == 0 then return true end
    if rot_controller.getTargetSpeed() ~= new_rpm then
        utils.run_async(
            rot_controller.setTargetSpeed,
            utils.clamp(new_rpm, -MAX_RPM, MAX_RPM)
        )
    end
end

--- Rotates the turret until it faces the target.
--- @param comp table
--- @param target table Vector or component
--- @param timeout number?
function puppeteer.aim_at(comp, target, timeout)
    error("Not implemented.")
    return async.action().create(function()
        local target_pos
        local is_vec = is_vector(target)
        if is_vec then target_pos = target end
        local rot_controller = comp.get_rotational_controller()
        local is_done
        repeat
            local comp_info = comp.get_info()
            local comp_pos = utils.tbl_to_vec(comp_info["position"])
            if not comp_info then goto continue end
            if not is_vec then
                local target_comp_info = target.get_info()
                if not target_comp_info then goto continue end
                target_pos = utils.tbl_to_vec(target_comp_info["position"])
            end

            is_done = manage_target_rpm(
                calculate_yaw(comp_pos, target_pos),
                comp_info,
                rot_controller,
                YAW_DEGREE_THRESHOLD
            )

            ::continue::
            async.pause()
        until is_done
    end, timeout)
end

--- Rotates the turret such that it faces the target and keeps it that way until told otherwise. Example usage:
--- ```
--- local action = puppeteer.lock_on(comp, target, timeout)
--- action.terminate()
--- ```
--- @param comp table Component
--- @param target table Vector or component
--- @param timeout number?
--- @return table
function puppeteer.lock_on(comp, target, timeout)
    return async.action().create(function()
        local target_pos
        local is_vec = is_vector(target)
        if is_vec then target_pos = target end
        local rot_controller = comp.get_rotational_controller()

        while true do
            local comp_info = comp.get_info()
            local comp_pos = utils.tbl_to_vec(comp_info["position"])
            if not comp_info then goto continue end
            if not is_vec then
                local target_comp_info = target.get_info()
                if not target_comp_info then goto continue end
                target_pos = utils.tbl_to_vec(target_comp_info["position"])
            end

            manage_target_rpm(calculate_yaw(comp_pos, target_pos), comp_info, rot_controller)

            ::continue::
            async.pause()
        end
    end, timeout)
end

--- Rotates the turret until its yaw is the same as its parent.
--- @param comp table Component
--- @param timeout number?
function puppeteer.turret_to_idle(comp, timeout)
    return async.action().create(function()
        local parent = comp.get_parent()
        assert(parent ~= nil, "Component " .. comp.get_name() .. " has no parent!")
        local rot_controller = comp.get_rotational_controller()
        local is_done
        repeat
            local comp_info = comp.get_info()
            local parent_info = parent.get_info()

            if not comp_info then goto continue end
            if not parent_info then goto continue end

            is_done = manage_target_rpm(
                parent_info["orientation"]["yaw"],
                comp_info,
                rot_controller,
                YAW_DEGREE_THRESHOLD
            )

            ::continue::
            async.pause()
        until is_done
    end, timeout)
end

local function fire_continuous(weapon, duration)
    -- Table being passed by reference is really covering my ass here.
    assert(weapon.get_type() == "continuous", "Weapon is not continuous!")
    return async.action().create(function()
        local relay = weapon.get_relay()
        local links = utils.ensure_is_table(weapon.get_links())
        for _, link in pairs(links) do relay.setAnalogOutput(link, weapon.get_fire_rate()) end
        async.pause(duration)
        for _, link in pairs(links) do relay.setOutput(link, false) end
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
        local relay = weapon.get_relay()
        local links = utils.ensure_is_table(weapon.get_links())
        for _, link in pairs(links) do relay.setOutput(link, true) end
        weapon.set_time_last_fired(utils.current_time_seconds())
        async.pause(0.25) -- Just on/off shenanigans.
        for _, link in pairs(links) do relay.setOutput(link, false) end
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
        act = duration and fire_non_continuous_duration(weapon, duration) or fire_non_continuous(weapon)
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
--- @return table
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
        for _, name in pairs(comp.get_field_all("name")) do
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
        for _, name in pairs(comp.get_field_all("name")) do
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
        for name, pos in pairs(comp.get_field_all("start_pos")) do
            print("vs " .. name .. " teleport " .. pos.x .. " " .. pos.y .. " " .. pos.z)
            -- commands.exec("vs " .. name .. " teleport " .. pos.x .. " " .. pos.y .. " " .. pos.z)
        end
        puppeteer.freeze(comp)
    end)
end

return puppeteer
