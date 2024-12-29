--[[ TESTING ]]

periphemu.create("top", "modem")

--[[ DEPENDENCIES ]]

package.path = package.path .. ";../modules/?.lua"
local ballistics = require("ballistics")
local networking = require("networking")
local utils = require("utils")
local pretty = require("cc.pretty")

--[[ PERIPHERALS ]]

local MODEM = peripheral.find("modem")

--[[ SETTINGS / CONSTANTS ]]

local T0 = 0
local TN = 750
-- Too lazy to do implement fallback trajectory.
local PREFERRED_TRAJECTORY = false -- true = low, false = high.
local INCOMING_CHANNEL, OUTGOING_CHANNEL = 6060, 6060
local BATTERY_ID_PREFIX = "battery_"
local MY_ID = BATTERY_ID_PREFIX .. "command"
local MAX_LOOP_TIME = 0.05
local FIRE_MISSION_TIMEOUT = 60 -- In seconds
local SLEEP_INTERVAL = 4 / 20

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

local function find_overwrite_cannon(cannons, new_cannon)
    for i, existing_cannon in ipairs(cannons) do
        if existing_cannon.id == new_cannon.id then
            cannons[i] = new_cannon
            return true
        end
    end
    return false
end

local function cannon()
    local self = setmetatable({}, {})

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

    function self.calculate(target_pos, trajectory)
        local yaw = ballistics.calculate_yaw(self.position, target_pos)
        local distance = utils.vec_drop_axis(target_pos - self.position, "y"):length()
        local target_height = target_pos.y - self.position.y
        local flight_time, pitch = ballistics.calculate_pitch(
            distance,
            self.velocity_ms,
            target_height,
            self.cannon_length,
            T0, TN,
            trajectory,
            self.is_med_cannon
        )
        if not (flight_time or pitch) then return nil, nil, nil end
        if pitch < self.min_pitch or pitch > self.max_pitch then return nil, nil, nil end
        return yaw, pitch, flight_time
    end

    return self
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
        local msg = networking.get_message(id)
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
                if fire_mission.id == id and not fire_mission.fired_time then
                    fire_mission.fired_time = packet["time"]
                end
            end
        end
        if msg["type"] == "has_reloaded" then
            for i, can in ipairs(unavailable_cannons) do
                if can.id == id then
                    table.insert(available_cannons, table.remove(unavailable_cannons, i))
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

--- @param target_pos table Vector
--- @return string? cannon_id The cannon that's supposed to fire on the target.
--- @return number? tn Shell flight time in ticks
local function order_available_cannon(target_pos)
    if #available_cannons == 0 then return end
    for i, can in ipairs(available_cannons) do
        local yaw, pitch, tn = can.calculate(target_pos, PREFERRED_TRAJECTORY)
        -- Valid solution
        if yaw and pitch and tn then
            add_to_message({
                ["type"] = "fire_mission",
                ["yaw"] = yaw,
                ["pitch"] = pitch,
            }, can.id)
            table.insert(unavailable_cannons, table.remove(available_cannons, i))
            return can.id, tn
        end
    end

    --- @TODO: IF NONE ARE VALID
    --- move target to back of queue
    --- remember which cannons we tried already (for that specific target)
    --- Try again with new ones, if it still doesn’t work, keep moving to the back.
    --- if we really have tried all possible cannons at both trajectories, but
    --- it still doesn’t work, then discard
    return nil, nil
end

local function main()
    -- Initial ping to begin registering all of the available cannons.
    add_to_message({ type = "info_request" })
    while true do
        networking.remove_decayed_packets()
        process_inbox()

        term.clear()
        print("Current request:")
        pretty.pretty_print(current_request)
        print("WIP fire missions:")
        pretty.pretty_print(wip_fire_missions)
        if wip_fire_missions[1] and wip_fire_missions[1].fired_time then
            print("Time until next impact:",
                wip_fire_missions[1].flight_time - utils.time_seconds() + wip_fire_missions[1].fired_time
            )
        end
        print("Cannons av/na:", #available_cannons, #unavailable_cannons)

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

        local start_time = utils.time_seconds()
        while current_request["coordinates"] and #current_request["coordinates"] > 0 and #available_cannons > 0 do
            local target_pos = current_request["coordinates"][1]
            local can_id, flight_time_ticks = order_available_cannon(target_pos)
            if can_id and flight_time_ticks then
                table.remove(current_request["coordinates"], 1)
                table.insert(wip_fire_missions, {
                    id = can_id,
                    pos = target_pos,
                    flight_time = flight_time_ticks / 20, -- Our current time function works in seconds.
                    fired_time = nil,
                    timeout_time = utils.time_seconds() + FIRE_MISSION_TIMEOUT
                })
            else
                --- @TODO: don't just ignore our problems out of convenience...
                table.remove(current_request["coordinates"], 1)
            end
            if utils.time_seconds() - start_time > MAX_LOOP_TIME then break end
        end
        for i = #wip_fire_missions, 1, -1 do
            local fire_mission = wip_fire_missions[i]
            if fire_mission.fired_time and
                utils.time_seconds() - fire_mission.fired_time > fire_mission.flight_time
            then
                table.remove(wip_fire_missions, i)
            elseif utils.time_seconds() > fire_mission.timeout_time then
                -- Transfer the coordinates back to the current_request to try again, since it took too long.
                table.insert(current_request["coordinates"], table.remove(wip_fire_missions, i).pos)
            end
        end

        -- Avoid needlessly sending out empty messages.
        if utils.count_keys(resulting_message) > 0 then networking.send_packet(resulting_message) end
        resulting_message = {} -- Wipe clean for next iteration.
        os.sleep(SLEEP_INTERVAL)
    end
end

local function test_input()
    table.insert(barrage_requests, {
        id = "test_orderer1",
        coordinates = generate_coordinates(vector.new(500, 0, 0), 1, 2, 2)
    })
    table.insert(barrage_requests, {
        id = "test_orderer2",
        coordinates = generate_coordinates(vector.new(450, 0, 0), 4, 5, 0)
    })
    table.insert(barrage_requests, {
        id = "test_orderer3",
        coordinates = generate_coordinates(vector.new(400, 0, 0), 1, 1, 1)
    })
    table.insert(available_cannons, cannon().create("c1", vector.new(0, 0, 0), 160, 11, false, -30, 60))
    table.insert(available_cannons, cannon().create("c2", vector.new(50, 0, 10), 160, 11, false, -30, 60))
    table.insert(available_cannons, cannon().create("c3", vector.new(100, 0, 20), 160, 11, false, -30, 60))
    table.insert(available_cannons,
        cannon().create("battery_cannon_1", vector.new(100, 0, 20), 160, 11, false, -30, 60))
end

-- test_input()

parallel.waitForAny(main, networking.message_handler)
