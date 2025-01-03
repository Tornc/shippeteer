-- Written by Ton, with love. Feel free to modify, consider this under the MIT license.

local utils = require("utils")

--[[
    SHIP COMPONENTS MODULE
]]

local component = setmetatable({}, {})

--- Ensures all parameters are not nil. Please use it whenever possible.
--- This will save you a headache down the line.
--- @param ... any
local function params_nil_check(...)
    local count = select("#", ...) -- Count of arguments including `nil`
    for i = 1, count do
        local param = select(i, ...)
        assert(param ~= nil, "Parameter #" .. i .. " is nil!")
    end
end

function component.ship()
    local self = setmetatable({}, {})

    --- @param name string
    --- @param start_pos table Vector
    --- @return table
    function self.create(name, start_pos)
        self.name = name
        self.start_pos = start_pos
        self.parent = nil
        return self
    end

    function self.get_name()
        return self.name
    end

    function self.get_start_pos()
        return self.start_pos
    end

    function self.get_parent()
        return self.parent
    end

    return self
end

--- There is 0 need to make a movable component by itself.
local function movable()
    local self = component.ship()
    local super_create = self.create

    function self.create(name, start_pos)
        params_nil_check(name, start_pos)
        super_create(name, start_pos)
        self.ship_info = {}
        self.child_components = {} -- Table of things that inherit from ship, can be left as nil
        return self
    end

    function self.update_info(info)
        self.ship_info = info
    end

    function self.get_info()
        return self.ship_info
    end

    --- @param ... table One or more components
    function self.add_child_component(...)
        local function is_circular_reference(comp, target)
            if comp == target then return true end
            for _, child in pairs(comp.child_components or {}) do
                if is_circular_reference(child, target) then return true end
            end
            return false
        end

        for _, comp in pairs({ ... }) do
            assert(not is_circular_reference(comp, self),
                "Circular reference: " .. comp.get_name() .. " can't be a child of " .. self.get_name() .. "!")
            table.insert(self.child_components, comp)
            comp.parent = self
        end
    end

    --- Returns the value of the queried field of the component and all its children.
    --- @param field_name string It's great that `field = ...` is equivalent to `["field"] = ...`
    --- @return table result `{name1 = field1, name2 = field2, ...}`
    function self.get_field_all(field_name)
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

function component.simple_tracked_hull()
    local self = movable()
    local super_create = self.create

    --- @param name string
    --- @param start_pos table Vector
    --- @param relay table Peripheral
    --- @param forward string|table string if only 1 side, otherwise a table of sides.
    --- @param left string|table
    --- @param right string|table
    --- @param reverse string|table
    --- @param track_rpm integer
    --- @return table
    function self.create(name, start_pos,
                         relay, forward, left, right, reverse, track_rpm)
        params_nil_check(name, start_pos, relay, forward, left, right, reverse, track_rpm)
        super_create(name, start_pos)
        self.relay = relay -- Peripheral
        self.forward = forward
        self.left = left   -- These can be tables if there's multiple links
        self.right = right
        self.reverse = reverse
        self.track_rpm = track_rpm
        return self
    end

    --- @return table
    function self.get_relay()
        return self.relay
    end

    --- @return table
    function self.get_controls()
        return {
            ["forward"] = self.forward,
            ["left"] = self.left,
            ["right"] = self.right,
            ["reverse"] = self.reverse,
        }
    end

    --- @return integer
    function self.get_track_rpm()
        return self.track_rpm
    end

    return self
end

local function weapon()
    local self = setmetatable({}, {})

    function self.create(name, relay, links)
        params_nil_check(name, relay, links)
        self.name = name
        self.relay = relay
        self.links = links
        self.type = nil
        return self
    end

    function self.get_name()
        return self.name
    end

    function self.get_relay()
        return self.relay
    end

    function self.get_links()
        return self.links
    end

    --- This is dumb stuff
    --- @return string
    function self.get_type()
        return self.type
    end

    return self
end

local function continuous_weapon()
    local self = weapon()
    local super_create = self.create

    --- @param name string
    --- @param relay table Peripheral
    --- @param links string|table
    --- @param fire_rate integer
    --- @return table
    function self.create(name, relay, links, fire_rate)
        params_nil_check(name, relay, links, fire_rate)
        super_create(name, relay, links)
        self.fire_rate = fire_rate
        self.type = "continuous"
        return self
    end

    --- @return integer
    function self.get_fire_rate()
        return self.fire_rate
    end

    return self
end

local function non_continuous_weapon()
    local self = weapon()
    local super_create = self.create

    --- @param name string
    --- @param relay table Peripheral
    --- @param links string|table
    --- @param reload_time number
    --- @return table
    function self.create(name, relay, links, reload_time)
        params_nil_check(name, relay, links, reload_time)
        super_create(name, relay, links)
        self.reload_time = reload_time
        self.time_last_fired = utils.time_seconds()
        self.type = "non_continuous"
        return self
    end

    --- @return number
    function self.get_reload_time()
        return self.reload_time
    end

    --- @return number
    function self.get_time_last_fired()
        return self.time_last_fired
    end

    --- @param time number
    function self.set_time_last_fired(time)
        self.time_last_fired = time
    end

    return self
end

function component.turret()
    local self = movable()
    local super_create = self.create

    --- @param name string
    --- @param start_pos table Vector
    --- @param relay table Peripheral
    --- @param rotation_controller table Peripheral for rotating the turret precisely.
    --- @return table
    function self.create(name, start_pos,
                         relay, rotation_controller)
        params_nil_check(name, start_pos, relay, rotation_controller)
        super_create(name, start_pos)
        self.relay = relay                               -- Peripheral
        self.rotational_controller = rotation_controller -- Peripheral
        self.weapons = {}
        return self
    end

    --- @param name string
    --- @param links string Side
    --- @param is_continuous boolean
    --- @param cooldown_firerate number cooldown (in seconds) applies to is_continuous `false`, firerate applies to `true`.
    function self.add_weapon(name, links, is_continuous, cooldown_firerate)
        if is_continuous then
            table.insert(self.weapons, continuous_weapon().create(name, self.relay, links, cooldown_firerate))
        else
            table.insert(self.weapons, non_continuous_weapon().create(name, self.relay, links, cooldown_firerate))
        end
    end

    --- @return table rotational_controller Peripheral
    function self.get_rotational_controller()
        return self.rotational_controller
    end

    --- @param name string Name of the weapon you want to query.
    --- @return table? weapon
    function self.get_weapon(name)
        for _, wpn in pairs(self.weapons) do
            if wpn.get_name() == name then return wpn end
        end
    end

    --- @param name string Name of the weapon you want to query.
    --- @return boolean
    function self.is_weapon_continuous(name)
        return self.get_weapon(name).get_type() == "continuous"
    end

    return self
end

return component
