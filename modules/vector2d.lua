--[[
    It is literally the Vector API but the Z axis has been gouged out.
]]

local vector2d = {}

local getmetatable = getmetatable
local expect = dofile("rom/modules/main/cc/expect.lua").expect

local vmetatable

--- A 2-dimensional vector, with `x` and `y` values.
---
--- This is suitable for representing both position and directional vectors in a 2D plane.
---
--- @class Vector2D
vector2d = {
    --- Adds two vectors together.
    ---
    --- @param self Vector2D The first vector to add.
    --- @param o Vector2D The second vector to add.
    --- @return Vector2D result The resulting vector
    --- @usage v1:add(v2)
    --- @usage v1 + v2
    add = function(self, o)
        if getmetatable(self) ~= vmetatable then expect(1, self, "vector2d") end
        if getmetatable(o) ~= vmetatable then expect(2, o, "vector2d") end

        return vector2d.new(
            self.x + o.x,
            self.y + o.y
        )
    end,

    --- Subtracts one vector from another.
    ---
    --- @param self Vector2D The vector to subtract from.
    --- @param o Vector2D The vector to subtract.
    --- @return Vector2D result The resulting vector
    --- @usage v1:sub(v2)
    --- @usage v1 - v2
    sub = function(self, o)
        if getmetatable(self) ~= vmetatable then expect(1, self, "vector2d") end
        if getmetatable(o) ~= vmetatable then expect(2, o, "vector2d") end

        return vector2d.new(
            self.x - o.x,
            self.y - o.y
        )
    end,

    --- Multiplies a vector by a scalar value.
    ---
    --- @param self Vector2D The vector to multiply.
    --- @param factor number The scalar value to multiply with.
    --- @return Vector2D result A vector with value `(x * m, y * m)`.
    --- @usage vector2d.new(1, 2):mul(3)
    --- @usage vector2d.new(1, 2) * 3
    mul = function(self, factor)
        if getmetatable(self) ~= vmetatable then expect(1, self, "vector2d") end
        expect(2, factor, "number")

        return vector2d.new(
            self.x * factor,
            self.y * factor
        )
    end,

    --- Divides a vector by a scalar value.
    ---
    --- @param self Vector2D The vector to divide.
    --- @param factor number The scalar value to divide by.
    --- @return Vector2D result A vector with value `(x / m, y / m)`.
    --- @usage vector2d.new(1, 2):div(3)
    --- @usage vector2d.new(1, 2) / 3
    div = function(self, factor)
        if getmetatable(self) ~= vmetatable then expect(1, self, "vector2d") end
        expect(2, factor, "number")

        return vector2d.new(
            self.x / factor,
            self.y / factor
        )
    end,

    --- Negate a vector
    ---
    --- @param self Vector2D The vector to negate.
    --- @return Vector2D result The negated vector.
    --- @usage -vector2d.new(1, 2)
    unm = function(self)
        if getmetatable(self) ~= vmetatable then expect(1, self, "vector2d") end
        return vector2d.new(
            -self.x,
            -self.y
        )
    end,

    --- Compute the dot product of two vectors
    ---
    --- @param self Vector2D The first vector to compute the dot product of.
    --- @param o Vector2D The second vector to compute the dot product of.
    --- @return number result The dot product of `self` and `o`.
    --- @usage v1:dot(v2)
    dot = function(self, o)
        if getmetatable(self) ~= vmetatable then expect(1, self, "vector2d") end
        if getmetatable(o) ~= vmetatable then expect(2, o, "vector2d") end

        return self.x * o.x + self.y * o.y
    end,

    --- Get the length (also referred to as magnitude) of this vector.
    --- @param self Vector2D This vector.
    --- @return number length The length of this vector.
    length = function(self)
        if getmetatable(self) ~= vmetatable then expect(1, self, "vector2d") end
        return math.sqrt(self.x * self.x + self.y * self.y)
    end,

    --- Divide this vector by its length, producing with the same direction, but
    --- of length 1.
    ---
    --- @param self Vector2D The vector to normalise
    --- @return Vector2D result The normalised vector
    --- @usage v:normalize()
    normalize = function(self)
        return self:mul(1 / self:length())
    end,

    --- Construct a vector with each dimension rounded to the nearest value.
    ---
    --- @param self Vector2D The vector to round
    --- @param tolerance number? The tolerance that we should round to,
    --- defaulting to 1. For instance, a tolerance of 0.5 will round to the
    --- nearest 0.5.
    --- @return Vector2D result The rounded vector.
    round = function(self, tolerance)
        if getmetatable(self) ~= vmetatable then expect(1, self, "vector2d") end
        expect(2, tolerance, "number", "nil")

        tolerance = tolerance or 1.0
        return vector2d.new(
            math.floor((self.x + tolerance * 0.5) / tolerance) * tolerance,
            math.floor((self.y + tolerance * 0.5) / tolerance) * tolerance
        )
    end,

    --- Convert this vector into a string, for pretty printing.
    ---
    --- @param  self Vector2D This vector.
    --- @return string result This vector's string representation.
    --- @usage v:tostring()
    --- @usage tostring(v)
    tostring = function(self)
        if getmetatable(self) ~= vmetatable then expect(1, self, "vector2d") end

        return self.x .. "," .. self.y
    end,

    --- Check for equality between two vectors.
    ---
    --- @param self Vector2D The first vector to compare.
    --- @param other Vector2D The second vector to compare to.
    --- @return boolean result Whether or not the vectors are equal.
    equals = function(self, other)
        if getmetatable(self) ~= vmetatable then expect(1, self, "vector2d") end
        if getmetatable(other) ~= vmetatable then expect(2, other, "vector2d") end

        return self.x == other.x and self.y == other.y
    end,
}

vmetatable = {
    __name = "vector2d",
    __index = vector2d,
    __add = vector2d.add,
    __sub = vector2d.sub,
    __mul = vector2d.mul,
    __div = vector2d.div,
    __unm = vector2d.unm,
    __tostring = vector2d.tostring,
    __eq = vector2d.equals,
}

--- Construct a new [`Vector2D`] with the given coordinates.
---
--- @param x number The X coordinate or direction of the vector.
--- @param y number The Y coordinate or direction of the vector.
--- @return Vector2D The constructed vector.
function vector2d.new(x, y)
    return setmetatable({
        x = tonumber(x) or 0,
        y = tonumber(y) or 0,
    }, vmetatable)
end

return vector2d
