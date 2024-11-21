-- Written by Ton, with love. Feel free to modify, consider this under the MIT license.

--[[ DEPENDENCIES ]]
package.path = package.path .. ";./modules/?.lua"
local config = require("config")
local networking = require("networking")
local utils = require("utils")
local pretty = require("cc.pretty")

--[[ PERIPHERALS ]]

local MODEM = peripheral.find("modem")

--[[ CONSTANTS ]]

local INCOMING_CHANNEL, OUTGOING_CHANNEL = 6060, 6060
local SETTINGS_FILE_PATH = "sensor.settings"
local ARG_ASK_SETTINGS = "settings"
local DIRECTIONS = { "North", "East", "South", "West" }
local VERSION = "0.1-dev"
local SLEEP_INTERVAL = 1 / 20

--[[ SETTINGS ]]

local MY_ID
local SHIPYARD_DIRECTION

--[[ FUNCTIONS ]]

local function init_settings()
    local sets = config.get_settings(SETTINGS_FILE_PATH)
    if (not sets) or arg[1] == string.lower(ARG_ASK_SETTINGS) then
        -- No need for type conversion; info is all strings anyway.
        config.set_setting(
            config.ask_setting("Movable component name (id)?",
                {},
                nil
            ),
            "my_id",
            nil
        )
        config.set_setting(
            config.ask_setting(
                "Shipyard direction?",
                { "North", "East", "South", "West" },
                function(i, c) return utils.contains(c, i) end),
            "shipyard_direction",
            nil
        )
        config.save_settings(SETTINGS_FILE_PATH)
        sets = config.get_settings(SETTINGS_FILE_PATH)
    end
    assert(sets, "Settings failed to load somehow.")
    SHIPYARD_DIRECTION = sets["shipyard_direction"]
    MY_ID = sets["my_id"]
end

local function get_orientation()
    local matrix = ship.getTransformationMatrix()
    local orientation = {
        -- CC:VS's getYaw() implementation does not work at the moment.
        ["pitch"] = math.deg(math.asin(-matrix[2][3])),
        ["yaw"] = math.deg(math.atan2(matrix[1][3], matrix[3][3])),
        ["roll"] = math.deg(math.atan2(matrix[2][1], matrix[2][2])),
    }
    return orientation
end

local function get_omega()
    local omega = {
        ["pitch"] = math.deg(ship.getOmega().x),
        ["yaw"] = math.deg(ship.getOmega().y),
        ["roll"] = math.deg(ship.getOmega().z),
    }
    return omega
end

local function main()
    networking.set_modem(MODEM)
    networking.set_channels(INCOMING_CHANNEL, OUTGOING_CHANNEL)
    networking.set_id(MY_ID)

    local display_string = "=][= SHIP SENSOR v" .. VERSION .. " =][="
    print(display_string)
    print(string.rep("-", #display_string))
    print("Optional program argument:")
    print("ship_sensor [" .. ARG_ASK_SETTINGS .. "]")
    print(string.rep("-", #display_string))
    print("ID: " .. MY_ID)
    print("Shipyard direction: " .. SHIPYARD_DIRECTION)
    while true do
        local message = {
            position = ship.getWorldspacePosition(),
            orientation = get_orientation(),
            omega = get_omega(),
            inertia = ship.getMomentOfInertiaTensor()
        }

        networking.send_packet(message)
        sleep(SLEEP_INTERVAL)
    end
end

init_settings()
main()
