-- Written by Ton, with depression. Feel free to modify, consider this under the MIT license.

local utils = require("utils")

--[[
    PID MODULE

    Okay, look - I surrender... 🏳️
]]

local pid = setmetatable({}, {})

function pid.controller()
    local self = setmetatable({}, {})

    --- @param kp number
    --- @param ki number
    --- @param kd number
    function self.create(kp, ki, kd)
        self.Kp = kp
        self.Ki = ki
        self.Kd = kd

        self.integral = 0
        self.previous_error = 0

        self.current_time = utils.time_seconds()
        self.previous_time = utils.time_seconds()
        return self
    end

    --- @param error number
    --- @return number output
    function self.get_output(error)
        self.current_time = utils.time_seconds()
        local dt = self.current_time - self.previous_time

        if dt <= 0 then return 0 end

        local proportional = error
        self.integral = self.integral + error * dt
        local derivative = (error - self.previous_error) / dt

        local output = self.Kp * proportional + self.Ki * self.integral + self.Kd * derivative

        self.previous_error = error
        self.previous_time = self.current_time

        return output
    end

    return self
end

return pid
