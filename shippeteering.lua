-- Written by Ton, with love. Feel free to modify, consider this under the MIT license.

--[[
    SHIPPETEER
]]

--[[ DEPENDENCIES ]]

package.path = package.path .. ";./modules/?.lua"
local async = require("async_actions")
local components = require("components")
local networking = require("networking")
local puppeteer = require("puppeteer")
local utils = require("utils")
local pretty = require("cc.pretty")

--[[ PERIPHERALS ]]

local MODEM = peripheral.find("modem")
local RELAY_TEST_HULL = peripheral.wrap("redstone_relay_5")
local RELAY_TEST_TURRET = peripheral.wrap("redstone_relay_4")
local RELAY_TINY_TEST_HULL = peripheral.wrap("redstone_relay_7")
local ROT_CONTROLLER_TEST_TURRET = peripheral.wrap("Create_RotationSpeedController_0")

--[[ SETTINGS / CONSTANTS ]]

local INCOMING_CHANNEL, OUTGOING_CHANNEL = 6060, 6060
local MY_ID = "shippeteer"
local VERSION = "0.2-dev"
local DISPLAY_STRING = "=][= SHIPPETEER v" .. VERSION .. " =][="
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

for _, relay in pairs({ peripheral.find("redstone_relay") }) do turn_off(relay) end
for _, rc in pairs({ peripheral.find("Create_RotationSpeedController") }) do rc.setTargetSpeed(0) end

--[[ VEHICLE ASSIGNMENT ]]

-- Naming
local NAME_TEST_HULL = "test_hull"
local NAME_TEST_TURRET = "test_turret"
local NAME_TINY_TEST_HULL = "tiny_test_hull"

-- Component creation
local COMPONENT_TEST_HULL = components.simple_tracked_hull().create(NAME_TEST_HULL, xyz(10.6, 1.7, 11.4),
    RELAY_TEST_HULL, "front", "left", "right", "back", 128)
local COMPONENT_TEST_TURRET = components.turret().create(NAME_TEST_TURRET, xyz(10.3, 2.7, 12.5),
    RELAY_TEST_TURRET, ROT_CONTROLLER_TEST_TURRET)
local COMPONENT_TINY_TEST_HULL = components.simple_tracked_hull().create(NAME_TINY_TEST_HULL, xyz(-0.1, 2.1, 11.6),
    RELAY_TINY_TEST_HULL, "front", { "left", "front" }, { "right", "left", "front" }, { "back", "front" }, 128)

-- Extra assignments
COMPONENT_TEST_HULL.add_child_component(COMPONENT_TEST_TURRET)
COMPONENT_TEST_TURRET.add_weapon("autocannon", "front", true, 8)
COMPONENT_TEST_TURRET.add_weapon("cannon", "top", false, 5.0)

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
    print(DISPLAY_STRING)
    print(string.rep("-", #DISPLAY_STRING))
    while true do
        networking.remove_decayed_packets()
        update_information()
        async.update()
        os.sleep(SLEEP_INTERVAL)
    end
end

--[[ SCRIPT ]]

local function script()
    print("Starting actions.")
    async.pause_until_terminated(puppeteer.reset(VEHICLE_TEST.hull, VEHICLE_TINY_TEST.hull))
    async.pause_until_terminated(puppeteer.unfreeze(VEHICLE_TEST.hull, VEHICLE_TINY_TEST.hull))
    os.sleep(0.5) -- Otherwise stuff will get goofy.

    local path1 = puppeteer.path_move_to(VEHICLE_TEST.hull,
        { xz(30, 20), xz(50, 0), xz(30, -25), xz(10, 10) }
    )
    local path2 = puppeteer.path_move_to(VEHICLE_TINY_TEST.hull,
        { xz(50, 20), xz(30, -25), xz(0, 0) }
    )
    local fire_autocannon = puppeteer.fire_at(VEHICLE_TEST.turret, xz(30, 0),
        puppeteer.fire, { VEHICLE_TEST.turret, "autocannon", 30 }
    )
    -- async.pause_until_terminated(path1)
    async.pause_until_terminated(path1, path2)
    -- local fire_cannon = puppeteer.fire_at(VEHICLE_TEST.turret, xz(30, 0),
    --     puppeteer.fire, {VEHICLE_TEST.turret, "cannon"}
    -- )
    async.pause_until_terminated(
        fire_autocannon,
        -- fire_cannon,
        puppeteer.move_to(VEHICLE_TEST.hull, xz(-20, -20), true)
    )
    async.pause_until_terminated(puppeteer.turret_to_idle(VEHICLE_TEST.turret))
    puppeteer.reset(VEHICLE_TEST.hull, VEHICLE_TINY_TEST.hull)
    print("Finished performing actions.")
end

local function script2()
    print("Starting actions.")
    -- local lock = puppeteer.lock_on(VEHICLE_TEST.turret, xz(30, 0))
    local lock = puppeteer.lock_on(VEHICLE_TEST.turret, 180)
    async.pause_until_terminated(lock)
    print("Finished performing actions.")
end

parallel.waitForAll(main, networking.message_handler, script)

--- @TODO: assert every goddamn create() parameter in component

--- @TODO: rework components module to use ':' - sombrero
--- @TODO: follow(comp, comp2)
--- @LATER: create an installer that downloads all the modules