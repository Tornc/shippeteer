-- Written by Ton, with love. Feel free to modify, consider this under the MIT license.

local matrix = require("matrix") -- See: https://github.com/davidm/lua-matrix/blob/master/lua/matrix.lua
local utils = require("utils")
local pretty = require("cc.pretty")

--[[
    3D GRAPHICS MODULE
]]

--- @TODO: verify this in-game
local graphics_3d = setmetatable({}, {})

--- @class Camera
function graphics_3d.camera()
    local self = setmetatable({}, {})

    --- @return table 4x4 matrix
    local function get_projection_matrix()
        local ar, n, f = self.aspect_ratio, self.near, self.far -- renaming for convenience
        local thv = math.tan(math.rad(self.vfov_deg) * 0.5)     -- Tan half fov
        return matrix {
            { 1 / (ar * thv), 0,       0,                  0 },
            { 0,              1 / thv, 0,                  0 },
            { 0,              0,       -(f + n) / (f - n), -(2 * f * n) / (f - n) },
            { 0,              0,       -1,                 0 },
        }
    end

    --- @return table 4x4 matrix
    local function get_view_rotation_matrix()
        local ori_rad = self.orientation * (math.pi / 180)
        local Rx = matrix {
            { math.cos(ori_rad.x), -math.sin(ori_rad.x), 0, 0 },
            { math.sin(ori_rad.x), math.cos(ori_rad.x),  0, 0 },
            { 0,                   0,                    1, 0 },
            { 0,                   0,                    0, 1 },
        }
        local Ry = matrix {
            { 1, 0,                   0,                    0 },
            { 0, math.cos(ori_rad.y), -math.sin(ori_rad.y), 0 },
            { 0, math.sin(ori_rad.y), math.cos(ori_rad.y),  0 },
            { 0, 0,                   0,                    1 },
        }
        local Rz = matrix {
            { math.cos(ori_rad.z),  0, math.sin(ori_rad.z), 0 },
            { 0,                    1, 0,                   0 },
            { -math.sin(ori_rad.z), 0, math.cos(ori_rad.z), 0 },
            { 0,                    0, 0,                   1 },
        }
        return matrix.transpose(Rz * Ry * Rx)
    end

    --- @param vfov_deg integer Vertical FOV
    --- @param screen_width integer
    --- @param screen_height integer
    --- @param near number Near clipping plane distance
    --- @param far number Far clipping plane distance
    --- @return Camera
    function self.create(vfov_deg, screen_width, screen_height, near, far)
        self.vfov_deg = vfov_deg
        self.screen_width = screen_width
        self.screen_height = screen_height
        self.near = near
        self.far = far

        self.position = vector.new(0, 0, 0)
        self.orientation = vector.new(0, 0, 0)
        self.aspect_ratio = self.screen_width / self.screen_height
        self.projection_matrix = get_projection_matrix()
        self.view_rotation_matrix = get_view_rotation_matrix()
        return self
    end

    --- @param position table 3d Vector
    --- @param orientation table 3d Vector in degrees
    function self.update(position, orientation)
        self.position = position
        self.orientation = orientation
        self.view_rotation_matrix = get_view_rotation_matrix()
    end

    return self
end

--- Converts a 3D coordinate into a 2D position on screen.
--- @param point table 3d Vector
--- @param camera Camera
--- @return integer? x position on screen.
--- @return integer? y position on screen.
function graphics_3d.project(point, camera)
    -- Convert 3d vectors to 4d vectors.
    local vertex_4d = matrix { { point.x }, { point.y }, { point.z }, { 1 } }
    local camera_pos_4d = matrix { { camera.position.x }, { camera.position.y }, { camera.position.z }, { 1 } }
    -- Translate vertex to camera space
    local translated = vertex_4d - camera_pos_4d
    -- Apply view rotation
    local rotated = camera.view_rotation_matrix * translated
    --- @LATER: this causes clipping issues; lines will disappear when a shape is too close.
    --- This shouldn't be a problem for my use-case, since I'm not drawing any 3D shapes very
    --- close to the camera.
    -- Don't project if behind camera.
    if rotated[3][1] <= camera.near then return nil, nil end
    -- Apply projection matrix
    local projected = camera.projection_matrix * rotated
    -- Perspective divide
    projected = projected / projected[4][1] -- Normalise by w
    -- Screen coord conversion
    local screen_x = utils.round((projected[1][1] + 1) * camera.screen_width / 2)
    local screen_y = utils.round((1 - projected[2][1]) * camera.screen_height / 2)
    return screen_x, screen_y
end

--- Expects a table full of target class, with field .position (3d vector)
--- @param targets table
--- @param camera Camera
--- @param threshold number In degrees; how far the camera can be away from point but still be considered.
--- @return table? focused_target
function graphics_3d.get_focused_target(targets, camera, threshold)
    local threshold_rad = math.rad(threshold)
    local focused_target
    local smallest_distance = math.huge

    local c2w_vrm = matrix.transpose(camera.view_rotation_matrix)
    -- Not being able to slice is pain.
    local camera_direction = vector.new(
        c2w_vrm[1][3],
        c2w_vrm[2][3],
        c2w_vrm[3][3]
    )
    for target in targets do
        local to_target = target.position - camera.position
        local distance = to_target:length()
        if distance == 0 then goto continue end
        if
            distance < smallest_distance and
            (to_target / distance):dot(camera_direction) > (1 - threshold_rad)
        then
            -- Update our candidate focused target
            smallest_distance = distance
            focused_target = target
        end
        ::continue::
    end
    return focused_target
end

return graphics_3d
