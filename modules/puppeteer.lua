-- Written by Ton, with love. Feel free to modify, consider this under the MIT license.

local async = require("async_actions")
local lqr = require("lqr")
local matrix = require("matrix")
local pid = require("pid")
local utils = require("utils")
local pretty = require("cc.pretty")

--[[
    PUPPETEER MODULE
]]

local puppeteer = setmetatable({}, {})

--[[ CONSTANTS / SETTINGS ]]

local MAX_RPM = 256
local TURRET_YAW_THRESHOLD = 1
local HULL_YAW_THRESHOLD = 1
local HULL_YAW_ROTATE_THRESHOLD = 20
local ARRIVAL_DISTANCE_THESHOLD = 4

local TURRET_PID_CONTROLLER = pid.controller().create(0.5, 0.45, 0.07)

--[[ FUNCTIONS ]]

function puppeteer.init(dt)
    puppeteer.dt = dt
end

--- I don't understand, but it works now.
--- @param comp_pos table Vector
--- @param target_pos table Vector
--- @return number result In degrees
local function calculate_yaw(comp_pos, target_pos)
    local delta_x = target_pos.x - comp_pos.x
    local delta_z = target_pos.z - comp_pos.z
    return math.deg(math.atan2(delta_x, delta_z))
end

--- @param pos1 table Vector
--- @param pos2 table Vector
--- @param threshold number
--- @return boolean
local function has_arrived(pos1, pos2, threshold)
    if pos1 == nil or pos2 == nil then return false end
    if (pos1 - pos2):length() < threshold then return true end
    return false
end

--- Only works because Vector has the metamethod(?) __name.
--- @param var any
--- @return boolean
local function is_vector(var)
    return type(var) == "table" and getmetatable(var).__name == "vector"
end

--- # IMPORTANT: this only works for tracked vehicles, not wheeled vehicles! (atm)
--- @param comp table
--- @param pos table Vector
--- @param reverse boolean?
--- @param line integer?
--- @param timeout number?
--- @return table
function puppeteer.move_to(comp, pos, reverse, line, timeout)
    return async.action().create(function()
        if reverse == nil then reverse = false end
        local relay = comp.get_relay()
        local controls = comp.get_controls()
        -- We do this mildly convoluted 'intermediary' table step to reduce the
        -- amount of (relay) peripheral calls needed.
        local control_states = {}
        while true do
            -- Assume no movement initially.
            for key, _ in pairs(controls) do control_states[key] = false end

            local comp_info = comp.get_info()
            if comp_info then
                local comp_pos = utils.tbl_to_vec(comp_info["position"])
                comp_pos.y = 0 -- Discard y because we work in 2D.
                if has_arrived(comp_pos, pos, ARRIVAL_DISTANCE_THESHOLD) then break end
                -- We flip the desired_yaw if we're going in reverse, because the rear
                -- must face towards the destination.
                local desired_yaw = calculate_yaw(comp_pos, pos)
                desired_yaw = reverse and ((desired_yaw + 360) % 360) - 180 or desired_yaw
                local current_yaw = comp_info["orientation"]["yaw"]
                local delta_yaw = ((desired_yaw - current_yaw + 180) % 360) - 180

                -- This dual threshold shenanigans is to avoid constantly turning if
                -- delta_yaw inches _just_ above the threshold for turning.
                -- Therefore, the threshold for deciding when to rotate is higher, but
                -- if we are actually rotating, the threshold to stop is lower.
                if math.abs(delta_yaw) > HULL_YAW_ROTATE_THRESHOLD or
                    (
                        math.abs(delta_yaw) > HULL_YAW_THRESHOLD and
                        (control_states["left"] or control_states["right"])
                    )
                then
                    control_states["right"] = delta_yaw < 0
                    control_states["left"] = delta_yaw > 0
                else
                    control_states["reverse"] = reverse
                    control_states["forward"] = not reverse
                end
            end

            -- Track sides that have already been set to ensure we take `true` for overlaps
            local sides_values = {}
            for link, links in pairs(controls) do
                -- Get value of this link (side).
                local link_bool = control_states[link] or false
                -- Ensure `true` values don't get overwritten.
                for _, side in pairs(utils.ensure_is_table(links)) do
                    sides_values[side] = sides_values[side] or link_bool
                end
            end

            -- Actual peripheral calls to set the redstone links.
            for side, value in pairs(sides_values) do
                relay.setOutput(side, value)
            end
            async.pause()
        end

        -- Required because loop termination happens before the peripheral calls.
        for _, links in pairs(controls) do
            for _, link in pairs(utils.ensure_is_table(links)) do
                relay.setOutput(link, false)
            end
        end
    end, line, timeout)
end

--- @param comp table
--- @param waypoints table Format: `{vector1:, {vector2, true}, ...}`
--- @param line integer?
--- @param timeout number?
--- @return table
function puppeteer.path_move_to(comp, waypoints, line, timeout)
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
    end, line, timeout)
end

--- @param hull table
--- @return number
local function parent_control_direction(hull)
    local direction, left, right
    -- Ugly instance-esque check.
    if type(hull.get_track_rpm()) == "number" then
        -- Determine the rpm of the left and right tracks.
        local relay = hull.get_relay()
        local controls = hull.get_controls()
        local track_rpm = hull.get_track_rpm()

        local activated_sides = {}
        for _, side in pairs(rs.getSides()) do
            -- Note that getOutput() won't work when feeding in redstone externally.
            if relay.getOutput(side) or relay.getInput(side) then
                table.insert(activated_sides, side)
            end
        end
        local control
        -- Sorting is important, otherwise we can't compare properly.
        table.sort(activated_sides)
        for ctrl, sides in pairs(controls) do
            local sides_as_tbl = utils.ensure_is_table(sides)
            if #sides_as_tbl > 1 then
                table.sort(utils.ensure_is_table(sides))
            end
            if utils.compare_tables(sides_as_tbl, activated_sides) then
                control = ctrl
                break
            end
        end

        if control == "forward" then
            left, right = track_rpm, track_rpm
        end
        if control == "left" then
            left, right = -track_rpm, track_rpm
        end
        if control == "right" then
            left, right = track_rpm, -track_rpm
        end
        if control == "reverse" then
            left, right = -track_rpm, -track_rpm
        end
    end

    -- direction < 0 --> rotating left
    -- direction == 0 --> no rotating
    -- direction > 0 --> rotating right
    if left ~= nil and right ~= nil then
        direction = left == right and 0 or left - right
    end

    return direction
end

--- Note: This assumes everything is in degrees, not radians.
--- @param desired_yaw number
--- @param comp table
--- @param rot_controller table Peripheral
--- @param threshold number? Optional
--- @return boolean?
local function manage_target_rpm(desired_yaw, comp, rot_controller, threshold)
    local comp_info = comp.get_info()
    local parent = comp.get_parent()
    local parent_info
    local parent_ctrl_dir
    if parent then
        parent_info = comp.get_parent().get_info()
        parent_ctrl_dir = parent_control_direction(parent)
    end
    parent_ctrl_dir = parent_ctrl_dir or 0 -- Assume no movement if there's no parent.

    local current_yaw = comp_info["orientation"]["yaw"]
    local delta_yaw = (desired_yaw - current_yaw + 180) % 360 - 180
    -- We need to take hull dynamics into account too.
    local comp_omega_yaw = comp_info["omega"]["yaw"] * puppeteer.dt -- Degrees/second -> Degrees/tick
    local parent_omega_yaw = parent_info and parent_info["omega"]["yaw"] * puppeteer.dt or 0

    -- local lqr_output = lqr.get_turret_yaw_rpm(delta_yaw, comp_omega_yaw)
    local pid_output = TURRET_PID_CONTROLLER.get_output(delta_yaw)
    -- local feedforward_control = 0.05 * parent_ctrl_dir
    local feedforward_control = 0.0775 * parent_ctrl_dir

    local output = pid_output + feedforward_control
    local new_rpm = utils.round(output)

    -- Note: It's very important to round the rpm, as otherwise  the rpm checks wouldn't work properly,
    -- leading to this just about never returning true and lots of unnecessary peripheral calls. This
    -- is bad here, because rot_controller calls freeze the script (yielding), requiring creating a
    -- coroutine for every call.
    local current_rpm = rot_controller.getTargetSpeed()
    if threshold and math.abs(delta_yaw) < threshold and current_rpm == 0 then return true end
    if current_rpm ~= new_rpm then
        utils.run_async(
            rot_controller.setTargetSpeed,
            utils.clamp(new_rpm, -MAX_RPM, MAX_RPM)
        )
    end
end

--- Rotates the turret until it faces the target.
--- @param comp table
--- @param target table Vector or component
--- @param line integer?
--- @param timeout number?
--- @return table
function puppeteer.aim_at(comp, target, line, timeout)
    return async.action().create(function()
        local target_pos
        local is_vec = is_vector(target)
        if is_vec then target_pos = target end
        local rot_controller = comp.get_rotational_controller()
        local is_done
        repeat
            local comp_info = comp.get_info()
            local comp_pos = comp_info and utils.tbl_to_vec(comp_info["position"])
            if not comp_info then goto continue end -- Really stupid placement, but otherwise it'll give scope error.
            if not is_vec then
                local target_comp_info = target.get_info()
                if not target_comp_info then goto continue end
                target_pos = utils.tbl_to_vec(target_comp_info["position"])
            end

            --- @TODO: take velocity into account; calculate future_comp_pos
            is_done = manage_target_rpm(
                calculate_yaw(comp_pos, target_pos),
                comp,
                rot_controller,
                TURRET_YAW_THRESHOLD
            )

            ::continue::
            async.pause()
        until is_done
    end, line, timeout)
end

--- Rotates the turret such that it faces the target and keeps it that way until told otherwise.
--- <br> Example usage:
--- ```
--- local action = puppeteer.lock_on(comp, target, timeout)
--- action.terminate()
--- puppeteer.stop_rot_controller(comp) -- Ensures your turret does not rotate further.
--- puppeteer.turret_to_idle(comp, timeout) -- Or use this.
--- ```
--- @param comp table Component
--- @param target number|table Yaw (degrees)/Vector/Component
--- @param line integer?
--- @param timeout number?
--- @return table
function puppeteer.lock_on(comp, target, line, timeout)
    -- This function is identical to aim_at, except for the fact that YAW_DEGREE_THRESHOLD is
    -- not needed. Maybe rewrite both to reduce code duplication.
    return async.action().create(function()
        local rot_controller = comp.get_rotational_controller()
        local desired_yaw, target_pos
        local is_yaw = type(target) == "number"
        local is_vec = is_vector(target)
        if is_yaw then desired_yaw = target end
        if is_vec then target_pos = target end

        while true do
            local comp_info = comp.get_info()
            local comp_pos = comp_info and utils.tbl_to_vec(comp_info["position"])
            if not comp_info then goto continue end -- _sigh_

            --- @TODO: take velocity into account;
            --- calculate future_comp_pos and future_target_pos (if applies)
            if not (is_yaw or is_vec) then -- aka Component
                local target_comp_info = target.get_info()
                if not target_comp_info then goto continue end
                target_pos = utils.tbl_to_vec(target_comp_info["position"])
            end
            -- Debugger freaks out a bit because when setting desired_yaw/target_pos to target,
            -- it thinks the is_yaw and is_vec don't exist.
            --- @diagnostic disable-next-line: param-type-mismatch
            if not is_yaw then desired_yaw = calculate_yaw(comp_pos, target_pos) end
            --- @diagnostic disable-next-line: param-type-mismatch
            manage_target_rpm(desired_yaw, comp, rot_controller)

            ::continue::
            async.pause()
        end
    end, line, timeout)
end

--- Use after terminating lock_on()
--- @param comp table Component
--- @param line integer?
--- @param timeout number?
--- @return table
function puppeteer.stop_rot_controller(comp, line, timeout)
    return async.action().create(function()
        local rot_controller = comp.get_rotational_controller()
        utils.run_async(rot_controller.setTargetSpeed, 0)
    end, line, timeout)
end

--- Rotates the turret in a certain direction at a constant speed. Possible use-case: 
--- the spinning of the T-90M that got pummeled by Bradleys.
--- @param comp table Component
--- @param rpm integer -256 to 256. setTargetSpeed() handles the clamping already.
--- @param duration number? Duration of rotation. Leave as nil to rotate indefinitely. Then you'll have to terminate externally.
--- @param line integer?
--- @param timeout number?
--- @return table
function puppeteer.rotate_turret(comp, rpm, duration, line, timeout)
    return async.action().create(function()
        local rot_controller = comp.get_rotational_controller()
        utils.run_async(rot_controller.setTargetSpeed, rpm)
        if duration then
            async.pause(duration)
            utils.run_async(rot_controller.setTargetSpeed, 0)
        else
            while true do async.pause() end
        end
    end, line, timeout)
end

--- Rotates the turret until its yaw is the same as its parent.
--- @param comp table Component
--- @param line integer?
--- @param timeout number?
--- @return table
function puppeteer.turret_to_idle(comp, line, timeout)
    return async.action().create(function()
        local parent = comp.get_parent()
        assert(parent ~= nil, "Component " .. comp.get_name() .. " has no parent!")
        local rot_controller = comp.get_rotational_controller()
        local is_done
        repeat
            local comp_info = comp.get_info()
            local parent_info = parent.get_info()

            if not (comp_info and parent_info) then goto continue end

            is_done = manage_target_rpm(
                parent_info["orientation"]["yaw"],
                comp,
                rot_controller,
                TURRET_YAW_THRESHOLD
            )

            ::continue::
            async.pause()
        until is_done
    end, line, timeout)
end

--- @param weapon table
--- @param duration number
--- @return table
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
        while utils.time_seconds() < weapon.get_time_last_fired() + weapon.get_reload_time() do
            if end_time and utils.time_seconds() > end_time then return end
            async.pause()
        end
        -- Firing sequence.
        local relay = weapon.get_relay()
        local links = utils.ensure_is_table(weapon.get_links())
        for _, link in pairs(links) do relay.setOutput(link, true) end
        weapon.set_time_last_fired(utils.time_seconds())
        async.pause(0.25) -- Just on/off shenanigans.
        for _, link in pairs(links) do relay.setOutput(link, false) end
    end)
end

--- @param weapon table
--- @param duration number
--- @return table
local function fire_non_continuous_duration(weapon, duration)
    assert(weapon.get_type() == "non_continuous", "Weapon is not non_continuous!")
    return async.action().create(function()
        local current_time = utils.time_seconds()
        local end_time = current_time + duration
        while current_time < end_time do
            async.pause_until_terminated(fire_non_continuous(weapon, end_time))
            current_time = utils.time_seconds()
        end
    end)
end

--- @param weapon table
--- @param duration number
--- @return table
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

--- @param comp table
--- @param duration number
--- @return table
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
--- @param line integer?
--- @param timeout number?
--- @return table
function puppeteer.fire(comp, weapon_name, duration, line, timeout)
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
    end, line, timeout)
end

--- @param comp table
--- @param target table Vector or component
--- @param fire_function function Silly detail: `fire_function` can also be something completely unrelated to `fire()`.
--- @param fire_parameters table Parameters of the fire function in the form of: {p1, p2, ...}.
--- @param line integer?
--- @param timeout number?
--- @return table
function puppeteer.fire_at(comp, target, fire_function, fire_parameters, line, timeout)
    return async.action().create(function()
        async.pause_until_terminated(puppeteer.aim_at(comp, target))
        local lock_on_action = puppeteer.lock_on(comp, target)
        local fire_action = fire_function(table.unpack(fire_parameters))
        async.pause_until_terminated(fire_action)
        lock_on_action.terminate()
    end, line, timeout)
end

--- `/vs ship set-static true` for all components and all their children.
--- @param ... table
--- @return table
function puppeteer.freeze(...)
    local components = { ... }
    return async.action().create(function()
        for _, comp in pairs(components) do
            if type(comp.get_field_all) ~= "function" then
                local name = comp.get_name()
                commands.execAsync("vs set-static " .. name .. " true")
            else
                for _, name in pairs(comp.get_field_all("name")) do
                    commands.execAsync("vs set-static " .. name .. " true")
                end
            end
        end
    end)
end

--- `/vs ship set-static false` for all components and all their children.
--- @param ... table
--- @return table
function puppeteer.unfreeze(...)
    local components = { ... }
    return async.action().create(function()
        for _, comp in pairs(components) do
            if type(comp.get_field_all) ~= "function" then
                local name = comp.get_name()
                commands.execAsync("vs set-static " .. name .. " false")
            else
                for _, name in pairs(comp.get_field_all("name")) do
                    commands.execAsync("vs set-static " .. name .. " false")
                end
            end
        end
    end)
end

--- `/vs ship teleport x y z` for all components and all their children.
--- @param ... table
--- @return table
function puppeteer.reset(...)
    local components = { ... }
    return async.action().create(function()
        for _, comp in pairs(components) do
            if type(comp.get_field_all) ~= "function" then
                local name = comp.get_name()
                local pos = comp.get_start_pos()
                commands.execAsync("vs teleport " .. name .. " " .. pos.x .. " " .. pos.y .. " " .. pos.z)
            else
                for name, pos in pairs(comp.get_field_all("start_pos")) do
                    commands.execAsync("vs teleport " .. name .. " " .. pos.x .. " " .. pos.y .. " " .. pos.z)
                end
            end
            puppeteer.freeze(comp)
        end
    end)
end

return puppeteer
