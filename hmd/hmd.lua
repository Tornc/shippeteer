--[[ DEPENDENCIES ]]

local config = require("config")
local elements = require("elements")
local font = require("cc_font")
local utils = require("utils")
local transforms_3d = require("transforms_3d")
local vector2d = require("vector2d") -- Not to be confused with vector
local pretty = require("cc.pretty")

--[[ PERIPHERALS ]]

local HOLOGRAM = peripheral.find("hologram")
local PLAYER_DETECTOR = peripheral.find("playerDetector")
local MONITOR = peripheral.find("monitor")

--[[ CONSTANTS / SETTINGS ]]

local SEA_LEVEL = 62
local ASPECT_RATIO = 16 / 9
local HMD_BACKGROUND_COLOUR = 0x00A0FF20
local HMD_TEXT_COLOUR = 0x00FF00FF
local HMD_SCREEN_WIDTH = 1024 -- 1024x1024 is max
local HMD_SCREEN_HEIGHT = utils.round(HMD_SCREEN_WIDTH / ASPECT_RATIO)
local PILOT_USERNAME = "TuongL"
local FOV = 90 -- math.atan(3/4 * math.tan(deg / 2)) * 2

--[[ STATE VARIABLES ]]

local pilot = {}
local camera_position = vector.new()
local plane = {
    position = vector.new(),
    velocity = vector.new(),
    omega = vector.new(),
    orientation = vector.new(), -- x = Roll, y = Pitch, z = Yaw

    speed = 0,
    altitude = 0, -- Note: this is barometric
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

--- @TODO: add space support (instead of printing a 0 bitmap) to save performance
--- also add \t support.
--- @TODO: move these functions to somewhere else (module)
local function draw_string(x, y, text, colour, scale)
    scale = (scale and scale > 1) and scale or 1
    local cur_x, cur_y = x, y
    for i = 1, #text do
        local char = text:sub(i, i)
        if char == "\n" then
            cur_x, cur_y = x, cur_y + font.char_width * scale
        elseif char == "\t" then
            cur_x = cur_x + font.char_width * scale * 4
        elseif char == " " then
            cur_x = cur_x + font.char_width * scale
        else
            local char_key = string.format("%02X", string.byte(char)) -- Convert character to hex key
            draw_char(cur_x, cur_y, char_key, colour, scale)
            cur_x = cur_x + font.char_width * scale
        end
    end
end

local function update_information()
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
    plane.altitude = plane.position.y - SEA_LEVEL

    -- Relevant fields: .x .y .z .eyeHeight .yaw .pitch
    pilot = PLAYER_DETECTOR.getPlayer(PILOT_USERNAME)
    --- @TODO: take ship roll pitch and yaw into account
    camera_position = vector.new(pilot.x, pilot.y + pilot.eyeHeight, pilot.z)
end

--- @param obj_pos table Vector(x, y, z)
--- @return Vector2D
local function proj_3d_to_2d(obj_pos)
    local fov = FOV -- degrees
    local aspect_ratio = ASPECT_RATIO
    local screen_width = HMD_SCREEN_WIDTH
    local screen_height = HMD_SCREEN_HEIGHT
    local cam_pos = camera_position -- vector.new(x, y, z)
    local cam_yaw = pilot.yaw       -- degrees
    local cam_pitch = pilot.pitch   -- degrees

    local screen_x, screen_y
    return vector2d.new(screen_x, screen_y)
end

local function main()
    --[[
    local element1 = elements.rectangle().create(
        vector2d.new(HMD_SCREEN_WIDTH * 0.4, HMD_SCREEN_HEIGHT * 0.4),
        2, 100, 5, HMD_TEXT_COLOUR
    )
    local element2 = elements.triangle().create(
        vector2d.new(HMD_SCREEN_WIDTH * 0.5, HMD_SCREEN_HEIGHT * 0.5),
        100, 2, HMD_TEXT_COLOUR
    )
    local element3 = elements.polygon().create(
        vector2d.new(HMD_SCREEN_WIDTH * 0.6, HMD_SCREEN_HEIGHT * 0.6),
        5, 100, 3, HMD_TEXT_COLOUR
    )
    local element4 = elements.circle().create(
        vector2d.new(HMD_SCREEN_WIDTH * 0.7, HMD_SCREEN_HEIGHT * 0.7),
        100, 4, HMD_TEXT_COLOUR
    )
    local element5 = elements.curved_line().create(
        vector2d.new(HMD_SCREEN_WIDTH * 0.8, HMD_SCREEN_HEIGHT * 0.8),
        1, false,
        100, 2, HMD_TEXT_COLOUR
    )
    local element6 = elements.diamond().create(
        vector2d.new(HMD_SCREEN_WIDTH * 0.9, HMD_SCREEN_HEIGHT * 0.4),
        1, 100, 2, HMD_TEXT_COLOUR
    )
    ]]

    local box = elements.rectangle().create(
        vector2d.new(HMD_SCREEN_WIDTH * 0.5, HMD_SCREEN_HEIGHT * 0.5),
        1, 100, 2, HMD_TEXT_COLOUR
    )

    local red_torch_pos = vector.new(-11, -4, 2)
    local blue_torch_pos = vector.new(-18, -7, -3)
    while true do
        update_information()
        HOLOGRAM.Clear()
        draw_string(0, 0,
            "Head XYZ:" .. tostring(camera_position:round()) .. "\n" ..
            "Y/P:     " .. tostring(vector2d.new(pilot.yaw, pilot.pitch):round()) .. "\n" ..
            "Box XY:  " .. tostring(box.center_point:round()),
            HMD_TEXT_COLOUR, 3
        )

        box.center_point = proj_3d_to_2d(red_torch_pos)
        box.draw()
        box.center_point = proj_3d_to_2d(blue_torch_pos)
        box.draw()

        HOLOGRAM.Flush()
        os.sleep(0.05)
    end
end

main()
