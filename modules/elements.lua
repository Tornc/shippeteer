local utils = require("utils")
local vector2d = require("vector2d")

--[[
    MODULE
]]

local elements = setmetatable({}, {})

--- We can assume it's a shape if the beginning and endpoint meet.
--- @param vectors Vector2D
--- @return boolean
local function shape_check(vectors)
    local total_vec = vector2d.new(0, 0)
    for _, vec in pairs(vectors) do
        total_vec = total_vec + vec
    end
    return total_vec:length() < 0.01 -- Some tolerance due to float shenanigans
end

function elements.vector_shape()
    local self = setmetatable({}, {})

    function self.create(vectors, center_pos, size, colour)
        -- assert(shape_check(vectors), "That's not a shape!")
        self.vectors = vectors
        self.center_pos = center_pos
        self.size = size
        self.colour = colour
        return self
    end

    function self.draw(screen)
        local cur_x = self.center_pos.x - math.floor(self.size / 2)
        local cur_y = self.center_pos.y - math.floor(self.size / 2)
        for _, cur_vec in pairs(self.vectors) do
            cur_vec = cur_vec * self.size
            local new_x, new_y = cur_x + cur_vec.x, cur_y + cur_vec.y
            screen.DrawLine(
                cur_x, cur_y,
                new_x, new_y,
                self.colour, 0
            )
            cur_x, cur_y = new_x, new_y
        end
    end

    return self
end

function elements.rectangle()
    local self = elements.vector_shape()
    local super_create = self.create

    function self.create(center_pos, aspect_ratio, size, colour)
        local height = size / aspect_ratio -- Ensures width is not larger than size
        local width = size

        local vectors = {
            vector2d.new(width, 0),
            vector2d.new(0, height),
            vector2d.new(-width, 0),
            vector2d.new(0, -height),
        }
        super_create(vectors, center_pos, size, colour)
        return self
    end

    return self
end

function elements.triangle()
end

function elements.polygon()
end

function elements.circle()
end

-- Note: this is something you can define by giving a bunch
-- of vectors. You could make a house-shape or plane-shape, etc.
function elements.custom_shape()
end

return elements
