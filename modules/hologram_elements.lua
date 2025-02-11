local utils = require("utils")
local vector2d = require("vector2d")
local pretty = require("cc.pretty")

--[[
    MODULE
]]

local elements = setmetatable({}, {})

--[[ STATE VARIABLES ]]

local SCREEN
local SCREEN_WIDTH
local SCREEN_HEIGHT

function elements.set_screen(screen) SCREEN = screen end

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

    function self.draw()
        -- Fuck you, floats!
        local is_closed_shape = (self.points[1] - self.points[#self.points]):length() < 0.0001
        local num_points = #self.points

        for i = 1, num_points do
            local point = self.points[i]
            local next_point = self.points[i + 1] or (is_closed_shape and self.points[1])
            if not next_point then goto continue end
            local p1 = ((point * self.size) + self.center_point):round()
            local p2 = ((next_point * self.size) + self.center_point):round()
            if p1 == p2 then goto continue end

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
                SCREEN.DrawLine(
                    p1.x, p1.y,
                    p2.x, p2.y,
                    self.colour, 0
                )
            else
                local dir = (p2 - p1):normalize()
                local perp = vector2d.new(-dir.y, dir.x)
                local offset = perp * (self.line_width / 2)

                -- 4 corners of the thick line
                local p1_start = (p1 - offset):round()
                local p1_end = (p1 + offset):round()
                local p2_start = (p2 - offset):round()
                local p2_end = (p2 + offset):round()

                -- Draw the thick line as a filled quad
                SCREEN.DrawTriangle(
                    p1_start.x, p1_start.y,
                    p2_start.x, p2_start.y,
                    p2_end.x, p2_end.y,
                    self.colour, self.colour, self.colour, 0
                )
                SCREEN.DrawTriangle(
                    p1_start.x, p1_start.y,
                    p2_end.x, p2_end.y,
                    p1_end.x, p1_end.y,
                    self.colour, self.colour, self.colour, 0
                )

                -- Handle the joint with the next segment
                local next_next_point = self.points[i + 2] or (is_closed_shape and self.points[2])
                if not next_next_point then goto continue end
                local p3 = ((next_next_point * self.size) + self.center_point):round()
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
                SCREEN.DrawTriangle(
                    joint_start.x, joint_start.y,
                    joint_start2.x, joint_start2.y,
                    joint_end.x, joint_end.y,
                    self.colour, self.colour, self.colour, 0
                )
                SCREEN.DrawTriangle(
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

function elements.diamond()
    local self = elements.element()
    local super_create = self.create

    --- @param center_point Vector2D
    --- @param aspect_ratio number Ex: 16 / 9, where width is size.
    --- @param size integer
    --- @param line_width integer
    --- @param colour integer
    --- @return table
    function self.create(center_point, aspect_ratio, size, line_width, colour)
        local half_height = 1 / aspect_ratio * 0.5
        local half_width = 0.5

        local points = {
            vector2d.new(0, -half_height), -- Top-middle
            vector2d.new(half_width, 0),   -- Middle-right
            vector2d.new(0, half_height),  -- Bottom-middle
            vector2d.new(-half_width, 0),  -- Middle-left
            vector2d.new(0, -half_height), -- Closing: -- Top-middle
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
