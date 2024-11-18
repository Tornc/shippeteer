-- Written by Ton, with love. Feel free to modify, consider this under the MIT license.

--[[ TESTING ]]

periphemu.create("top", "modem")

--[[ DEPENDENCIES ]]
package.path = package.path .. ";./modules/?.lua"
local config = require("config")
local networking = require("networking")
local ship = require("fake_ShipAPI")
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
    local sets = config.load(SETTINGS_FILE_PATH)
    if not sets or arg[1] == string.lower(ARG_ASK_SETTINGS) then
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
        config.save(SETTINGS_FILE_PATH)
        config.load(SETTINGS_FILE_PATH)
    end
    assert(sets, "Settings failed to load somehow.")
    SHIPYARD_DIRECTION = sets["shipyard_direction"]
    MY_ID = sets["my_id"]
end

local function get_orientation()
    local orientation = {
        ["pitch"] = math.deg(ship.getPitch()),
        ["yaw"] = math.deg(ship.getYaw()),
        ["roll"] = math.deg(ship.getRoll()),
    }
    -- NESW bullshit explanation:
    -- ShipAPI's orientation will always be based on the orientation a ship is in the shipyard.
    -- The 'true north' (front) of a ship may not be the same as the front of your build.
    -- Shift yaw by 90 degrees accordingly. N = +0, E = +90, S = +180, W = +270. - done
    -- Therefore, if a ship is built facing south, the roll will be inverted. - done
    -- When it’s east, roll becomes inverted pitch and pitch becomes roll.
    -- When it's west, roll becomes pitch and pitch becomes inverted roll.
    orientation["yaw"] = orientation["yaw"] +
        (90 * (utils.index_of(DIRECTIONS, SHIPYARD_DIRECTION) - 1) + 180) % 360 - 180
    if SHIPYARD_DIRECTION == "South" then
        orientation["roll"] = -orientation["roll"]
    elseif SHIPYARD_DIRECTION == "East" then
        orientation["roll"], orientation["pitch"] = -orientation["pitch"], orientation["roll"]
    elseif SHIPYARD_DIRECTION == "West" then
        orientation["roll"], orientation["pitch"] = orientation["pitch"], -orientation["roll"]
    end
    return orientation
end

local function get_omega()
    local omega = {
        ["pitch"] = math.deg(ship.getOmega().x),
        ["yaw"] = math.deg(ship.getOmega().y),
        ["roll"] = math.deg(ship.getOmega().z),
    }
    -- Same bullshit here, only that yaw does not need to get shifted.
    if SHIPYARD_DIRECTION == "South" then
        omega["roll"] = -omega["roll"]
    elseif SHIPYARD_DIRECTION == "East" then
        omega["roll"], omega["pitch"] = -omega["pitch"], omega["roll"]
    elseif SHIPYARD_DIRECTION == "West" then
        omega["roll"], omega["pitch"] = omega["pitch"], -omega["roll"]
    end
    return omega
end

local function main()
    networking.set_modem(MODEM)
    networking.set_channels(INCOMING_CHANNEL, OUTGOING_CHANNEL)
    networking.set_id(MY_ID)

    local display_string = "=][= SHIP SENSOR v" .. VERSION .. " =][="
    print(display_string)
    print(string.rep("-", #display_string))
    print("ID: " .. MY_ID)
    print("Shipyard direction: " .. SHIPYARD_DIRECTION)
    while true do
        local message = {
            position = ship.getWorldspacePosition(),
            velocity = ship.getVelocity(),
            orientation = get_orientation(),
            omega = get_omega()
        }

        networking.send_packet(message)
        ship.run(SLEEP_INTERVAL)
        sleep(SLEEP_INTERVAL)
    end
end

init_settings()
main()
