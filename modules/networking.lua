-- Written by Ton, with love. Feel free to modify, consider this under the MIT license.

local utils = require("utils")
local pretty = require("cc.pretty")

--[[
    NETWORKING MODULE
]]

local networking = setmetatable({}, {})

--[[ STATE VARIABLES ]]

local packet_decay_time = 0.5
local modem
local incoming_channel, outgoing_channel
local my_id
local inbox = {}

--- Run this in parallel. Note: it is a good idea to call
--- `networking.remove_old_packets()` in your main loop.
function networking.message_handler()
    modem.open(incoming_channel)
    while true do
        local _, _, channel, _, incoming_packet, _
        repeat
            _, _, channel, _, incoming_packet, _ = os.pullEvent("modem_message")
        until channel == incoming_channel

        -- If any of these 2 are weird, skip immediately; we don't talk to strangers on the internet.
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
function networking.remove_decayed_packets()
    local current_time = utils.time_seconds()
    for key, packet in pairs(inbox) do
        if current_time > packet["time"] + packet_decay_time then
            inbox[key] = nil
        end
    end
end

--- Wraps and transmits the given message inside a dict with format:
--- `{ id = ..., time = ..., message = your_message }`
--- @param message any
function networking.send_packet(message)
    local packet = {
        ["id"] = my_id,
        ["time"] = utils.time_seconds(),
        ["message"] = message,
    }
    modem.transmit(outgoing_channel, incoming_channel, packet)
end

--- Wraps the given message inside a dict with format:
--- `{ id = ..., time = ..., message = your_message }`
--- Useful if you want to do encryption stuff or something... hopefully.
--- @param id string
--- @param message any
--- @return table packet
function networking.create_packet(id, message)
    return {
        ["id"] = id,
        ["time"] = utils.time_seconds(),
        ["message"] = message,
    }
end

--- @param m table Peripheral
function networking.set_modem(m)
    modem = m
end

--- Only relevant when using `remove_decayed_packets()`. Default is 0.5 seconds.
--- @param time number Time in seconds. Setting time <= 0 should not be done.
function networking.set_packet_decay_time(time)
    packet_decay_time = time
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
    local packet = networking.get_packet(id)
    return packet and packet["message"]
end

--- Workaround for preventing reading the same message multiple
--- times across multiple program loops. The networking module
--- wasn't initially built for this (stabilisers and such send
--- messages constantly). Using raw modems would've been better,
--- but hey, I want to re-use code, even if it's overkill/convoluted.
--- @param id string
--- @return boolean success true/false for success/failure
function networking.mark_as_read(id)
    local packet = networking.get_packet(id)
    if packet then
        packet["read"] = true
        return true
    else
        return false
    end
end

--- @param id string
--- @return boolean
function networking.has_been_read(id)
    local packet = networking.get_packet(id)
    return packet and packet["read"] or false
end

return networking
