-- Written by Ton, with depression. Feel free to modify, consider this under the MIT license.

--[[
    PID MODULE

    Okay, look - I surrender... 🏳️
]]

local pid = setmetatable({}, {})

local K = {}
local integrals = {}
local delta_time

--- @param name string
--- @param kp number
--- @param ki number
--- @param kd number
function pid.setKpid(name, kp, ki, kd)
    K[name] = {
        p = kp,
        i = ki,
        d = kd
    }
    integrals[name] = 0
end

--- @param dt number
function pid.set_dt(dt)
    delta_time = dt
end

--- @param name string
--- @param yaw_error number
--- @param omega_y number
--- @return number rpm
function pid.get_turret_rpm(name, yaw_error, omega_y)
    local proportional = K[name].p * yaw_error
    integrals[name] = integrals[name] + yaw_error * delta_time
    local integral = K[name].i * integrals[name]
    local derivative = K[name].d * omega_y
    return proportional + integral - derivative
end

return pid
