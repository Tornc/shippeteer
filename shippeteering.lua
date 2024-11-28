-- Written by Ton, with love. Feel free to modify, consider this under the MIT license.

--[[
    SHIPPETEER
]]

--[[ DEPENDENCIES ]]

package.path = package.path .. ";./modules/?.lua"
local async = require("async_actions")
local components = require("components")
local config = require("config")
local lqr = require("lqr")
local networking = require("networking")
local puppeteer = require("puppeteer")
local utils = require("utils")
local pretty = require("cc.pretty")

--[[ PERIPHERALS ]]

local MODEM = peripheral.find("modem")
local RELAY_TEST_HULL = peripheral.wrap("redstone_relay_5")
local RELAY_TEST_TURRET = peripheral.wrap("redstone_relay_4")
local RELAY_TINY_TEST_HULL = peripheral.wrap("redstone_relay_6")
local ROT_CONTROLLER_TEST_TURRET = peripheral.wrap("Create_RotationSpeedController_0")

--[[ SETTINGS / CONSTANTS ]]

local INCOMING_CHANNEL, OUTGOING_CHANNEL = 6060, 6060
local MY_ID = "shippeteer"
local SLEEP_INTERVAL = 1 / 20

--[[ STATE VARIABLES ]]

local movables = {}

--[[ FUNCTIONS ]]

local function turn_off(relay) for _, side in pairs(rs.getSides()) do relay.setOutput(side, false) end end
local function timeout(duration) return debug.getinfo(2).currentline, duration end
local function xz(x, z) return vector.new(x, 0, z) end
local function xyz(x, y, z) return vector.new(x, y, z) end
local function add_movable(vehicle) for _, comp in pairs(utils.ensure_is_table(vehicle)) do table.insert(movables, comp) end end

--[[ DEPENDENCIES SETUP ]]

puppeteer.init(SLEEP_INTERVAL)
networking.set_modem(MODEM)
networking.set_channels(INCOMING_CHANNEL, OUTGOING_CHANNEL)
networking.set_id(MY_ID)

--[[ PERIPHERALS SETUP ]]

turn_off(RELAY_TEST_HULL)
turn_off(RELAY_TEST_TURRET)
ROT_CONTROLLER_TEST_TURRET.setTargetSpeed(0)

--[[ VEHICLE ASSIGNMENT ]]

-- Naming
local NAME_TEST_HULL = "test_hull"
local NAME_TEST_TURRET = "test_turret"
local NAME_TINY_TEST_HULL = "tiny_test_hull"

-- Component creation
local COMPONENT_TEST_HULL = components.hull().create(NAME_TEST_HULL, xyz(10.6, 1.7, 11.4),
    RELAY_TEST_HULL, "front", "left", "right", "back")
local COMPONENT_TEST_TURRET = components.turret().create(NAME_TEST_TURRET, xyz(10.3, 2.7, 12.5),
    RELAY_TEST_TURRET, ROT_CONTROLLER_TEST_TURRET)
local COMPONENT_TINY_TEST_HULL = components.hull().create(NAME_TINY_TEST_HULL, xyz(-0.1, 2.1, 11.6),
    RELAY_TINY_TEST_HULL, "front", { "left", "front" }, { "right", "left", "front" }, { "back", "front" })

-- Extra assignments
COMPONENT_TEST_HULL.add_child_component(COMPONENT_TEST_TURRET)
COMPONENT_TEST_TURRET.add_weapon("autocannon", "front", true, 8)

-- Vehicle assignment
local VEHICLE_TEST      = { hull = COMPONENT_TEST_HULL, turret = COMPONENT_TEST_TURRET }
local VEHICLE_TINY_TEST = { hull = COMPONENT_TINY_TEST_HULL }

-- Movable registration
add_movable(VEHICLE_TEST)
add_movable(VEHICLE_TINY_TEST)

--[[ STATE ]]

local function update_information()
    for _, movable in pairs(movables) do
        movable.update_info(networking.get_message(movable.get_name()))
    end
end

local function main()
    while true do
        networking.remove_old_packets()
        update_information()
        async.update()
        sleep(SLEEP_INTERVAL)
    end
end

--[[ SCRIPT ]]

local function script()
    print("Starting actions.")
    async.pause_until_terminated(puppeteer.reset(VEHICLE_TEST.hull, VEHICLE_TINY_TEST.hull))
    async.pause_until_terminated(puppeteer.unfreeze(VEHICLE_TEST.hull, VEHICLE_TINY_TEST.hull))
    sleep(0.5) -- Otherwise stuff will get goofy.

    local path1 = puppeteer.path_move_to(VEHICLE_TEST.hull,
        { xz(30, 20), xz(50, 0), xz(30, -25), xz(10, 10) }
    )
    local fire_mission = puppeteer.fire_at(VEHICLE_TEST.turret, xz(30, 0),
        puppeteer.fire, { VEHICLE_TEST.turret, "autocannon", 30 }
    )
    local path2 = puppeteer.path_move_to(VEHICLE_TINY_TEST.hull,
        { xz(50, 20), xz(30, -25), xz(0, 0) }
    )
    async.pause_until_terminated(path1, path2)
    async.pause_until_terminated(path2)
    async.pause_until_terminated(
        fire_mission,
        puppeteer.move_to(VEHICLE_TEST.hull, xz(-20, -20), true)
    )
    async.pause_until_terminated(puppeteer.turret_to_idle(VEHICLE_TEST.turret))
    puppeteer.reset(VEHICLE_TEST.hull, VEHICLE_TINY_TEST.hull)
    print("Finished performing actions.")
end

parallel.waitForAll(main, networking.message_handler, script)

--- @TODO: test non_continuous and all cannon firing
--- @TODO: ships shouldn't be able to have children; move that to movables --> overload get_field_all in movable()
--- @TODO: tune LQR further to allow for firing on the move.

--- @BUG: firing mission + movement at same time with same relay, causes weirdness.
--- @TODO: follow(comp, comp2)
--- @LATER: create an installer that downloads all the modules
