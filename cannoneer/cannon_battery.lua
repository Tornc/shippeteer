--[[ TESTING ]]

-- periphemu.create("top", "modem")

--[[ DEPENDENCIES ]]

package.path = package.path .. ";../modules/?.lua"
local config = require("config")
local networking = require("networking")
local utils = require("utils")
local pretty = require("cc.pretty")

--[[ CONSTANTS ]]

local SETTINGS_LOCATION   = fs.getDir(shell.getRunningProgram()) .. "./cannon.settings"
local ARG_ASK_SETTINGS    = "settings"
local CBC_GEARDOWN_RATIO  = 8
local MAX_YAW_RPM         = 256    -- Not the actual speed, the MAX speed! Only relevant if you're SU limited.
local MAX_PITCH_RPM       = 256
local REASSEMBLY_COOLDOWN = 4 / 20 -- Ticks
local INCOMING_CHANNEL    = 6060
local OUTGOING_CHANNEL    = 6060
local BATTERY_ID_PREFIX   = "battery_" -- Dumb solution but my brain is not big enough.
local VERSION             = "0.1-unfinished"
-- Ideally 2 ticks. But to ensure maximum reliability, do 4 ticks. <= 0.15 degrees is _fine_.
local MOVE_SLEEP_INTERVAL = 4 / 20

--[[ SETTINGS ]]

local MY_ID                  -- String
local COMMAND_ID             -- String
local CANNON_POS             -- Vector(X, Y, Z)
local CANNON_LENGTH          -- From shaft to muzzle (inclusive)
local CANNON_TYPE            -- "big" or "medium"
local PROJECTILE_VELOCITY_MS -- # of charges * 40
local RELOAD_TIME            -- Seconds
local STARTING_YAW           -- Degrees
local STARTING_PITCH         -- Degrees
local PITCH_RANGE            -- Minimum and maximum cannon pitch in degrees
local YAW_CONTROLLER_SIDE    -- "top", "bottom", "left", "right", "front", "back"
local PITCH_CONTROLLER_SIDE  --
local CANNON_ASSEMBLY_SIDE   --
local CANNON_FIRE_SIDE       --

local function init_settings()
    local settings = config.get_settings(SETTINGS_LOCATION)
    if (not settings) or arg[1] == string.lower(ARG_ASK_SETTINGS) then
        config.set_setting(
            config.ask_setting(
                "Cannon controller id?",
                { BATTERY_ID_PREFIX }
            ),
            "my_id"
        )
        config.set_setting(
            config.ask_setting(
                "Battery command id?",
                { BATTERY_ID_PREFIX }
            ),
            "command_id"
        )
        config.set_setting(
            config.ask_setting(
                "Cannon position <X Y Z>?",
                { "0 0 0" },
                function(i)
                    local coordinate = {}
                    for value in i:gmatch("%S+") do
                        if tonumber(value) ~= nil then
                            table.insert(coordinate, value)
                        else
                            return false
                        end
                    end
                    return #coordinate == 3
                end
            ),
            "cannon_pos",
            function(i)
                local coordinate = {}
                for v in i:gmatch("%S+") do table.insert(coordinate, tonumber(v)) end
                return coordinate
            end
        )
        config.set_setting(
            config.ask_setting(
                "Cannon length?",
                { "11" },
                function(i) return tonumber(i) end
            ),
            "cannon_length",
            function(i) return tonumber(i) end
        )
        config.set_setting(
            config.ask_setting(
                "Cannon type?",
                { "big", "medium" },
                function(i, c) return utils.contains(c, i) end
            ),
            "cannon_type"
        )
        config.set_setting(
            config.ask_setting(
                "Projectile velocity (m/s)?",
                { "160", "320" },
                function(i) return tonumber(i) end
            ),
            "projectile_velocity_ms",
            function(i) return tonumber(i) end
        )
        config.set_setting(
            config.ask_setting(
                "Reload time in seconds?",
                { "5.0" },
                function(i) return tonumber(i) end
            ),
            "reload_time",
            function(i) return tonumber(i) end
        )
        config.set_setting(
            config.ask_setting(
                "Starting yaw?",
                { "0", "90", "180", "270" },
                function(i) return tonumber(i) end -- Account for weird bullshit players can come up with.
            ),
            "starting_yaw",
            function(i) return tonumber(i) end
        )
        config.set_setting(
            config.ask_setting(
                "Starting pitch?",
                { "0", "90" },
                function(i) return tonumber(i) end -- Account for weird bullshit players can come up with.
            ),
            "starting_pitch",
            function(i) return tonumber(i) end
        )
        config.set_setting(
            config.ask_setting(
                "Pitch range?",
                { "-30 60" },
                function(i)
                    local range = {}
                    for value in i:gmatch("%S+") do
                        if tonumber(value) ~= nil then
                            table.insert(range, value)
                        else
                            return false
                        end
                    end
                    return #range == 2
                end
            ),
            "pitch_range",
            function(i)
                local range = {}
                for v in i:gmatch("%S+") do table.insert(range, tonumber(v)) end
                table.sort(range)
                return range
            end
        )
        config.set_setting(
            config.ask_setting(
                "Yaw controller side?",
                rs.getSides(),
                function(i, c) return utils.contains(c, i) end
            ),
            "yaw_controller_side"
        )
        config.set_setting(
            config.ask_setting(
                "Pitch controller side?",
                rs.getSides(),
                function(i, c) return utils.contains(c, i) end
            ),
            "pitch_controller_side"
        )
        config.set_setting(
            config.ask_setting(
                "Cannon assembly side?",
                rs.getSides(),
                function(i, c) return utils.contains(c, i) end
            ),
            "cannon_assembly_side"
        )
        config.set_setting(
            config.ask_setting(
                "Cannon fire side?",
                rs.getSides(),
                function(i, c) return utils.contains(c, i) end
            ),
            "cannon_fire_side"
        )
        config.save_settings(SETTINGS_LOCATION)
        settings = config.get_settings(SETTINGS_LOCATION)
    end
    assert(settings, "Settings failed to load somehow.")
    MY_ID = settings["my_id"]
    COMMAND_ID = settings["command_id"]
    CANNON_POS = utils.tbl_to_vec(settings["cannon_pos"])
    CANNON_LENGTH = settings["cannon_length"]
    CANNON_TYPE = settings["cannon_type"]
    PROJECTILE_VELOCITY_MS = settings["projectile_velocity_ms"]
    RELOAD_TIME = settings["reload_time"]
    STARTING_YAW = settings["starting_yaw"]
    STARTING_PITCH = settings["starting_pitch"]
    PITCH_RANGE = settings["pitch_range"]
    YAW_CONTROLLER_SIDE = settings["yaw_controller_side"]
    PITCH_CONTROLLER_SIDE = settings["pitch_controller_side"]
    CANNON_ASSEMBLY_SIDE = settings["cannon_assembly_side"]
    CANNON_FIRE_SIDE = settings["cannon_fire_side"]
end

init_settings()

--[[ PERIPHERALS ]]

local YAW_CONTROLLER = peripheral.wrap(YAW_CONTROLLER_SIDE)
local PITCH_CONTROLLER = peripheral.wrap(PITCH_CONTROLLER_SIDE)
local MODEM = peripheral.find("modem")

--[[ STATE VARIABLES ]]

local current_yaw
local current_pitch

--[[ DEPENDENCIES SETUP ]]

networking.set_modem(MODEM)
networking.set_channels(INCOMING_CHANNEL, OUTGOING_CHANNEL)
networking.set_id(MY_ID)

--[[ PERIPHERALS SETUP ]]

rs.setOutput(CANNON_FIRE_SIDE, false)
for _, rc in pairs({ peripheral.find("Create_RotationSpeedController") }) do rc.setTargetSpeed(0) end

--[[ FUNCTIONS ]]

--- Ensures current_yaw and current_pitch match STARTING_YAW and STARTING_PITCH
local function reassemble_cannon()
    rs.setOutput(CANNON_ASSEMBLY_SIDE, false)
    os.sleep(REASSEMBLY_COOLDOWN)
    rs.setOutput(CANNON_ASSEMBLY_SIDE, true)
    current_yaw = STARTING_YAW
    current_pitch = STARTING_PITCH
end

local function fire_cannon()
    rs.setOutput(CANNON_FIRE_SIDE, true)
    os.sleep(REASSEMBLY_COOLDOWN)
    rs.setOutput(CANNON_FIRE_SIDE, false)
end

--- Derivation:
--- 1 rpm = 360 degrees / 1 minute
---       = 6 degrees / 1 second
---       = 0.3 degrees / 1 tick
--- @param rpm number
--- @return number degrees Delta degrees per second.
local function rpm_dds(rpm) return rpm * 6 end

--- Returns the highest RPM it can get away with, to close the gap ASAP.
--- @param delta_degrees number
--- @param smallest_rpm_step number
--- @param max_rpm number
--- @return number
local function calculate_rpm(delta_degrees, smallest_rpm_step, max_rpm)
    return utils.clamp(delta_degrees / rpm_dds(smallest_rpm_step), -max_rpm, max_rpm)
end

--- @param desired_yaw number In degrees
--- @param desired_pitch number In degrees
local function move_cannon(desired_yaw, desired_pitch)
    local yaw_rpm = 0
    local pitch_rpm = 0
    local previous_time = utils.time_seconds()
    os.sleep(MOVE_SLEEP_INTERVAL)

    while true do
        current_yaw = current_yaw % 360
        current_pitch = utils.clamp(current_pitch, PITCH_RANGE[1], PITCH_RANGE[2])

        local delta_yaw = (desired_yaw - current_yaw + 180) % 360 - 180
        local delta_pitch = desired_pitch - current_pitch

        yaw_rpm = utils.round(calculate_rpm(delta_yaw, 1 / CBC_GEARDOWN_RATIO * MOVE_SLEEP_INTERVAL, MAX_YAW_RPM))
        pitch_rpm = utils.round(calculate_rpm(delta_pitch, 1 / CBC_GEARDOWN_RATIO * MOVE_SLEEP_INTERVAL, MAX_PITCH_RPM))

        local dt = utils.round_increment(utils.time_seconds() - previous_time, 0.05)
        local yaw_change = rpm_dds(yaw_rpm / CBC_GEARDOWN_RATIO) * dt
        local pitch_change = rpm_dds(pitch_rpm / CBC_GEARDOWN_RATIO) * dt
        current_yaw = current_yaw + yaw_change
        current_pitch = current_pitch + pitch_change

        if yaw_rpm ~= YAW_CONTROLLER.getTargetSpeed() then
            utils.run_async(YAW_CONTROLLER.setTargetSpeed, -yaw_rpm)
        end
        if pitch_rpm ~= PITCH_CONTROLLER.getTargetSpeed() then
            utils.run_async(PITCH_CONTROLLER.setTargetSpeed, -pitch_rpm)
        end

        if
            yaw_rpm + pitch_rpm == 0 and
            YAW_CONTROLLER.getTargetSpeed() + PITCH_CONTROLLER.getTargetSpeed() == 0
        then
            print(current_yaw, current_pitch)
            break
        end

        previous_time = utils.time_seconds()
        os.sleep(MOVE_SLEEP_INTERVAL)
    end
end

local display_string = "=][= CANNON v" .. VERSION .. " =][="
print(display_string)
print(string.rep("-", #display_string))
print("Optional program arguments:")
print("ship_sensor [" .. ARG_ASK_SETTINGS .. "]")
print(string.rep("-", #display_string))
print("My ID:", MY_ID)
print("Command ID:", COMMAND_ID)
print("Cannon pos:", CANNON_POS)
print("Cannon length:", CANNON_LENGTH)
print("Cannon type:", CANNON_TYPE)
print("Projectile velocity (m/s):", PROJECTILE_VELOCITY_MS)
print("Reload time:", RELOAD_TIME)
print("Starting yaw, pitch:", STARTING_YAW .. ", " .. STARTING_PITCH)
print("Min, max pitch:", PITCH_RANGE[1] .. ", " .. PITCH_RANGE[2])
print("Yaw controller side:", YAW_CONTROLLER_SIDE)
print("Pitch controller side:", PITCH_CONTROLLER_SIDE)
print("Cannon assembly side:", CANNON_ASSEMBLY_SIDE)
print("Cannon fire side:", CANNON_FIRE_SIDE)

-- reassemble_cannon()
-- move_cannon(tonumber(arg[1]) or 0, tonumber(arg[2]) or 0)
-- fire_cannon()

-- reassemble_cannon()
-- local count = 1
-- while true do
--     print("Turn #" .. count)
--     move_cannon(tonumber(arg[1]) or 0, tonumber(arg[2]) or 0)
--     os.sleep(1.5)
--     move_cannon(0, 0)
--     os.sleep(1.5)
--     count = count + 1
-- end

-- networking.send_packet(
--     {
--         type = "cannon_info",
--         position = CANNON_POS,
--         velocity_ms = PROJECTILE_VELOCITY_MS,
--         cannon_length = CANNON_LENGTH,
--         cannon_type = CANNON_TYPE,
--         min_pitch = PITCH_RANGE[1],
--         max_pitch = PITCH_RANGE[2],
--         reload_time = RELOAD_TIME
--     },
--     COMMAND_ID
-- )