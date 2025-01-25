--[[ DEPENDENCIES ]]

local config = require("config")
local elements = require("elements")
local font = require("cc_font")
local utils = require("utils")
local vector2d = require("vector2d")
local pretty = require("cc.pretty")

--[[ PERIPHERALS ]]

local HOLOGRAM = peripheral.find("hologram")
local PLAYER_DETECTOR = peripheral.find("playerDetector")

--[[ CONSTANTS / SETTINGS ]]

local SEA_LEVEL = 62
local ASPECT_RATIO = 16 / 9
local HMD_BACKGROUND_COLOUR = 0x00A0FF20
local HMD_TEXT_COLOUR = 0x00FF00FF
local HMD_SCREEN_WIDTH = 1024 -- 1024x1024 is max
local HMD_SCREEN_HEIGHT = utils.round(HMD_SCREEN_WIDTH / ASPECT_RATIO)
local PILOT_USERNAME = "TuongL"

--[[ STATE VARIABLES ]]

local pilot = {}
local plane = {
    position = vector.new(),
    velocity = vector.new(),
    omega = vector.new(),
    orientation = vector.new(), -- x = Roll, y = Pitch, z = Yaw

    speed = 0,
    barometric_altitude = 0,
}

--[[ PERIPHERALS SETUP ]]

HOLOGRAM.Resize(HMD_SCREEN_WIDTH, HMD_SCREEN_HEIGHT)
HOLOGRAM.SetScale(0, 0)                       -- In order to fully hide the hologram
HOLOGRAM.SetClearColor(HMD_BACKGROUND_COLOUR) -- Default: 0x00A0FF6F
HOLOGRAM.Rename("HMD_" .. PILOT_USERNAME)

--[[ DEPENDENCIES SETUP ]]

elements.set_screen(HOLOGRAM)
elements.set_screen_width(HMD_SCREEN_WIDTH)
elements.set_screen_height(HMD_SCREEN_HEIGHT)
-- networking.set_modem(MODEM)
-- networking.set_channels(INCOMING_CHANNEL, OUTGOING_CHANNEL)
-- networking.set_id(MY_ID)

--[[ FUNCTIONS ]]

--- Converts a binary bitmap into a bitmap by replacing 1s with a specified colour and 0s with a background colour.
--- @param binary_bitmap table
--- @param colour integer The colour to use for pixels where the binary value is 1.
--- @return table bitmap A table representing the bitmap with applied colours.
local function bake_bitmap(binary_bitmap, colour)
    local bitmap = {}
    for i = 1, #binary_bitmap do bitmap[i] = binary_bitmap[i] == 1 and colour or HMD_BACKGROUND_COLOUR end
    return bitmap
end

--- Scales a bitmap to a new size using nearest-neighbor interpolation.
--- @param bitmap table The original bitmap to scale.
--- @param original_width integer The width of the original bitmap.
--- @param original_height integer The height of the original bitmap.
--- @param scale integer The scaling factor to apply (e.g., 2 for doubling the size).
--- @return table scaled_bitmap The scaled bitmap.
--- @return integer scaled_width The width of the scaled bitmap.
--- @return integer scaled_height The height of the scaled bitmap.
local function scale_bitmap(bitmap, original_width, original_height, scale)
    local scaled_width = original_width * scale
    local scaled_height = original_height * scale
    local scaled_bitmap = {}

    for y = 0, scaled_height - 1 do
        local original_y = math.floor(y / scale)
        for x = 0, scaled_width - 1 do
            local original_x = math.floor(x / scale)
            local original_index = original_y * original_width + original_x + 1
            scaled_bitmap[y * scaled_width + x + 1] = bitmap[original_index]
        end
    end

    return scaled_bitmap, scaled_width, scaled_height
end

local function draw_char(x, y, char_key, colour, scale)
    local char_data = font.bitmap[char_key]
    assert(char_data, "Character not found in font: " .. char_key)
    local char_width, char_height = font.char_width, font.char_height
    if scale and scale > 1 then
        char_data, char_width, char_height = scale_bitmap(char_data, font.char_width, font.char_height, scale)
    end
    HOLOGRAM.Blit(x, y, char_width, char_height, bake_bitmap(char_data, colour), 0)
end

local function draw_string(x, y, text, colour, scale)
    scale = (scale and scale > 1) and scale or 1
    for i = 1, #text do
        local char = text:sub(i, i)
        local char_key = string.format("%02X", string.byte(char)) -- Convert character to hex key
        draw_char(x + (i - 1) * font.char_width * scale, y, char_key, colour, scale)
    end
end

local function update_information()
    -- Relevant fields: .x .y .z .eyeHeight .yaw .pitch
    pilot = PLAYER_DETECTOR.getPlayer(PILOT_USERNAME)

    plane.position = utils.tbl_to_vec(ship.getWorldspacePosition())
    plane.velocity = utils.tbl_to_vec(ship.getVelocity())
    plane.omega = utils.tbl_to_vec(ship.getOmega())

    local ship_matrix = ship.getTransformationMatrix()
    plane.orientation = vector.new(
        math.deg(math.atan2(ship_matrix[2][1], ship_matrix[2][2])),
        math.deg(math.asin(-ship_matrix[2][3])),
        math.deg(math.atan2(ship_matrix[1][3], ship_matrix[3][3]))
    )

    plane.speed = plane.velocity:length()
    plane.barometric_altitude = plane.position.y - SEA_LEVEL
end

local function main()
    local element1 = elements.rectangle().create(
        vector2d.new(HMD_SCREEN_WIDTH * 0.4, HMD_SCREEN_HEIGHT * 0.4),
        2, 100, 10, HMD_TEXT_COLOUR
    )
    local element2 = elements.triangle().create(
        vector2d.new(HMD_SCREEN_WIDTH * 0.5, HMD_SCREEN_HEIGHT * 0.5),
        100, 10, HMD_TEXT_COLOUR
    )
    local element3 = elements.polygon().create(
        vector2d.new(HMD_SCREEN_WIDTH * 0.6, HMD_SCREEN_HEIGHT * 0.6),
        5, 100, 10, HMD_TEXT_COLOUR
    )
    local element4 = elements.circle().create(
        vector2d.new(HMD_SCREEN_WIDTH * 0.7, HMD_SCREEN_HEIGHT * 0.7),
        100, 10, HMD_TEXT_COLOUR
    )
    local element5 = elements.curved_line().create(
        vector2d.new(HMD_SCREEN_WIDTH * 0.8, HMD_SCREEN_HEIGHT * 0.8),
        1, false,
        100, 10, HMD_TEXT_COLOUR
    )
    local element6 = elements.diamond().create(
        vector2d.new(HMD_SCREEN_WIDTH * 0.9, HMD_SCREEN_HEIGHT * 0.4),
        1, 100, 10, HMD_TEXT_COLOUR
    )
    while true do
        update_information()

        -- local t1 = utils.time_seconds()
        HOLOGRAM.Clear()
        draw_string(
            HMD_SCREEN_WIDTH * 0.2, HMD_SCREEN_HEIGHT * 0.2,
            utils.center_string(tostring(utils.round(-pilot.yaw % 360)), 3),
            HMD_TEXT_COLOUR, 4
        )
        draw_string(HMD_SCREEN_WIDTH * 0.3, HMD_SCREEN_HEIGHT * 0.3, "\x05\x1A\xAB New font!", HMD_TEXT_COLOUR, 3)

        element1.draw()
        element2.draw()
        element3.draw()
        element4.draw()
        element5.draw()
        element6.draw()

        -- HOLOGRAM.DrawTriangle(
        --     HMD_SCREEN_WIDTH * 0.4, HMD_SCREEN_HEIGHT * 0.4,
        --     HMD_SCREEN_WIDTH * 0.5, HMD_SCREEN_HEIGHT * 0.5,
        --     HMD_SCREEN_WIDTH * 0.3, HMD_SCREEN_HEIGHT * 0.5,
        --     0xFF0000FF, 0x00FF00FF, 0x0000FFFF, 0
        -- )

        HOLOGRAM.Flush()
        -- print(utils.time_seconds() - t1)
        os.sleep(0.05)
    end
end

main()
