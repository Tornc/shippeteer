--[[ TESTING ]]

periphemu.create("top", "modem")

--[[ DEPENDENCIES ]]

-- package.path = package.path .. ";../modules/?.lua"
package.path           = package.path .. ";./modules/?.lua"
local networking       = require("networking")
local utils            = require("utils")
local pretty           = require("cc.pretty")

local INCOMING_CHANNEL = 6060
local OUTGOING_CHANNEL = 6060
local MY_ID            = "fake_cannon"
local COMMAND_ID       = "battery_command"

local MODEM            = peripheral.find("modem")

networking.set_modem(MODEM)
networking.set_channels(INCOMING_CHANNEL, OUTGOING_CHANNEL)
networking.set_id(MY_ID)

local function main()
    while true do
        networking.remove_decayed_packets()

        local command_msg = networking.get_message(COMMAND_ID)
        if not command_msg then goto continue end
        if networking.has_been_read(COMMAND_ID) then goto continue end
        networking.mark_as_read(COMMAND_ID)
        if
            command_msg[1] and
            command_msg[1]["type"] == "info_request"
        then
            pretty.pretty_print(command_msg)
            write("Send info?")
            read()
            networking.send_packet(
                {
                    type = "cannon_info",
                    position = vector.new(0, 0, 0),
                    velocity_ms = 160,
                    cannon_length = 12,
                    cannon_type = "big",
                    min_pitch = -30,
                    max_pitch = 60
                }
            )
            print("Info sent.")
        end
        if
            command_msg and
            command_msg[MY_ID] and
            command_msg[MY_ID]["type"] == "fire_mission"
        then
            print("Yaw/pitch:", utils.round(command_msg[MY_ID]["yaw"], 2), utils.round(command_msg[MY_ID]["pitch"], 2))
            write("Complete mission?")
            read()
            networking.send_packet({ type = "fire_mission_completion" })
            print("Completion sent.")
            write("Reload?")
            read()
            networking.send_packet({ type = "has_reloaded" })
            print("Reloaded status sent.")
        end

        ::continue::
        os.sleep(0.05)
    end
end

parallel.waitForAny(main, networking.message_handler)
