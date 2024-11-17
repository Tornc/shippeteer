-- Written by Ton, with love. Feel free to modify, consider this under the MIT license.

--[[
    UTILITY MODULE

    Honestly, some of these should have been included in base Lua, smh.
]]

local utils = setmetatable({}, {})

--- Centers a string within a given width by padding it with spaces.
--- @param string string The string to be centered.
--- @param width integer The total width to center the string within.
--- @return string padded_string The centered string with padding.
function utils.center_string(string, width)
    local padding = width - #string
    local left_pad = math.floor(padding / 2)
    local right_pad = padding - left_pad
    return string.rep(" ", left_pad) .. string .. string.rep(" ", right_pad)
end

--- Clamps a number within a specified range.
--- @param value number The number to clamp.
--- @param min number The minimum allowed value.
--- @param max number The maximum allowed value.
--- @return number result The clamped number within the specified range.
function utils.clamp(value, min, max)
    return math.min(max, math.max(min, value))
end

--- Checks if a table contains a specific value.
--- @param table table The table to search within.
--- @param value any The value to search for.
--- @return boolean `true` if the value is found, otherwise `false`.
function utils.contains(table, value)
    for _, v in pairs(table) do
        if v == value then return true end
    end
    return false
end

--- The current time in seconds with 3 digits of precision.
--- @return number time Time since 1 January 1970 in the UTC timezone.
function utils.current_time_seconds()
    return os.epoch("utc") * 0.001
end

--- If `variable` is not a table, wrap it in {...}. May come in handy when iterating over things.
--- @param variable any
--- @return table
function utils.ensure_is_table(variable)
    return type(variable) == "table" and variable or { variable }
end

--- Formats a time duration in seconds to a readable format.
--- @param seconds number The duration in seconds.
--- @return string time_string A formatted string representing the time in seconds (s), minutes (m), or hours (h).
function utils.format_time(seconds)
    if seconds < 1000 then
        return string.format("%ds", seconds)
    elseif seconds < 60000 then
        local minutes = math.floor(seconds / 60)
        return string.format("%dm", minutes)
    else
        local hours = math.floor(seconds / 3600)
        return string.format("%dh", hours)
    end
end

--- Finds the index of a specified value in a table.
--- @param table table The table to search within.
--- @param value any The value to find.
--- @return any result  The index of the value if found, or `nil` if not found.
function utils.index_of(table, value)
    for i, v in ipairs(table) do
        if v == value then return i end
    end
    return nil
end

--- Get the length of a dict
--- @param dict table
--- @return integer
function utils.len_d(dict)
    local count = 0
    for _ in pairs(dict) do count = count + 1 end
    return count
end

--- Rounds a number to the nearest integer or to a specified decimal place.
--- @param num number The number to round.
--- @param decimal number? The number of decimal places to round to. If omitted, rounds to the nearest integer.
--- @return integer|number result The rounded number.
function utils.round(num, decimal)
    local mult = 10 ^ (decimal or 0)
    return math.floor(num * mult + 0.5) / mult
end

--- Rounds a number to the nearest increment.
--- @param number number The number to round.
--- @param increment number The increment to round to.
--- @return number result The rounded number to the nearest specified increment.
function utils.round_increment(number, increment)
    return utils.round(number * (1 / increment)) / (1 / increment)
end

--- Runs a function asynchronously using coroutines.
--- @param func function The function to run asynchronously.
--- @param ... any Arguments of the function.
function utils.run_async(func, ...)
    local args = { ... }
    local co = coroutine.create(
        function()
            func(unpack(args))
        end
    )
    coroutine.resume(co)
end

--- Converts a table to a vector. Assumes table has keys or values representing `x`, `y`, and `z`.
--- @param table table The table containing x, y, z values (either as keys or as an indexed array).
--- @return table vector A vector constructed with x, y, and z components.
function utils.tbl_to_vec(table)
    return vector.new(
        table.x or table[1],
        table.y or table[2],
        table.z or table[3]
    )
end

return utils
