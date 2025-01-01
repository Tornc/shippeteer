-- Written by Ton, with love. Feel free to modify, consider this under the MIT license.

--[[ DEPENDENCIES ]]

package.path = package.path .. ";../modules/?.lua"
local ballistics = require("ballistics")
local networking = require("networking")
local utils = require("utils")
local pretty = require("cc.pretty")

--[[ PERIPHERALS ]]

local MODEM = peripheral.find("modem")

--[[ SETTINGS / CONSTANTS ]]

local T0                                 = 0
local TN                                 = 750
-- Too lazy to do implement fallback trajectory.
local PREFERRED_TRAJECTORY               = false -- true = low, false = high.
local INCOMING_CHANNEL, OUTGOING_CHANNEL = 6060, 6060
local MY_ID                              = "battery_command"
local MAX_LOOP_TIME                      = 2 / 20
local FIRE_MISSION_TIMEOUT               = 60 -- In seconds
local VERSION                            = "0.2"
local DISPLAY_STRING                     = "=][= COMMAND v" .. VERSION .. " =][="
local SLEEP_INTERVAL                     = 6 / 20 -- In ticks

--[[ STATE VARIABLES ]]

local resulting_message = {}

local available_cannons = {}   -- Table of cannon()s
local unavailable_cannons = {} -- Table of cannon()s
local barrage_requests = {}    -- Table in the form of: `{ { id = ..., coordinates = { vector(), ... } }, ... }`
local current_request = {}     -- Table in the form of: `{ id = ..., coordinates = { vector(), ... } }`
local wip_fire_missions = {}   -- Table in the form of: `{ { id = ..., pos = ..., flight_time = ..., fired_time = ..., timeout_time = ... } }`

--[[ DEPENDENCIES SETUP ]]

networking.set_modem(MODEM)
networking.set_channels(INCOMING_CHANNEL, OUTGOING_CHANNEL)
networking.set_id(MY_ID)

--[[ FUNCTIONS ]]

local function cannon()
    local self = setmetatable({}, {})

    --- @param id string
    --- @param position table Vector
    --- @param velocity_ms integer
    --- @param cannon_length integer
    --- @param is_med_cannon boolean
    --- @param min_pitch integer
    --- @param max_pitch integer
    --- @return table
    function self.create(
        id, position, velocity_ms,
        cannon_length, is_med_cannon,
        min_pitch, max_pitch
    )
        self.id = id
        self.position = position
        self.velocity_ms = velocity_ms
        self.cannon_length = cannon_length
        self.is_med_cannon = is_med_cannon
        self.min_pitch = min_pitch
        self.max_pitch = max_pitch
        return self
    end

    --- @param target_pos table Vector
    --- @param trajectory boolean true = low, false = high
    --- @return number? yaw Required yaw
    --- @return number? pitch Required pitch
    --- @return number? t Flight time in ticks
    function self.calculate(target_pos, trajectory)
        local yaw = ballistics.calculate_yaw(self.position, target_pos)
        local distance = utils.vec_drop_axis(target_pos - self.position, "y"):length()
        local target_height = target_pos.y - self.position.y
        local t, pitch = ballistics.calculate_pitch(
            distance,
            self.velocity_ms,
            target_height,
            self.cannon_length,
            T0, TN,
            trajectory,
            self.is_med_cannon
        )
        if not (t or pitch) then return nil, nil, nil end
        if pitch < self.min_pitch or pitch > self.max_pitch then return nil, nil, nil end
        return yaw, pitch, t
    end

    return self
end

--- @param cannons table A table of cannon()s
--- @param new_cannon table cannon()
--- @return boolean has_found Whether new_cannon already exists in cannons
local function find_overwrite_cannon(cannons, new_cannon)
    for i, existing_cannon in ipairs(cannons) do
        if existing_cannon.id == new_cannon.id then
            cannons[i] = new_cannon
            return true
        end
    end
    return false
end

--- @param target table Vector
--- @param spacing integer
--- @param semi_width integer
--- @param semi_height integer
--- @return table coordinates Table of Vectors
local function generate_coordinates(target, spacing, semi_width, semi_height)
    local x_min = target.x - semi_width
    local x_max = target.x + semi_width
    local z_min = target.z - semi_height
    local z_max = target.z + semi_height

    spacing = spacing + 1 -- Compensate for the fact that it's inclusive. (terribly explained)
    local coordinates = {}
    local x_start = target.x - math.floor((x_max - x_min) / (2 * spacing)) * spacing
    local z_start = target.z - math.floor((z_max - z_min) / (2 * spacing)) * spacing
    for x = x_start, x_max, spacing do
        for z = z_start, z_max, spacing do
            table.insert(coordinates, vector.new(x, target.y, z))
        end
    end

    return coordinates
end

--- Message format:
--- ```lua
--- {
---     { ... }, -- Message to all
---     ["Recipient_1"] = { ... },
---     ["Recipient_2"] = { ... },
---     ...
--- }
--- ```
--- @param part any
--- @param recipient string?
local function add_to_message(part, recipient)
    -- Maybe inserting (appending) is better here if it's intended for everyone.
    -- Instead of just replacing.
    resulting_message[recipient or 1] = part
end

-- [[ STATE ]]

local function process_inbox()
    for id, _ in pairs(networking.get_inbox()) do
        local packet = networking.get_packet(id)
        local msg = packet["message"]
        if networking.has_been_read(id) then goto continue end
        networking.mark_as_read(id)
        -- Note: this overwrites existing cannons with more up to date information.
        if msg["type"] == "cannon_info" then
            local new_cannon = cannon().create(
                id, utils.tbl_to_vec(msg["position"]), msg["velocity_ms"],
                msg["cannon_length"], msg["cannon_type"] == "medium",
                msg["min_pitch"], msg["max_pitch"]
            )
            -- This is dumb.
            local found = find_overwrite_cannon(available_cannons, new_cannon)
                or find_overwrite_cannon(unavailable_cannons, new_cannon)
            if not found then table.insert(available_cannons, new_cannon) end
        end
        if msg["type"] == "fire_mission_completion" then
            -- We can assume that the oldest entry with a matching id but without
            -- a fired_time, is the one that has just been completed.
            for _, fire_mission in pairs(wip_fire_missions) do
                if fire_mission.id == id and fire_mission.fired_time == nil then
                    fire_mission.fired_time = packet["time"]
                    break
                end
            end
        end
        if msg["type"] == "has_reloaded" then
            for i, can in ipairs(unavailable_cannons) do
                if can.id == id then
                    table.insert(available_cannons, table.remove(unavailable_cannons, i))
                    break
                end
            end
        end
        if msg["type"] == "artillery_barrage_request" then
            table.insert(barrage_requests,
                {
                    id = id,
                    coordinates = generate_coordinates(
                        utils.tbl_to_vec(msg["target_position"]),
                        msg["spacing"],
                        msg["semi_width"],
                        msg["semi_height"]
                    )
                }
            )
        end
        ::continue::
    end
end

local function handle_barrage_completion()
    -- This will mean some cannons may be idle, waiting until the current request
    -- is 100% finished, but I don't care enough.
    if (current_request["coordinates"] == nil or #current_request["coordinates"] == 0) and
        #wip_fire_missions == 0
    then
        -- Ordering is important. Who would've thought?
        if current_request["id"] then
            add_to_message(
                { type = "artillery_barrage_completion" },
                current_request["id"]
            )
        end
        current_request = #barrage_requests > 0 and table.remove(barrage_requests, 1) or {}
    end
end

local function allocate_cannons_to_targets()
    local start_time = utils.time_seconds()
    while current_request["coordinates"] and #current_request["coordinates"] > 0 and #available_cannons > 0 do
        -- Position to be struck
        local target_pos = current_request["coordinates"][1]
        -- Go through all cannons that are ready to fire. If a firing solution exists,
        -- send the required yaw and pitch to the suitable cannon.
        -- Also note that the coordinate we ordered the cannon to fire is now 'work in progress'.
        for i, a_can in ipairs(available_cannons) do
            local yaw, pitch, t = a_can.calculate(target_pos, PREFERRED_TRAJECTORY)
            -- Valid solution
            if yaw and pitch and t then
                add_to_message({
                    ["type"] = "fire_mission",
                    ["yaw"] = yaw,
                    ["pitch"] = pitch,
                }, a_can.id)
                table.insert(unavailable_cannons, table.remove(available_cannons, i))
                table.remove(current_request["coordinates"], 1)
                table.insert(wip_fire_missions, {
                    id = a_can.id,
                    pos = target_pos,
                    flight_time = t / 20, -- Our current time function works in seconds.
                    fired_time = nil,
                    timeout_time = utils.time_seconds() + FIRE_MISSION_TIMEOUT
                })
                goto continue
            end
        end
        -- If we didn't find a valid solution, then we must check if ANY of our cannons
        -- is able to hit it.
        for _, u_can in ipairs(unavailable_cannons) do
            local yaw, pitch, t = u_can.calculate(target_pos, PREFERRED_TRAJECTORY)
            if yaw and pitch and t then
                -- Since the cannon that can shoot at it is not available yet,
                -- move the coordinate to the back of the queue to be struck later,
                -- when the cannon is more likely to be ready.
                table.insert(current_request["coordinates"], table.remove(current_request["coordinates"], 1))
                goto continue
            end
        end
        -- Not a single one of our cannons can hit the target. Let's just give up.
        table.remove(current_request["coordinates"], 1)
        ::continue::
        if utils.time_seconds() - start_time > MAX_LOOP_TIME then break end
    end
end

--- Remove all fire_missions of which the shells have already
--- hit the target or have taken way too long to complete.
local function cleanup_wip_missions()
    for i = #wip_fire_missions, 1, -1 do
        local fire_mission = wip_fire_missions[i]
        if fire_mission.fired_time and
            utils.time_seconds() - fire_mission.fired_time > fire_mission.flight_time
        then
            table.remove(wip_fire_missions, i)
        elseif utils.time_seconds() > fire_mission.timeout_time then
            print(fire_mission.id .. " has timed out!")
            -- Transfer the coordinates back to current_request to try again.
            table.insert(current_request["coordinates"], table.remove(wip_fire_missions, i).pos)
        end
    end
end

local function main()
    print(DISPLAY_STRING)
    print(string.rep("-", #DISPLAY_STRING))
    -- Initial ping to begin registering all of the available cannons.
    os.sleep(1.0) -- Wait until all startup scripts (cannons) are ready.
    add_to_message({ type = "info_request" })
    while true do
        process_inbox()
        handle_barrage_completion()
        allocate_cannons_to_targets()
        cleanup_wip_missions()

        -- Avoid needlessly sending out empty messages.
        if utils.count_keys(resulting_message) > 0 then networking.send_packet(resulting_message) end
        resulting_message = {} -- Wipe clean for next iteration.
        os.sleep(SLEEP_INTERVAL)
    end
end

parallel.waitForAny(main, networking.message_handler)
