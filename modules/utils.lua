-- Written by Ton, with love. Feel free to modify, consider this under the MIT license.

local pretty = require("cc.pretty")

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

--- Compare the values of n tables and check if they're the same.
--- @param ... table Tables you want to compare.
--- @return boolean
function utils.compare_tables(...)
    local function is_equal(table_1, table_2)
        if type(table_1) ~= "table" or type(table_2) ~= "table" then
            return table_1 == table_2
        end

        local keys1, keys2 = 0, 0
        for _ in pairs(table_1) do keys1 = keys1 + 1 end
        for _ in pairs(table_2) do keys2 = keys2 + 1 end
        if keys1 ~= keys2 then return false end

        for k, v1 in pairs(table_1) do
            local v2 = table_2[k]
            if not is_equal(v1, v2) then
                return false
            end
        end

        return true
    end

    local tables = { ... }
    local count = #tables
    if count < 2 then return true end
    for i = 1, count - 1 do
        if not is_equal(tables[i], tables[i + 1]) then return false end
    end
    return true
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

--- Get the number of keys of a dict.
--- @param dict table
--- @return integer
function utils.count_keys(dict)
    local count = 0
    for _ in pairs(dict) do count = count + 1 end
    return count
end

--- The current time in seconds with 3 digits of precision.
--- @return number time Time since 1 January 1970 in the UTC timezone.
function utils.time_seconds()
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

--- Merge 2 or more tables together. Basically `table.insert()`, but in bulk.
--- @param ... table Tables you want to merge.
--- @return table merged_tables
function utils.merge_tables(...)
    local tables = { ... }
    local first_table = table.remove(tables, 1)
    for _, tbl in pairs(tables) do
        for _, elem in pairs(tbl) do
            table.insert(first_table, elem)
        end
    end
    return first_table
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

--- Round a bunch of numbers to a whole number.
--- @param ... number of numbers.
function utils.round_nrs(...)
    local args = { ... }
    for i = 1, #args do args[i] = utils.round(args[i]) end
    return table.unpack(args)
end

--- Runs a function asynchronously using coroutines.
--- <br> <sub> Fuck you, Create peripherals!!! </sub>
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

--- Drops an axis. Maybe the CC:Tweaked's vector implementation will get updated in the future, but
--- at the time of writing, setting an axis as nil upon creation, means it becomes 0.
--- @param vec table Vector
--- @param axis string `x`, `y`, `z`
--- @return table vector A vector of which at least one of its axes is 0.
function utils.vec_drop_axis(vec, axis)
    vec[axis] = nil
    return vector.new(vec.x, vec.y, vec.z)
end

return utils
