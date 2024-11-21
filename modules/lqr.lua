-- Written by Ton, with love. Feel free to modify, consider this under the MIT license.

-- See: https://github.com/davidm/lua-matrix/blob/master/lua/matrix.lua
local matrix = require("matrix")

--[[
    LQR MODULE
]]

local lqr = setmetatable({}, {})

--[[ MATRIX VALUES ]]

local TUR_YAW_Q = matrix { -- State cost matrix
    { 100, 0 },            -- Yaw error
    { 0,   1 },            -- Yaw angular velocity
}
local TUR_YAW_R = matrix { -- Control cost matrix
    { 1 },                 -- Yaw actuator
}
local TUR_YAW_A = matrix { -- State dynamics matrix
    { 0, 1 },              -- d(theta_y)/dt = omega_y
    { 0, 0 },              -- d(omega_y)/dt = 0 (no direct influence)
}
local TUR_YAW_B = matrix { -- Control input matrix
    { 0 },                 -- No direct influence on theta_y
    { 1 },                 -- Control input u_y affects omega_y
}

--[[ FUNCTIONS ]]

function lqr.init(dt)
    TUR_YAW_K = lqr.compute_gain(
        TUR_YAW_Q,
        TUR_YAW_R,
        TUR_YAW_A,
        TUR_YAW_B,
        dt
    )
end

--- @param Q table State cost matrix
--- @param R table Control cost matrix
--- @param A table State dynamics matrix
--- @param B table Control input matrix
--- @param dt number Interval between control inputs. (SLEEP_INTERVAL is a safe bet)
--- @return table K Gain matrix
function lqr.compute_gain(Q, R, A, B, dt)
    local function discretise(_A, _B, _dt)
        local Ad = matrix:new(matrix.rows(_A), "I") + _A * _dt
        local Bd = _B * _dt
        return Ad, Bd
    end

    -- I don't want to look at this math ever again.
    -- See https://en.wikipedia.org/wiki/Algebraic_Riccati_equation for more depression.
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
--- @return number
function lqr.get_turret_yaw_rpm(yaw_error, omega_y)
    local state_matrix   = matrix {
        { yaw_error },
        { omega_y },
    }
    -- local control_matrix = -(TUR_YAW_K * state_matrix)
    local control_matrix = TUR_YAW_K * state_matrix
    return matrix.getelement(control_matrix, 1, 1)
end

return lqr
