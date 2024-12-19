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
-- We don't do fallback options; too much effort.
local DESIRED_TRAJECTORY = false -- true = low, false = high.
local INCOMING_CHANNEL, OUTGOING_CHANNEL = 6060, 6060
local BATTERY_ID_PREFIX = "battery_"
local MY_ID = BATTERY_ID_PREFIX .. "command"
local SLEEP_INTERVAL = 1 / 20

--[[ STATE VARIABLES ]]

local cannons = {}

local barrage_requests = {}
local current_barrage_fire_missions = {}
local active_fire_missions = {} -- key is a fire_mission (pos?), and comp id

--[[ DEPENDENCIES SETUP ]]

networking.set_modem(MODEM)
networking.set_channels(INCOMING_CHANNEL, OUTGOING_CHANNEL)
networking.set_id(MY_ID)

--[[ FUNCTIONS ]]

local function cannon()
    local self = setmetatable({}, {})

    function self.create(
        id, position, velocity_ms,
        cannon_length, is_med_cannon,
        min_pitch, max_pitch, reload_time
    )
        self.id = id
        self.position = position
        self.velocity_ms = velocity_ms
        self.cannon_length = cannon_length
        self.is_med_cannon = is_med_cannon
        self.min_pitch = min_pitch
        self.max_pitch = max_pitch
        self.reload_time = reload_time
        self.last_fired = 0
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
        print(flight_time, pitch)
        if (not flight_time) or (not pitch) then return nil, nil end
        if pitch < self.min_pitch or pitch > self.max_pitch then return nil, nil end
        return yaw, pitch, flight_time
    end

    function self.request_fire(yaw, pitch)
        --- @TODO: send command to fire (and update queue if cannon answers back), but we must respect cooldown.
        --- NOTE: cannon MUST send back when it has last fired, so we know when a target has been hit
        --- (time of firing + t)
        networking.send_packet(
            {
                type = "fire_mission",
                yaw = yaw,
                pitch = pitch,
            }
        )
    end

    function self.update_last_fired(time)
        assert(time >= self.last_fired, "How are we going back in time?")
        self.last_fired = time
    end

    function self.is_reloaded()
        return utils.time_seconds() > self.last_fired + self.reload_time
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

-- [[ STATE ]]

local function main()
    while true do
        networking.remove_decayed_packets()
        for id, _ in pairs(networking.get_inbox()) do
            local packet = networking.get_packet(id)
            local msg = networking.get_message(id)
            if networking.has_been_read(id) then goto continue end
            networking.mark_as_read(id)
            if msg["type"] == "cannon_info" then
                local is_med_cannon = msg["cannon_type"] == "medium"
                -- Note: this _will_ overwrite existing cannons.
                cannons[id] = cannon().create(
                    id, utils.tbl_to_vec(msg["position"]),
                    msg["velocity_ms"], msg["cannon_length"], is_med_cannon,
                    msg["min_pitch"], msg["max_pitch"], msg["reload_time"]
                )
            end
            --- @TODO: also figure out how to link this back to a specific fire_mission
            --- (which to remove from a queue since it's done) probably by using the id somehow.
            if msg["type"] == "fire_mission_completion" then
                pretty.pretty_print(msg)
                print(id .. " fired at: " .. packet["time"])
            end

            if msg["type"] == "artillery_barrage_request" then
                table.insert(barrage_requests,
                    {
                        id = id,
                        fire_missions = generate_coordinates(
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
        -- If you somehow end up requesting multiple times on the same id, you will
        -- run into some weird issues where you get multiple completion notices.
        for i, barrage_request in pairs(barrage_requests) do
            if #barrage_request.fire_missions == 0 then
                networking.send_packet({ type = "artillery_barrage_completion" }, barrage_request.id)
                table.remove(barrage_requests, i)
            end
        end
        os.sleep(SLEEP_INTERVAL)
    end
end

-- networking.send_packet({ type = "info_request" })
networking.send_packet({ type = "fire_mission", yaw = 10, pitch = 20 })
-- networking.send_packet({ type = "artillery_barrage_completion" })
parallel.waitForAny(main, networking.message_handler)
