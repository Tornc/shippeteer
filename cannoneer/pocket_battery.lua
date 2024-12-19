--[[ TESTING ]]

periphemu.create("top", "modem")
periphemu.create("back", "speaker")

--[[ DEPENDENCIES ]]

-- package.path = package.path .. ";../modules/?.lua"
package.path = package.path .. ";./modules/?.lua"
local config = require("config")
local dfpwm = require("cc.audio.dfpwm")
local networking = require("networking")
local utils = require("utils")
local pretty = require("cc.pretty")

--[[ PERIPHERALS ]]

local MODEM = peripheral.find("modem")
local SPEAKER = peripheral.find("speaker")

--[[ SETTINGS / CONSTANTS ]]

local INCOMING_CHANNEL, OUTGOING_CHANNEL = 6060, 6060
local BATTERY_ID_PREFIX = "battery_"
local MY_ID = BATTERY_ID_PREFIX .. "pocket"
local COMMAND_ID = BATTERY_ID_PREFIX .. "command"
local SOUND_VOLUME = 1
local SOUND_EXTENSION_TYPE = "dfpwm"
local SOUNDS_DIRECTORY_PATH = fs.getDir(shell.getRunningProgram()) .. "./sounds/"
local START_FIRE = {
    "RU_StartFire1",
    "RU_StartFire2",
}
local END_FIRE = {
    "RU_EndFire1",
    "RU_EndFire2",
    "RU_EndFire3",
    "RU_EndFire4",
}
local DECODER = dfpwm.make_decoder()
local VERSION = "0.1-unfinished"
local DISPLAY_STRING = "=][= POCKET v" .. VERSION .. " =][="
local SLEEP_INTERVAL = 1 / 20

--[[ DEPENDENCIES SETUP ]]

networking.set_modem(MODEM)
networking.set_channels(INCOMING_CHANNEL, OUTGOING_CHANNEL)
networking.set_id(MY_ID)

local function play_sound(file_name)
    local file_path = SOUNDS_DIRECTORY_PATH .. file_name .. "." .. SOUND_EXTENSION_TYPE
    if not fs.exists(file_path) then error(file_path .. " does not exist!") end
    for chunk in io.lines(file_path, 16 * 1024) do
        local buffer = DECODER(chunk)
        while not SPEAKER.playAudio(buffer, SOUND_VOLUME) do
            os.pullEvent("speaker_audio_empty")
        end
    end
end

local function download(url, file_name)
    local content = http.get(url).readAll()
    if not content then error("Could not connect to website") end
    local f = fs.open(file_name, "w")
    f.write(content)
    f.close()
end

--- @param type_conversion_func function
local function convert_type(var, type_conversion_func)
    return type_conversion_func(var)
end

--- Yes, I'm using config.ask_setting() because it's convenient.
--- @return table Vector
--- @return integer
--- @return integer
--- @return integer
local function ask_barrage_parameters()
    local target_pos = convert_type(
        config.ask_setting(
            "Target position <X Y Z>?",
            { "0 0 0" },
            function(i)
                local coordinate = {}
                for value in i:gmatch("%S+") do
                    if tonumber(value) ~= nil then
                        table.insert(coordinate, value)
                    else
                        return false
                    end
                end
                return #coordinate == 3
            end
        ),
        function(i)
            local coordinate = {}
            for v in i:gmatch("%S+") do table.insert(coordinate, tonumber(v)) end
            return utils.tbl_to_vec(coordinate)
        end
    )
    local spacing = convert_type(
        config.ask_setting(
            "Spacing?",
            {},
            function(i) return tonumber(i) end
        ),
        function(i) return tonumber(i) end
    )
    local semi_width = convert_type(
        config.ask_setting(
            "Semi-width?",
            {},
            function(i) return tonumber(i) end
        ),
        function(i) return tonumber(i) end
    )
    local semi_height = convert_type(
        config.ask_setting(
            "Semi-height?",
            {},
            function(i) return tonumber(i) end
        ),
        function(i) return tonumber(i) end
    )
    return target_pos, spacing, semi_width, semi_height
end

local function confirm_ask__barrage_parameters()
    local tpos, sp, sw, sh
    while true do
        tpos, sp, sw, sh = ask_barrage_parameters()
        print(string.rep("-", #DISPLAY_STRING))
        print("PLEASE CONFIRM!")
        print("Target position:", tpos)
        print("Spacing:", sp)
        print("Semi-width:", sw)
        print("Semi-height:", sh)
        print(string.rep("-", #DISPLAY_STRING))
        io.write("y/n: ")
        local choice = read()
        print(string.rep("-", #DISPLAY_STRING))
        if string.lower(choice) == "y" then break end
    end
    return tpos, sp, sw, sh
end

--- Note: inside is a while-true loop. This _will_ wait
--- forever if there's no response given.
local function await_barrage_completion()
    print("Your order of destruction is being carried out.")
    print("Please be patient. Thank you. \x02")
    while true do
        networking.remove_decayed_packets()
        local command_msg = networking.get_message(COMMAND_ID)
        if command_msg and command_msg["type"] == "artillery_barrage_completion" then
            break
        end
        os.sleep(SLEEP_INTERVAL)
    end
    print(string.rep("-", #DISPLAY_STRING))
end

local function main()
    print(DISPLAY_STRING)
    print(string.rep("-", #DISPLAY_STRING))

    while true do
        local tpos, sp, sw, sh = confirm_ask__barrage_parameters()
        networking.send_packet(
            {
                type = "artillery_barrage_request",
                target_position = tpos,
                spacing = sp,
                semi_width = sw,
                semi_height = sh,

            },
            COMMAND_ID
        )
        play_sound(START_FIRE[math.random(#START_FIRE)])
        await_barrage_completion()
        play_sound(END_FIRE[math.random(#END_FIRE)])
    end
end

parallel.waitForAny(main, networking.message_handler)

--- @TODO (later): prompt for downloading US/RU/OTHER voicelines.
-- THIS WORKS!
-- download(
--     "https://github.com/Tornc/cc-vs_flighthud/raw/refs/heads/main/voices/betty/ALTITUDE.dfpwm",
--     SOUNDS_DIRECTORY_PATH .. "betty" .. "." .. SOUND_EXTENSION_TYPE
-- )
-- play_sound(SOUNDS_DIRECTORY_PATH .. "betty")
