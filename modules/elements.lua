local utils = require("utils")
local vector2d = require("vector2d")

--[[
    MODULE
]]

local elements = setmetatable({}, {})

local function shape_check(vectors)
    local sum_vec = vector2d.new(0, 0)
    for _, vec in pairs(vectors) do
        
    end
end

--- @TODO: include an assert that ensures that a shape is a full outline
--- (i.e. first and last point meet eachother)
function elements.vector_shape()
    local self = setmetatable({}, {})

    function self.create(vectors, center_pos, scale, colour)
        self.vectors = vectors
        self.center_pos = center_pos
        self.scale = scale
        self.colour = colour
        return self
    end

    function self.draw(screen)
        local cur_x = self.center_pos.x - math.floor(self.scale / 2)
        local cur_y = self.center_pos.y - math.floor(self.scale / 2)
        for _, cur_vec in pairs(self.vectors) do
            cur_vec = cur_vec * self.scale
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

    function self.create(center_pos, aspect_ratio, scale, colour)
        local height = utils.round(1 * scale)
        local width = utils.round(aspect_ratio * height)

        local vectors = {
            vector2d.new(width, 0),
            vector2d.new(0, height),
            vector2d.new(-width, 0),
            vector2d.new(0, -height)
        }
        super_create(vectors, center_pos, scale, colour)
        return self
    end

    return self
end

function elements.triangle()
end

function elements.circle()
end

function elements.polygon()
end

-- Note: this is something you can define by giving a bunch
-- of vectors. You could make a house-shape or plane-shape, etc.
function elements.custom_shape()
end

return elements
