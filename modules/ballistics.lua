-- Written by Ton, with love. Feel free to modify, consider this under the MIT license.

--[[
    BALLISTICS MODULE
]]

---@diagnostic disable: param-type-mismatch

local ballistics = setmetatable({}, {})

--- Ensures that 0 < (1 - (distance - muzzle_x) / (100 * Vx)) < 1
--- This is a conservative rough upper bound due to the assumptions.
--- @param cannon_length integer
--- @param initial_velocity_ms integer
--- @return integer estimated_max_range
function ballistics.estimate_max_range(cannon_length, initial_velocity_ms)
    local initial_velocity = initial_velocity_ms / 20

    local estimated_max_range = 0
    local upperbound = 100000 -- Arbitrary

    while estimated_max_range < upperbound do
        local tried_distance = math.floor((estimated_max_range + upperbound) / 2)

        if (tried_distance - cannon_length) / (100 * initial_velocity) >= 1 then
            upperbound = tried_distance - 1
        else
            estimated_max_range = tried_distance + 1
        end
    end

    return estimated_max_range
end

--- All calculations come from Endal's ballistics calculator made in Desmos (https://www.desmos.com/calculator/az4angyumw),
--- there may be bugs because the formulas sure look like some kind of alien language to me. It's >60x faster than
--- brute-forcing pitch, and has higher precision to boot.
--- @param distance number
--- @param velocity_ms integer Big cannon: number of charges * 40. Medium cannon: 60 + 20 * barrel length (including recoil barrel).
--- @param target_height number Target heigh _relative_ to cannon
--- @param cannon_length integer From shaft to muzzle (inclusive)
--- @param t0 integer Minimum projectile flight time in ticks
--- @param tn integer Maximum projectile flight time in ticks
--- @param low boolean Low or high trajectory
--- @param is_med_cannon boolean
--- @return integer? t Projectile flight time in ticks
--- @return number? pitch Required cannon pitch
function ballistics.calculate_pitch(distance, velocity_ms, target_height, cannon_length, t0, tn, low, is_med_cannon)
    local start_step_size = 18.75

    -- Constants
    local g = is_med_cannon and 0.04 or 0.05 -- CBC gravity
    local c_d = 0.99                         -- drag coefficient

    -- Inputs
    local X_R = distance
    local v_m = velocity_ms
    local h = target_height
    local L = cannon_length

    local u = v_m / 20 -- Convert to velocity per tick

    -- Higher order parameters
    local A = g * c_d / (u * (1 - c_d))
    local B = function(t) return t * (g * c_d / (1 - c_d)) * 1 / X_R end
    local C = L / (u * X_R) * (g * c_d / (1 - c_d)) + h / X_R

    -- The idea is to start with very large steps and decrease step size
    -- the closer we get to the actual value.
    local num_halvings = 10           -- This is fine, too many halvings will slow down
    local acceptable_threshold = 0.01 -- How close to X_R is good enough

    local function a_R(t)
        -- "watch out for the square root" -Endal
        local B_t = B(t)
        local in_root = -(A ^ 2) + B_t ^ 2 + C ^ 2 + 2 * B_t * C + 1
        if in_root < 0 then return nil end

        local num_a_R = math.sqrt(in_root) - 1
        local den_a_R = A + B_t + C
        return 2 * math.atan(num_a_R / den_a_R)
    end

    -- t = time projectile, either start from t0 and increment or tn and decrement
    local t = low and t0 or tn
    local increasing_t = low
    local step_size = start_step_size

    local a_R1 -- scope reasons, since we need to return it

    for _ = 1, num_halvings do
        while true do
            -- It's taking too long, give up
            if (low and t >= tn) or (not low and t <= t0) then return nil, nil end

            -- Angle of projectile at t
            a_R1 = a_R(t)
            -- a square root being negative means something
            -- has gone wrong, so give up
            if not a_R1 then return nil, nil end

            -- Distance of projectile at t
            local p1_X_R1 = u * math.cos(a_R1) / math.log(c_d)
            local p2_X_R1 = c_d ^ t - 1
            local p3_X_R1 = L * math.cos(a_R1)
            local X_R1 = p1_X_R1 * p2_X_R1 + p3_X_R1

            -- Good enough, let's call it quits
            if math.abs(X_R1 - X_R) <= acceptable_threshold then
                break
            end

            -- We've passed the target (aka we're close), now oscillate around the actual
            -- target value until it's 'good enough' or it's taking too long.
            if (increasing_t and X_R1 > X_R) or (not increasing_t and X_R1 < X_R) then
                increasing_t = not increasing_t
                break
            end

            t = t + (increasing_t == low and step_size or -step_size)
        end

        -- Increase the precision after breaking out, since we're closer to target
        step_size = step_size / 2
    end

    return t, math.deg(a_R1)
end

--- Precalculates the pitch for all distances.
--- @param max_distance number
--- @param velocity_ms integer
--- @param target_height number
--- @param cannon_length integer
--- @param t0 integer
--- @param tn integer
--- @param low boolean
--- @param is_med_cannon boolean
--- @return table range_table Format: { {distance1, pitch1}, ...}
function ballistics.calculate_range_table(
    max_distance, velocity_ms, target_height, cannon_length, t0, tn, low, is_med_cannon
)
    local distances_and_pitches = {}

    local t_low = t0
    local t_high = tn

    for d = 1, max_distance do
        local pitch
        local new_t

        new_t, pitch = ballistics.calculate_pitch(
            d,
            velocity_ms,
            target_height,
            cannon_length,
            t_low,
            t_high,
            low,
            is_med_cannon
        )

        if low then
            t_low = new_t ~= nil and new_t or t_low
        else
            t_high = new_t ~= nil and new_t or t_high
        end

        table.insert(distances_and_pitches, pitch)

        sleep() -- Yield, since this process can take very long.
    end

    return distances_and_pitches
end

function ballistics.export_range_table(filepath, distances_and_pitches)
    local file = fs.open(filepath, "w")
    -- Distance is added for ease of reading
    for d, p in ipairs(distances_and_pitches) do
        if p ~= nil then
            file.write(d .. "," .. p .. "\n")
        end
    end
    file.close()
end

function ballistics.import_range_table(filepath)
    local file = fs.open(filepath, "r")
    local imported_distances_and_pitches = {}

    while true do
        local line = file.readLine()
        if not line then break end

        local _, pitch = line:match("([^,]+),([^,]+)")

        table.insert(imported_distances_and_pitches, pitch)
    end
    file.close()

    return imported_distances_and_pitches
end

function ballistics.lookup_pitch(distances_and_pitches, input_distance)
    -- Either it's somehow inside the tank or outside of max range
    if input_distance < 0 or input_distance > #distances_and_pitches then return nil end

    local distance_1 = math.floor(input_distance)

    -- Exact match
    if input_distance == distance_1 then
        return distances_and_pitches[input_distance]
    end

    -- otherwise, interpolate
    local pitch_1 = distances_and_pitches[distance_1]
    local pitch_2 = distances_and_pitches[distance_1 + 1]

    -- we can simplify because our data points are always exactly 1 distance apart
    return pitch_1 + (input_distance - distance_1) * (pitch_2 - pitch_1)
end

function ballistics.generate_range_table()
    local trajectory_types = {
        ["low"] = true,
        ["high"] = false
    }
    local cannon_types = {
        ["medium"] = true,
        ["big"] = false,
    }

    local velocity_ms, cannon_length, trajectory_choice, cannon_choice
    term.clear()
    while true do
        print("=][= Range table generator =][=")
        print("-------------------------------")
        write("Velocity (ms/s): ")
        velocity_ms = tonumber(read())
        print("(Starting from cannon mount to tip, both included)")
        write("Cannon length: ")
        cannon_length = tonumber(read())
        write("Low/high trajectory: ")
        trajectory_choice = string.lower(read())
        write("medium/big cannon: ")
        cannon_choice = string.lower(read())

        if velocity_ms and cannon_length and (trajectory_types[trajectory_choice] ~= nil) then
            print("-------------------------------")
            print("PLEASE CONFIRM")
            print("Velocity (ms/s): ", velocity_ms)
            print("Cannon length: ", cannon_length)
            print("Trajectory: ", trajectory_choice)
            print("Cannon: ", cannon_choice)
            write("y/n: ")
            local choice = read()
            print("-------------------------------")
            if string.lower(choice) == "y" then break end
            term.clear()
        else
            print("At least 1 of the values is incorrect. Please try again.")
        end
    end

    local target_height = 0
    local t0 = 0
    local tn = 750

    print("Generating range table ...")
    local max_distance = ballistics.estimate_max_range(cannon_length, velocity_ms)
    print("Max distance upperbound: ", max_distance)
    local distances_and_pitches = ballistics.calculate_range_table(max_distance, velocity_ms, target_height,
        cannon_length, t0, tn,
        trajectory_types[trajectory_choice], cannon_types[cannon_choice])
    print("Writing range table to file ...")
    ballistics.export_range_table("range_table_" .. trajectory_choice .. ".txt", distances_and_pitches)
    print("Finished")
end

return ballistics
