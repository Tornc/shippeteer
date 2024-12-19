--[[ TESTING ]]

-- periphemu.create("front", "monitor")
periphemu.create("top", "modem")

--[[ DEPENDENCIES ]]

package.path = package.path .. ";../modules/?.lua"
local ballistics = require("ballistics")
local networking = require("networking")
local utils = require("utils")
local pretty = require("cc.pretty")

--[[ PERIPHERALS ]]

local MODEM = peripheral.find("modem")
local MONITOR = peripheral.find("monitor")

--[[ SETTINGS / CONSTANTS ]]

local T0 = 0
local TN = 750
local PREFERRED_TRAJECTORY = false  -- true = low, false = high
local INCOMING_CHANNEL, OUTGOING_CHANNEL = 6060, 6060
local BATTERY_ID_PREFIX = "battery" -- Dumb solution but my brain is not big enough.
local MY_ID = BATTERY_ID_PREFIX .. "_command"
local SLEEP_INTERVAL = 1 / 20

--[[ STATE VARIABLES ]]

local coordinate_queue = {}
local cannons = {}
local aiming_cannons = {}
local reloading_cannons = {}

--[[ DEPENDENCIES SETUP ]]

networking.set_modem(MODEM)
networking.set_channels(INCOMING_CHANNEL, OUTGOING_CHANNEL)
networking.set_id(MY_ID)

--[[ FUNCTIONS ]]

local function write_at(x, y, text)
    local p_x, p_y = MONITOR.getCursorPos()
    MONITOR.setCursorPos(x, y)
    MONITOR.write(text)
    MONITOR.setCursorPos(p_x, p_y)
end

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

local function task_assigner()
    os.sleep(SLEEP_INTERVAL)
    local target_pos = vector.new(6 * 3, 20, 6 * 3)

    coordinate_queue = utils.merge_tables(coordinate_queue, generate_coordinates(target_pos, 4, 5, 10))
    local test_cannon = cannon().create("cannon_1", vector.new(1, 2, 3), 160, 11, false, -30, 60, 5.0)
    table.insert(cannons, test_cannon)

    local y, p, t = test_cannon.calculate(target_pos, not PREFERRED_TRAJECTORY)
    -- test_cannon.request_fire(y, p)

    while true do
        --- @TODO: move this over to main (?)
        for _, can in pairs(cannons) do
            local pck = networking.get_packet(can.id)
            if pck and pck["message"]["type"] == "has_fired" then
                can.update_last_fired(pck["time"])
                print("Fired at: ", pck["time"])
                print("Time of impact: ", can.last_fired + t)
            end
        end
        os.sleep(SLEEP_INTERVAL)
    end
end

local function main()
    --- @TODO: maybe move this into a separate function, where we ping, wait for a few seconds, register the cannons and then continue.
    cannons = {}                                      -- Clean up.
    networking.send_packet({ type = "request_info" }) -- ping

    while true do
        networking.remove_decayed_packets()

        -- These are all of our cannons.
        for id, _ in pairs(networking.get_inbox()) do
            if string.find(id, BATTERY_ID_PREFIX) then
                local msg = networking.get_message(id)
                if msg["type"] == "info" then
                    local new_cannon = cannon().create(
                        id, msg.position, msg.velocity_ms,
                        msg.cannon_length, msg.is_med_cannon,
                        msg.min_pitch, msg.max_pitch, msg.reload_time
                    )
                    if not cannons[id] then cannons[id] = new_cannon end
                end
            end
        end

        --- @TODO: pocket comp input

        os.sleep(SLEEP_INTERVAL)
    end
end

parallel.waitForAny(main, task_assigner, networking.message_handler)

-- MONITOR.clear()
-- for _, c in pairs(coordinates) do
--     write_at(c.x, c.z, "x")
-- end

-- print(ballistics.calculate_yaw(vector.new(-42, 66, 61), vector.new(-183, 71, 327)))

--[[
    I am creating an artillery battery system in a game. I have a list of target positions
    (X Y Z), computed by the battery command computer. An artillery battery consists of
    multiple cannons, each controlled by a computer. Each cannon's computer has information
    like cannon position, etc. and combined with a provided target position, they can
    calculate how to rotate the cannon to the correct angles. Sometimes, there is no solution
    since the cannon is out of range. A cannon needs time to aim and also has a reload time.
    It also can receive the command to fire. What kind of information would need to be
    communicated between the battery command computer and cannon computers? How would the
    network look like? There will probably be more targets than cannons. How would the task
    assignment be implemented? We do NOT know a cannon's max range, only if it has a solution
    or not. Also, the command computer does not know each cannon's position, aim time or
    reload, etc.
]]

--- Idea:
--- store everything in the command computer, perform all calculations there.
--- a 'ping' message (send only once) from command to any cannon computer, to ask for all relevant info
--- create a cannon() class
--- Cannons can't fail (most cases) if all the info is correct; we can detect out of range failures here.
--- cannon comp _does_ have to send back when they fired.

--- @TODO: go for low trajectory as a backup option ONLY if NONE of the cannons can do high.
