-- Written by Ton, with love. Feel free to modify, consider this under the MIT license.

--[[
    LQR CONTROLLER MODULE
]]

local matrix = require "matrix"

local lqr = setmetatable({}, {})

--[[ MATRIX VALUES ]]

lqr.TUR_YAW_Q = matrix { -- State cost matrix
    { 10, 0 },           -- Yaw error
    { 0,  1 },           -- Yaw angular velocity
}
lqr.TUR_YAW_R = matrix { -- Control cost matrix
    { 0.5 },             -- Yaw actuator
}
lqr.TUR_YAW_A = matrix { -- State dynamics matrix
    { 0, 1 },            -- d(theta_y)/dt = omega_y
    { 0, 0 },            -- d(omega_y)/dt = 0 (no direct influence)
}
lqr.TUR_YAW_B = matrix { -- Control input matrix
    { 0 },               -- No direct influence on theta_y
    { 1 },               -- Control input u_y affects omega_y
}

--[[ FUNCTIONS ]]

--- @param Q table State cost matrix
--- @param R table Control cost matrix
--- @param A table State dynamics matrix
--- @param B table Control input matrix
--- @param dt number Interval between control inputs. (SLEEP_INTERVAL is a safe bet)
--- @return table
function lqr.compute_gain(Q, R, A, B, dt)
    local function discretise(_A, _B, _dt)
        local Ad = matrix:new(matrix.rows(_A), "I") + _A * _dt
        local Bd = _B * _dt
        return Ad, Bd
    end

    --- I don't want to look at this math ever again.
    local function solve_discrete_Riccati(_A, _B, _Q, _R)
        local max_iterations = 100
        local tolerance = 1e-9
        local P = _Q
        local difference = tolerance + 1
        local i = 0

        while difference > tolerance and i < max_iterations do
            i = i + 1
            local P_next = matrix.transpose(_A) * P * _A
                - (matrix.transpose(_A) * P * _B)
                * matrix.invert(_R + matrix.transpose(_B) * P * _B)
                * (matrix.transpose(_B) * P * _A) + _Q
            difference = matrix.normf(P_next - P)
            P = P_next
        end

        return P
    end

    local Ad, Bd = discretise(A, B, dt)
    local P = solve_discrete_Riccati(Ad, Bd, Q, R)

    -- Compute gain matrix
    K = matrix.invert(R + matrix.transpose(Bd) * P * Bd)
        * matrix.transpose(Bd) * P * Ad

    return K
end

--- @param yaw_error number
--- @param omega_y number
--- @param K table Gain matrix, make sure it's the right one though.
--- @return number
function lqr.get_yaw_rpm(yaw_error, omega_y, K)
    local state_matrix   = matrix {
        { yaw_error },
        { omega_y },
    }
    local control_matrix = -(K * state_matrix)
    return matrix.getelement(control_matrix, 1, 1)
end

return lqr
