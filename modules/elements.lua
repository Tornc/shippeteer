local utils = require("utils")
local vector2d = require("vector2d")
local pretty = require("cc.pretty")

--[[
    MODULE
]]

local elements = setmetatable({}, {})

--[[ STATE VARIABLES ]]

local SCREEN_WIDTH
local SCREEN_HEIGHT

function elements.set_screen_width(width) SCREEN_WIDTH = width end

function elements.set_screen_height(height) SCREEN_HEIGHT = height end

--- I got 'inspired' by super95shao to render using vector graphics instead of
--- bitmaps (except for fonts). This will help ease the pain of perspective transforming.
function elements.element()
    local self = setmetatable({}, {})

    --- @param p Vector2D
    --- @return boolean
    local function is_out_of_bounds(p)
        return p.x < 0 or p.y < 0 or p.x > SCREEN_WIDTH or p.y > SCREEN_HEIGHT
    end

    --- @param points table<Vector2D>
    --- @param center_point Vector2D
    --- @param size integer
    --- @param line_width integer
    --- @param colour integer
    --- @return table
    function self.create(points, center_point, size, line_width, colour)
        self.points = points
        self.center_point = center_point
        self.size = size
        self.line_width = line_width
        self.colour = colour
        return self
    end

    --- @TODO: fix the corners between segments for thick lines!
    function self.draw(screen)
        for i, point in ipairs(self.points) do
            local next_point = self.points[i + 1]
            if next_point then
                local p1 = (point * self.size) + self.center_point
                local p2 = (next_point * self.size) + self.center_point

                local is_p1_outside, is_p2_outside = is_out_of_bounds(p1), is_out_of_bounds(p2)
                if is_p1_outside and is_p2_outside then goto continue end
                if is_p1_outside then
                    p1.x = utils.clamp(p1.x, 0, SCREEN_WIDTH)
                    p1.y = utils.clamp(p1.y, 0, SCREEN_HEIGHT)
                end
                if is_p2_outside then
                    p2.x = utils.clamp(p2.x, 0, SCREEN_WIDTH)
                    p2.y = utils.clamp(p2.y, 0, SCREEN_HEIGHT)
                end

                if self.line_width == 1 then
                    screen.DrawLine(
                        utils.round(p1.x), utils.round(p1.y),
                        utils.round(p2.x), utils.round(p2.y),
                        self.colour, 0
                    )
                else
                    local dir = (p2 - p1):normalize()
                    local perp = vector2d.new(-dir.y, dir.x)
                    local offset = perp * (self.line_width / 2)

                    -- 4 corners of the thick line
                    local p1_start = p1 - offset
                    local p1_end = p1 + offset
                    local p2_start = p2 - offset
                    local p2_end = p2 + offset

                    -- Draw the thick line as a filled quad
                    screen.DrawTriangle(
                        utils.round(p1_start.x), utils.round(p1_start.y),
                        utils.round(p2_start.x), utils.round(p2_start.y),
                        utils.round(p2_end.x), utils.round(p2_end.y),
                        self.colour, self.colour, self.colour, 0
                    )
                    screen.DrawTriangle(
                        utils.round(p1_start.x), utils.round(p1_start.y),
                        utils.round(p2_end.x), utils.round(p2_end.y),
                        utils.round(p1_end.x), utils.round(p1_end.y),
                        self.colour, self.colour, self.colour, 0
                    )
                end
            end
            ::continue::
        end
    end

    return self
end

function elements.rectangle()
    local self = elements.element()
    local super_create = self.create

    --- @param center_point Vector2D
    --- @param aspect_ratio number Ex: 16 / 9, where width is size.
    --- @param size integer
    --- @param line_width integer
    --- @param colour integer
    --- @return table
    function self.create(center_point, aspect_ratio, size, line_width, colour)
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
        super_create(points, center_point, size, line_width, colour)
        return self
    end

    return self
end

function elements.triangle()
    local self = elements.element()
    local super_create = self.create

    --- @param center_point Vector2D
    --- @param size integer
    --- @param line_width integer
    --- @param colour integer
    --- @return table
    function self.create(center_point, size, line_width, colour)
        -- Note: This is an equilateral triangle
        local radius = 0.5                                        -- Again, these are ratios!
        local points = {
            vector2d.new(0, -radius),                             -- Top vertex
            vector2d.new(radius * math.sqrt(3) / 2, radius / 2),  -- Bottom-right vertex
            vector2d.new(-radius * math.sqrt(3) / 2, radius / 2), -- Bottom-left vertex
            vector2d.new(0, -radius)                              -- Closing: Top vertex
        }
        super_create(points, center_point, size, line_width, colour)
        return self
    end

    return self
end

function elements.polygon()
    local self = elements.element()
    local super_create = self.create

    --- @param center_pos Vector2D
    --- @param num_sides integer
    --- @param size integer
    --- @param line_width integer
    --- @param colour integer
    --- @return table
    function self.create(center_pos, num_sides, size, line_width, colour)
        local radius = 0.5
        local points = {}
        for i = 0, num_sides do
            local angle = math.pi / 2 + 2 * math.pi * i / num_sides
            local x = radius * math.cos(angle)
            local y = radius * math.sin(angle)
            table.insert(points, vector2d.new(x, y))
        end
        super_create(points, center_pos, size, line_width, colour)
        return self
    end

    return self
end

function elements.circle()
    local self = elements.polygon()
    local super_create = self.create

    --- @param center_pos Vector2D
    --- @param size integer
    --- @param line_width integer
    --- @param colour integer
    --- @return table
    function self.create(center_pos, size, line_width, colour)
        --- Yup, it's literally a polygon in disguise.
        super_create(center_pos, 16, size, line_width, colour)
        return self
    end

    return self
end

function elements.curved_line()
    local self = elements.element()
    local super_create = self.create

    --- @param center_point Vector2D
    --- @param curviness number [-1, 1] When horizontal, 1 curves down. For vertical, it curves right.
    --- @param horizontal boolean
    --- @param size integer
    --- @param line_width integer
    --- @param colour integer
    --- @return table
    function self.create(center_point, curviness, horizontal, size, line_width, colour)
        -- Either from left to right or top to bottom
        local start_point = vector2d.new(horizontal and -0.5 or 0, horizontal and 0 or -0.5)
        local end_point = vector2d.new(horizontal and 0.5 or 0, horizontal and 0 or 0.5)
        local control_point = vector2d.new(horizontal and 0 or curviness, horizontal and curviness or 0)

        -- Quadratic Bézier curve
        local points = {}
        local num_points = 16
        for i = 0, num_points do
            local t = i / num_points
            local x = (1 - t) * (1 - t) * start_point.x + 2 * (1 - t) * t * control_point.x + t * t * end_point.x
            local y = (1 - t) * (1 - t) * start_point.y + 2 * (1 - t) * t * control_point.y + t * t * end_point.y
            table.insert(points, vector2d.new(x, y))
        end

        super_create(points, center_point, size, line_width, colour)
        return self
    end

    return self
end

return elements
