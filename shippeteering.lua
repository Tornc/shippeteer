-- Written by Ton, with love. Feel free to modify, consider this under the MIT license.

--[[
    SHIPPETEER
]]

--[[ TESTING ]]

-- periphemu.create("top", "modem")
-- local function fake_peripheral() end

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
local RELAY_TEST_HULL = peripheral.wrap("redstone_relay_3")
local RELAY_TEST_TURRET = peripheral.wrap("redstone_relay_4")
local ROT_CONTROLLER_TEST_TURRET = peripheral.wrap("Create_RotationSpeedController_0")
-- local RELAY_LEOPARD_HULL = { fake_peripheral }
-- local RELAY_LEOPARD_TURRET = { fake_peripheral }
-- local ROT_CONTROLLER_LEOPARD_TURRET = { fake_peripheral }

--[[ CONSTANTS / SETTINGS ]]

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

-- local NAME_LEOPARD_HULL = "leo_hull"
-- local NAME_LEOPARD_HULL_DECO = "leo_hull_deco"
-- local NAME_LEOPARD_TURRET = "leo_turret"
-- local NAME_LEOPARD_TURRET_DECO = "leo_turret_deco"

-- local COMPONENT_LEOPARD_HULL_DECO = components.ship().create(NAME_LEOPARD_HULL_DECO, xyz(0, 0, 0))
-- local COMPONENT_LEOPARD_HULL = components.hull().create(NAME_LEOPARD_HULL, xyz(1, 1, 1),
--     RELAY_LEOPARD_HULL, "freq_front", "freq_left", "freq_right", { "freq_back", "freq_back2" })
-- local COMPONENT_LEOPARD_TURRET_DECO = components.ship().create(NAME_LEOPARD_TURRET_DECO, xyz(2, 2, 2))
-- local COMPONENT_LEOPARD_TURRET = components.turret().create(NAME_LEOPARD_TURRET, xyz(3, 3, 3),
--     RELAY_LEOPARD_TURRET, ROT_CONTROLLER_LEOPARD_TURRET)

-- COMPONENT_LEOPARD_HULL.add_child_component(COMPONENT_LEOPARD_HULL_DECO, COMPONENT_LEOPARD_TURRET)
-- COMPONENT_LEOPARD_TURRET.add_child_component(COMPONENT_LEOPARD_TURRET_DECO)
-- COMPONENT_LEOPARD_TURRET.add_weapon("cannon", "top", false, 5.0)
-- COMPONENT_LEOPARD_TURRET.add_weapon("coax_machinegun", { "bottom", "left" }, true, 15)

-- local VEHICLE_LEOPARD = { hull = COMPONENT_LEOPARD_HULL, turret = COMPONENT_LEOPARD_TURRET }
-- add_movable(VEHICLE_LEOPARD)

-- Naming
local NAME_TEST_HULL = "test_hull"
local NAME_TEST_TURRET = "test_turret"

-- Component creation
local COMPONENT_TEST_HULL = components.hull().create(NAME_TEST_HULL, xyz(10, 3, 10),
    RELAY_TEST_HULL, "front", "left", "right", "back")
local COMPONENT_TEST_TURRET = components.turret().create(NAME_TEST_TURRET, xyz(10, 4, 10),
    RELAY_TEST_TURRET, ROT_CONTROLLER_TEST_TURRET)

-- Extra assignments
COMPONENT_TEST_HULL.add_child_component(COMPONENT_TEST_TURRET)
COMPONENT_TEST_TURRET.add_weapon("autocannon", "front", true, 10)

-- Vehicle assignment
local VEHICLE_TEST = { hull = COMPONENT_TEST_HULL, turret = COMPONENT_TEST_TURRET }

-- Movable registration
add_movable(VEHICLE_TEST)

--[[ STATE ]]

local function update_information()
    for _, movable in pairs(movables) do
        movable.update_info(networking.get_message(movable.get_name()))
    end
end

local function main()
    while true do
        update_information()
        async.update()
        sleep(SLEEP_INTERVAL)
    end
end

--[[ SCRIPT ]]

local function script()
    async.pause_until_terminated(puppeteer.reset(VEHICLE_TEST.hull))
    async.pause_until_terminated(puppeteer.unfreeze(VEHICLE_TEST.hull))
    sleep(0.5) -- Otherwise stuff will get goofy.

    local path = puppeteer.path_move_to(VEHICLE_TEST.hull,
        { xz(30, 20), xz(50, 0), xz(30, -25), xz(10, 10) }
    )
    local fire_mission = puppeteer.fire_at(VEHICLE_TEST.turret, xz(30, 0),
        puppeteer.fire, { VEHICLE_TEST.turret, "autocannon", 25 }
    )
    async.pause_until_terminated(path, fire_mission)
    local idle = puppeteer.turret_to_idle(VEHICLE_TEST.turret)
    local rev = puppeteer.move_to(VEHICLE_TEST.hull, xz(-20, -20), true)
    async.pause_until_terminated(idle, rev)
    puppeteer.reset(VEHICLE_TEST.hull)
    print("Done.")
end

parallel.waitForAll(main, script, networking.message_handler)

-- commands.exec("vs set-static test_hull false")
-- commands.exec("setblock ~ ~5 ~ minecraft:stone")

--- @TODO: tune LQR further --> 
--- @BUG: firing mission + movement at same time with same relay, causes weirdness.
