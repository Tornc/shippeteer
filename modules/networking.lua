-- Written by Ton, with love. Feel free to modify, consider this under the MIT license.

local utils = require("utils")

--[[
    NETWORKING MODULE
]]

local networking = setmetatable({}, {})

--[[ CONSTANTS / SETTINGS ]]

local PACKET_DECAY_TIME = 0.5

--[[ STATE VARIABLES ]]

local modem
local incoming_channel, outgoing_channel
local my_id
local inbox = {}

--- Run this in parallel.
function networking.message_handler()
    modem.open(incoming_channel)
    while true do
        local _, _, channel, _, incoming_packet, _
        repeat
            _, _, channel, _, incoming_packet, _ = os.pullEvent("modem_message")
        until channel == incoming_channel

        if incoming_packet["id"] == nil then goto continue end
        if incoming_packet["time"] == nil then goto continue end
        if inbox[incoming_packet["id"]] ~= nil and incoming_packet["time"] < inbox[incoming_packet["id"]]["time"] then goto continue end

        inbox[incoming_packet["id"]] = incoming_packet
        ::continue::
    end
end

--- Run this every loop iteration. Note that we can't put call this inside message_handler,
--- as that will run into problems when there are 0 incoming packets. The message_handler
--- will keep sitting inside the repeat until loop, therefore not running the function call.
function networking.remove_old_packets()
    local current_time = utils.current_time_seconds()
    for key, packet in pairs(inbox) do
        if current_time > packet["time"] + PACKET_DECAY_TIME then
            inbox[key] = nil
        end
    end
end

--- Wraps and transmits the given message inside a dict with format: `{id = ..., time = ..., message = your_message}`
--- @param message any
function networking.send_packet(message)
    local packet = {
        ["id"] = my_id,
        ["time"] = utils.current_time_seconds(),
        ["message"] = message,
    }
    modem.transmit(outgoing_channel, incoming_channel, packet)
end

--- @param m table Peripheral
function networking.set_modem(m)
    modem = m
end

--- @param incoming integer
--- @param outgoing integer
function networking.set_channels(incoming, outgoing)
    incoming_channel, outgoing_channel = incoming, outgoing
end

--- @param id string
function networking.set_id(id)
    my_id = id
end

--- @return table inbox All incoming messages
function networking.get_inbox()
    return inbox
end

--- @param id string
--- @return table
function networking.get_packet(id)
    return inbox[id]
end

--- @param id string
--- @return any
function networking.get_message(id)
    return inbox[id] and inbox[id]["message"]
end

return networking
