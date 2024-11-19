-- Written by Ton, with love. Feel free to modify, consider this under the MIT license.

--[[
    SHIPPETEER
]]

--[[ TESTING ]]

periphemu.create("top", "modem")
local function fake_peripheral() end

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
local REDROUTER_LEOPARD_HULL = { fake_peripheral }
local REDROUTER_LEOPARD_TURRET = { fake_peripheral }
local ROT_CONTROLLER_LEOPARD_TURRET = { fake_peripheral }

--[[ CONSTANTS / SETTINGS ]]

local INCOMING_CHANNEL, OUTGOING_CHANNEL = 6060, 6060
local MY_ID = "shippeteer"
local SLEEP_INTERVAL = 1 / 20

--[[ DEPENDENCIES SETUP ]]

puppeteer.init(SLEEP_INTERVAL)
networking.set_modem(MODEM)
networking.set_channels(INCOMING_CHANNEL, OUTGOING_CHANNEL)
networking.set_id(MY_ID)

local MOVABLES = {}
local NAME_LEOPARD_HULL = "leo_hull"
local NAME_LEOPARD_HULL_DECO = "leo_hull_deco"
local NAME_LEOPARD_TURRET = "leo_turret"
local NAME_LEOPARD_TURRET_DECO = "leo_turret_deco"

--[[ STATE VARIABLES ]]

-- tehe ~ ⭐

--[[ FUNCTIONS ]]

local function timeout(duration) return debug.getinfo(2).currentline, duration end
local function xz(x, z) return vector.new(x, 0, z) end
local function xyz(x, y, z) return vector.new(x, y, z) end
local function add_movable(vehicle) for _, comp in pairs(vehicle) do table.insert(MOVABLES, comp) end end

--[[ VEHICLE ASSIGNMENT ]]

local COMPONENT_LEOPARD_HULL_DECO = components.ship().create(NAME_LEOPARD_HULL_DECO, xyz(0, 0, 0))
local COMPONENT_LEOPARD_HULL = components.hull().create(NAME_LEOPARD_HULL, xyz(1, 1, 1),
    REDROUTER_LEOPARD_HULL, "freq_front", "freq_left", "freq_right", { "freq_back", "freq_back2" })
local COMPONENT_LEOPARD_TURRET_DECO = components.ship().create(NAME_LEOPARD_TURRET_DECO, xyz(2, 2, 2))
local COMPONENT_LEOPARD_TURRET = components.turret().create(NAME_LEOPARD_TURRET, xyz(3, 3, 3),
    REDROUTER_LEOPARD_TURRET, ROT_CONTROLLER_LEOPARD_TURRET)

COMPONENT_LEOPARD_HULL.add_child_component(COMPONENT_LEOPARD_HULL_DECO, COMPONENT_LEOPARD_TURRET)
COMPONENT_LEOPARD_TURRET.add_child_component(COMPONENT_LEOPARD_TURRET_DECO)
COMPONENT_LEOPARD_TURRET.add_weapon("cannon", "top", false, 5.0)
COMPONENT_LEOPARD_TURRET.add_weapon("coax_machinegun", { "bottom", "left" }, true, 15)

local VEHICLE_LEOPARD = { hull = COMPONENT_LEOPARD_HULL, turret = COMPONENT_LEOPARD_TURRET }
add_movable(VEHICLE_LEOPARD)

-- pretty.pretty_print(COMPONENT_LEOPARD_HULL.get_controls())

-- local controls = COMPONENT_LEOPARD_HULL.get_controls()
-- for key, links in pairs(controls) do
--     for _, link in pairs(utils.ensure_is_table(links)) do
--         print(key, link)
--     end
-- end


--[[ SCRIPT ]]

local function script()
    puppeteer.test(1, 2, timeout(1))
    -- puppeteer.path_move_to(test_c2, {
    --     xz(10, 10),
    --     { xz(20, 20), true },
    --     xz(30, 30),
    -- })
    -- async.pause_until_terminated(puppeteer.reset(COMPONENT_LEOPARD_HULL))
    -- async.pause_until_terminated(puppeteer.unfreeze(COMPONENT_LEOPARD_HULL))
    -- async.pause_until_terminated(puppeteer.freeze(COMPONENT_LEOPARD_HULL))
    -- pretty.pretty_print(async.get_actions())
end

--[[ STATE ]]

local function update_information()
    for _, movable in pairs(MOVABLES) do
        movable.update_info(networking.get_message(movable.get_name()))
    end
    -- term.clear()
    -- pretty.pretty_print(VEHICLE_LEOPARD.hull.get_info())
    -- local info = VEHICLE_LEOPARD.turret.get_info()
    -- if info then
    --     pretty.pretty_print(info["yaw"])
    -- end
end

local function main()
    while true do
        update_information()
        async.update()
        sleep(SLEEP_INTERVAL)
    end
end

parallel.waitForAll(main, script, networking.message_handler)
