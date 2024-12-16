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

        -- If any of these 3 are weird, skip immediately; we don't talk to strangers on the internet.
        if incoming_packet["id"] == nil then goto continue end
        if incoming_packet["time"] == nil then goto continue end
        if incoming_packet["recipients"] == nil then goto continue end

        -- `recipients` is optional, but due to `ensure_is_table`, we know that length of 0 means it's for everyone.
        -- If there _is_ a recipient, check if that's us, otherwise skip.
        if #incoming_packet["recipients"] > 1 and (not utils.contains(incoming_packet["recipients"], my_id)) then goto continue end
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
--- `{ id = ..., recipients = ..., time = ..., message = your_message }`
--- @param message any
--- @param recipients string|table|nil IDs, wrap in table if there's multiple. nil means everyone.
function networking.send_packet(message, recipients)
    local packet = {
        ["id"] = my_id,
        ["recipients"] = utils.ensure_is_table(recipients),
        ["time"] = utils.time_seconds(),
        ["message"] = message,
    }
    modem.transmit(outgoing_channel, incoming_channel, packet)
end

--- Wraps the given message inside a dict with format:
--- `{ id = ..., recipients = ..., time = ..., message = your_message }`
--- Useful if you want to do encryption stuff or something... hopefully.
--- @param id string
--- @param message any
--- @param recipients string|table|nil IDs, wrap in table if there's multiple. nil means everyone.
--- @return table packet
function networking.create_packet(id, message, recipients)
    return {
        ["id"] = id,
        ["recipients"] = utils.ensure_is_table(recipients),
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
    return inbox[id] and inbox[id]["message"]
end

return networking
