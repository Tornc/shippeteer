local font = require("cc_font")
local utils = require("utils")
local vector2d = require("vector2d")
local pretty = require("cc.pretty")

--[[
    HOLOGRAM ELEMENTS MODULE
]]

local h_element = setmetatable({}, {})

--[[ CONSTANTS ]]

local EPSILON = 0.0000001

--[[ STATE VARIABLES ]]

local hologram

function h_element.set_hologram(_hologram) hologram = _hologram end

--- @class Framebuffer
function h_element.framebuffer()
    local self = setmetatable({}, {})

    function self.create(x, y, width, height, background_colour)
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.background_colour = background_colour
        self.id = hologram.CreateFrameBuffer(self.width, self.height)
        return self
    end

    function self.draw()
        hologram.BlitFrameBuffer(self.x, self.y, self.id, 0)
    end

    function self.free()
        hologram.FreeFrameBuffer(self.id)
    end

    return self
end

--- I got 'inspired' by super95shao to render using vector graphics instead of
--- bitmaps. This will help ease the pain of perspective transforming.
function h_element.line_group()
    local self = setmetatable({}, {})

    --- @param p Vector2D
    --- @return boolean
    local function is_out_of_bounds(p)
        return p.x < 0 or p.y < 0 or p.x > self.framebuffer.width or p.y > self.framebuffer.height
    end

    --- Liang-Barsky line clipping algorithm.
    --- See: https://en.wikipedia.org/wiki/Liang%E2%80%93Barsky_algorithm
    --- @param p1 Vector2D
    --- @param p2 Vector2D
    --- @return Vector2D? clipped_p1
    --- @return Vector2D? clipped_p2
    local function clip_line(p1, p2)
        local dir = p2 - p1
        local edge_param = { -dir.x, dir.x, -dir.y, dir.y }
        -- Note that you have to subtract by min_x and min_y, but it's 0 in our case.
        local bound_values = { p1.x, self.framebuffer.width - p1.x, p1.y, self.framebuffer.height - p1.y }
        local t_enter, t_exit = 0, 1
        for i = 1, 4 do
            if edge_param[i] == 0 then
                if bound_values[i] < 0 then return nil, nil end -- Parallel + outside
            else
                local t = bound_values[i] / edge_param[i]
                if edge_param[i] < 0 then
                    t_enter = math.max(t_enter, t)
                else
                    t_exit = math.min(t_exit, t)
                end
            end
        end
        if t_enter > t_exit then return nil, nil end -- Completely outside
        return p1 + dir:mul(t_enter), p1 + dir:mul(t_exit)
    end

    --- @param framebuffer Framebuffer
    --- @param points table<Vector2D>
    --- @param center_point Vector2D
    --- @param size integer
    --- @param line_width integer
    --- @param colour integer
    --- @return table
    function self.create(framebuffer, points, center_point, size, line_width, colour)
        self.framebuffer = framebuffer
        self.points = points
        self.center_point = center_point
        self.size = size
        self.line_width = line_width
        self.colour = colour
        return self
    end

    --- This assumes that the shape is well within the screen border,
    --- removing the need to perform line clipping.
    function self.draw() self.draw_at(self.center_point, true) end

    --- Draws an element with its center located at a given position.
    --- @param position Vector2D Will skip if no position is given.
    --- @param skip_clip boolean?
    function self.draw_at(position, skip_clip)
        if not position then return end
        hologram.SetCurrentFrameBuffer(self.framebuffer.id)

        -- Fuck you, floats!
        local is_closed_shape = (self.points[1] - self.points[#self.points]):length() < EPSILON
        local num_points = #self.points

        -- For every point, draw a line between 2 points.
        -- You might ask: Why the FUCK do you need so much code for that?
        -- Well... hear me out please 🙏
        -- 1-wide lines? Simple, just use a single DrawLine call.
        -- Thick lines? That's a bit trickier.
        -- 1. We are forced to use triangles (quads), because spamming DrawLine() calls to
        -- create a thick line will absolutely tank performance. These are the first pair
        -- of triangle draw calls.
        -- 2. We get gaps between segments at large angle changes. Therefore, we need to
        -- fill the space between the joints. These are the second pair of triangles.
        --
        -- I don't think this filling is the best approach; it'd probably be better to
        -- lengthen the lines so the line segments overlap automatically.
        for i = 1, num_points do
            local point = self.points[i]
            local next_point = self.points[i + 1] or (is_closed_shape and self.points[1])
            if not next_point then goto continue end
            local p1 = ((point * self.size) + position):round()
            local p2 = ((next_point * self.size) + position):round()
            if p1 == p2 then goto continue end

            if not skip_clip then p1, p2 = clip_line(p1, p2) end
            if not (p1 and p2) then goto continue end
            if is_out_of_bounds(p1) or is_out_of_bounds(p2) then goto continue end
            -- Drawing a thick line is annoying due to mitering (the reason for the 2nd set of triangle drawing).
            if self.line_width == 1 then
                hologram.DrawLine(p1.x, p1.y, p2.x, p2.y, self.colour, 0)
            else
                --- @TODO: there may be edge cases where these recalculated points are out of bounds!
                --- am I seriously going to have to perform polygon clipping T-T ???
                local dir = (p2 - p1):normalize()
                local perp = vector2d.new(-dir.y, dir.x)
                local offset = perp * (self.line_width / 2)

                -- 4 corners of the thick line
                local p1_start = (p1 - offset):round()
                local p1_end = (p1 + offset):round()
                local p2_start = (p2 - offset):round()
                local p2_end = (p2 + offset):round()

                -- Draw the thick line as a filled quad
                hologram.DrawTriangle(
                    p1_start.x, p1_start.y,
                    p2_start.x, p2_start.y,
                    p2_end.x, p2_end.y,
                    self.colour, self.colour, self.colour, 0
                )
                hologram.DrawTriangle(
                    p1_start.x, p1_start.y,
                    p2_end.x, p2_end.y,
                    p1_end.x, p1_end.y,
                    self.colour, self.colour, self.colour, 0
                )

                -- Handle the joint with the next segment
                local next_next_point = self.points[i + 2] or (is_closed_shape and self.points[2])
                if not next_next_point then goto continue end
                local p3 = ((next_next_point * self.size) + position):round()
                if p2 == p3 then goto continue end

                local dir2 = (p3 - p2):normalize()
                local perp2 = vector2d.new(-dir2.y, dir2.x)
                local offset2 = perp2 * (self.line_width / 2)

                -- Calculate the intersection point for the joint
                local joint_start = (p2 - offset):round()
                local joint_end = (p2 + offset):round()
                local joint_start2 = (p2 - offset2):round()
                local joint_end2 = (p2 + offset2):round()

                -- Fill the joint
                hologram.DrawTriangle(
                    joint_start.x, joint_start.y,
                    joint_start2.x, joint_start2.y,
                    joint_end.x, joint_end.y,
                    self.colour, self.colour, self.colour, 0
                )
                hologram.DrawTriangle(
                    joint_start2.x, joint_start2.y,
                    joint_end2.x, joint_end2.y,
                    joint_end.x, joint_end.y,
                    self.colour, self.colour, self.colour, 0
                )
            end
            ::continue::
        end
    end

    return self
end

function h_element.rectangle()
    local self = h_element.line_group()
    local super_create = self.create

    --- @param framebuffer Framebuffer
    --- @param center_point Vector2D
    --- @param aspect_ratio number Ex: 16 / 9, where width is size.
    --- @param size integer
    --- @param line_width integer
    --- @param colour integer
    --- @return table
    function self.create(framebuffer, center_point, aspect_ratio, size, line_width, colour)
        -- These are ratios!
        local half_height = 1 / aspect_ratio * 0.5 -- Ensures width is not larger than size
        local half_width = 0.5

        local points = {
            vector2d.new(-half_width, -half_height), -- Top-left
            vector2d.new(half_width, -half_height),  -- Top-right
            vector2d.new(half_width, half_height),   -- Bottom-right
            vector2d.new(-half_width, half_height),  -- Bottom-left
            vector2d.new(-half_width, -half_height), -- Closing: Top-left
        }
        super_create(framebuffer, points, center_point, size, line_width, colour)
        return self
    end

    return self
end

function h_element.diamond()
    local self = h_element.line_group()
    local super_create = self.create

    --- @param framebuffer Framebuffer
    --- @param center_point Vector2D
    --- @param aspect_ratio number Ex: 16 / 9, where width is size.
    --- @param size integer
    --- @param line_width integer
    --- @param colour integer
    --- @return table
    function self.create(framebuffer, center_point, aspect_ratio, size, line_width, colour)
        local half_height = 1 / aspect_ratio * 0.5
        local half_width = 0.5

        local points = {
            vector2d.new(0, -half_height), -- Top-middle
            vector2d.new(half_width, 0),   -- Middle-right
            vector2d.new(0, half_height),  -- Bottom-middle
            vector2d.new(-half_width, 0),  -- Middle-left
            vector2d.new(0, -half_height), -- Closing: -- Top-middle
        }
        super_create(framebuffer, points, center_point, size, line_width, colour)
        return self
    end

    return self
end

function h_element.triangle()
    local self = h_element.line_group()
    local super_create = self.create

    --- @param framebuffer Framebuffer
    --- @param center_point Vector2D
    --- @param size integer
    --- @param line_width integer
    --- @param colour integer
    --- @return table
    function self.create(framebuffer, center_point, size, line_width, colour)
        -- Note: This is an equilateral triangle
        local radius = 0.5                                        -- Again, these are ratios!
        local points = {
            vector2d.new(0, -radius),                             -- Top vertex
            vector2d.new(radius * math.sqrt(3) / 2, radius / 2),  -- Bottom-right vertex
            vector2d.new(-radius * math.sqrt(3) / 2, radius / 2), -- Bottom-left vertex
            vector2d.new(0, -radius)                              -- Closing: Top vertex
        }
        super_create(framebuffer, points, center_point, size, line_width, colour)
        return self
    end

    return self
end

function h_element.polygon()
    local self = h_element.line_group()
    local super_create = self.create

    --- @param framebuffer Framebuffer
    --- @param center_pos Vector2D
    --- @param num_sides integer
    --- @param size integer
    --- @param line_width integer
    --- @param colour integer
    --- @return table
    function self.create(framebuffer, center_pos, num_sides, size, line_width, colour)
        local radius = 0.5
        local points = {}
        for i = 0, num_sides do
            local angle = math.pi / 2 + 2 * math.pi * i / num_sides
            local x = radius * math.cos(angle)
            local y = radius * math.sin(angle)
            table.insert(points, vector2d.new(x, y))
        end
        super_create(framebuffer, points, center_pos, size, line_width, colour)
        return self
    end

    return self
end

function h_element.circle()
    local self = h_element.polygon()
    local super_create = self.create

    --- @param center_pos Vector2D
    --- @param size integer
    --- @param line_width integer
    --- @param colour integer
    --- @return table
    function self.create(center_pos, size, line_width, colour)
        --- Yup, it's literally a polygon in disguise. 16 is a bit low fidelity, but who cares.
        super_create(center_pos, 16, size, line_width, colour)
        return self
    end

    return self
end

function h_element.curved_line()
    local self = h_element.line_group()
    local super_create = self.create

    --- @param framebuffer Framebuffer
    --- @param center_point Vector2D
    --- @param curviness number [-1, 1] When horizontal, 1 curves down. For vertical, it curves right.
    --- @param horizontal boolean
    --- @param size integer
    --- @param line_width integer
    --- @param colour integer
    --- @return table
    function self.create(framebuffer, center_point, curviness, horizontal, size, line_width, colour)
        -- Either from left to right or top to bottom
        local start_point = vector2d.new(horizontal and -0.5 or 0, horizontal and 0 or -0.5)
        local end_point = vector2d.new(horizontal and 0.5 or 0, horizontal and 0 or 0.5)
        local control_point = vector2d.new(horizontal and 0 or curviness, horizontal and curviness or 0)

        -- Quadratic Bézier curve
        local points = {}
        local num_points = 8
        for i = 0, num_points do
            local t = i / num_points
            local x = (1 - t) * (1 - t) * start_point.x + 2 * (1 - t) * t * control_point.x + t * t * end_point.x
            local y = (1 - t) * (1 - t) * start_point.y + 2 * (1 - t) * t * control_point.y + t * t * end_point.y
            table.insert(points, vector2d.new(x, y))
        end

        super_create(framebuffer, points, center_point, size, line_width, colour)
        return self
    end

    return self
end

--- @TODO: I need dotted lines!

--- Converts a binary bitmap into a bitmap by replacing 1s with a specified colour and 0s with a background colour.
--- @param binary_bitmap table
--- @param colour integer The colour to use for pixels where the binary value is 1.
--- @param bg_colour integer The colour to use for pixels where the binary value is 0.
--- @return table bitmap A table representing the bitmap with applied colours.
local function bake_bitmap(binary_bitmap, colour, bg_colour)
    local bitmap = {}
    for i = 1, #binary_bitmap do bitmap[i] = binary_bitmap[i] == 1 and colour or bg_colour end
    return bitmap
end

--- Scales a bitmap to a new size using nearest-neighbor interpolation.
--- @param bitmap table The original bitmap to scale.
--- @param original_width integer The width of the original bitmap.
--- @param original_height integer The height of the original bitmap.
--- @param scale integer The scaling factor to apply (e.g., 2 for doubling the size). Expect it's not a 0 or 1.
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

function h_element.static_text()
    local self = setmetatable({}, {})

    --- @param framebuffer Framebuffer
    --- @param position Vector2D
    --- @param text string
    --- @param colour integer
    --- @param scale integer
    --- @return table
    function self.create(framebuffer, position, text, colour, scale)
        self.framebuffer = framebuffer
        self.position = position
        self.text = text
        self.colour = colour
        self.scale = (scale and scale > 1) and scale or 1
        self.bitmap, self.bitmap_width, self.bitmap_height = self.calculate_bitmap()
        return self
    end

    --- Note: Please avoid recalculating needlessly.
    --- @return table baked_bitmap 1D array. Keep in mind: this is a baked bitmap!
    --- @return integer width in pixels
    --- @return integer height in pixels
    function self.calculate_bitmap()
        local char_width, char_height = font.char_width, font.char_height
        local lines = {}
        -- Replaces tabs with 4 spaces
        for line in (self.text .. "\n"):gmatch("(.-)\n") do table.insert(lines, #line:gsub("\t", string.rep(" ", 4))) end
        local bitmap_width = math.max(table.unpack(lines)) * char_width
        local bitmap_height = #lines * char_height

        -- Merge the individual bitmaps into 1 big 1D array.
        local bitmap = {}
        for i = 1, bitmap_width * bitmap_height do bitmap[i] = 0 end --- @LATER: Is this really required?
        local cur_x, cur_y = 0, 0
        for i = 1, #self.text do
            local char = self.text:sub(i, i)
            if char:match("[\n\t ]") then
                -- Unreadable dogshit in the name of one-liners.
                cur_x = char == "\n" and 0 or cur_x + font.char_width * self.scale * (char == "\t" and 4 or 1)
                cur_y = char == "\n" and cur_y + font.char_width * self.scale or cur_y
            else
                local char_key = string.format("%02X", string.byte(char)) -- Convert character to hex key
                local char_bitmap = font.bitmap[char_key]
                assert(char_bitmap, "Character not found in font: " .. char_key)
                --- @TODO: verify
                for y = 0, char_height - 1 do
                    for x = 0, char_width - 1 do
                        local src_idx = y * char_width + x + 1
                        local dst_idx = (cur_y + y) * bitmap_width + (cur_x + x) + 1
                        bitmap[dst_idx] = char_bitmap[src_idx]
                    end
                end
                cur_x = cur_x + char_width
            end
        end

        if self.scale > 1 then
            bitmap, bitmap_width, bitmap_height = scale_bitmap(
                bitmap, bitmap_width, bitmap_height, self.scale
            )
        end

        return bake_bitmap(bitmap, self.colour, self.framebuffer.background_colour), bitmap_width, bitmap_height
    end

    function self.draw() self.draw_at(self.position) end

    function self.draw_at(position)
        if not position then return end
        hologram.SetCurrentFrameBuffer(self.framebuffer.id)
        hologram.Blit(position.x, position.y, self.bitmap_width, self.bitmap_height, self.bitmap, 0)
    end

    return self
end

function h_element.dynamic_text()
    local self = h_element.static_text()
    local super_create = self.create

    --- @param framebuffer Framebuffer
    --- @param position Vector2D
    --- @param variable_ref function
    --- @param colour integer
    --- @param scale integer
    function self.create(framebuffer, position, variable_ref, colour, scale)
        self.variable_ref = variable_ref
        super_create(framebuffer, position, tostring(self.variable_ref()), colour, scale)
    end

    function self.update()
        local new_text = tostring(self.variable_ref())
        if self.text ~= new_text then
            self.text = new_text
            self.bitmap, self.bitmap_width, self.bitmap_height = self.calculate_bitmap()
        end
    end

    return self
end

return h_element
