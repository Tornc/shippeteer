-- Written by Ton, with love. Feel free to modify, consider this under the MIT license.

--[[
    SHIP COMPONENTS MODULE
]]

local component = setmetatable({}, {})

function component.ship()
    local self = setmetatable({}, {})

    --- @param name string
    --- @param start_pos table Vector
    --- @return table
    function self.create(name, start_pos)
        self.name = name
        self.start_pos = start_pos
        return self
    end

    return self
end

--- There is 0 need to make a movable component by itself.
local function movable()
    local self = component.ship()
    local super_create = self.create

    function self.create(name, start_pos,
                         sensor_id)
        super_create(name, start_pos)
        self.sensor_id = sensor_id
        self.child_components = {} -- Table of things that inherit from ship, can be left as nil
        return self
    end

    --- @param ... table One or more components
    function self.add_child_component(...)
        for _, comp in pairs({ ... }) do
            table.insert(self.child_components, comp)
        end
    end

    --- @param field_name string It's great that `field = ...` is equivalent to `["field"] = ...`
    --- @return table
    function self.get_fields(field_name)
        local fields = {}

        local function traverse_and_collect(comp)
            fields[comp.name] = comp[field_name]
            for _, child in pairs(comp.child_components or {}) do
                traverse_and_collect(child)
            end
        end

        traverse_and_collect(self)
        return fields
    end

    return self
end

function component.hull()
    local self = movable()
    local super_create = self.create

    --- @param name string
    --- @param start_pos table Vector
    --- @param sensor_id string
    --- @param redrouter table Peripheral
    --- @param forward string|table string if only 1 side, otherwise a table of sides.
    --- @param left string|table
    --- @param right string|table
    --- @param reverse string|table
    --- @return table
    function self.create(name, start_pos, sensor_id,
                         redrouter, forward, left, right, reverse)
        super_create(name, start_pos, sensor_id)
        self.redrouter = redrouter -- Peripheral
        self.forward = forward
        self.left = left           -- These can be tables if there's multiple links
        self.right = right
        self.reverse = reverse
        return self
    end

    return self
end

function component.turret()
    local self = movable()
    local super_create = self.create

    --- @param name string
    --- @param start_pos table Vector
    --- @param sensor_id string
    --- @param redrouter table Peripheral
    --- @param rotation_controller table Peripheral for rotating the turret precisely.
    --- @return table
    function self.create(name, start_pos, sensor_id,
                         redrouter, rotation_controller)
        super_create(name, start_pos, sensor_id)
        self.redrouter = redrouter                       -- Peripheral
        self.rotational_controller = rotation_controller -- Peripheral
        self.weapons = {}
        return self
    end

    --- @param name string
    --- @param link string Side
    --- @param is_continuous boolean
    --- @param cooldown_firerate number cooldown (in seconds) applies to is_continuous `false`, firerate applies to `true`.
    function self.add_weapon(name, link, is_continuous, cooldown_firerate)
        self.weapons[name] = { link, is_continuous, cooldown_firerate }
    end

    --- @param name string Name of the weapon you want to query.
    --- @return table weapon_info Format: `{is_continuous, cooldown_firerate}`. cooldown_firerate is either in seconds or in redstone strength.
    function self.get_weapon_info(name)
        return self.weapons[name]
    end

    return self
end

return component
