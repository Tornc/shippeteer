-- Written by Ton, with love. Feel free to modify, consider this under the MIT license.

local utils = require("utils")

--[[
    ASYNC ACTIONS MODULE
]]

local async_actions = setmetatable({}, {})
local actions = {} -- A register of all the actions that have been created.

local function register_action(action)
    table.insert(actions, action)
end

function async_actions.get_actions()
    return actions
end

--- # ⚠️ DO NOT USE ⚠️
--- Very niche use-case (stupid hack).
function async_actions.wipe_actions()
    actions = {}
end

--- Creates and manages asynchronous actions.
function async_actions.action()
    local self = setmetatable({}, {})

    local STATES = {
        RUNNING = 1,
        TERMINATED = 2,
    }

    --- Creates a new asynchronous action. I'm not too happy with having to pass in line _and_
    --- timeout, but it is what it is.
    --- @param func function The function to run as a coroutine.
    --- @param line integer? The line of code that created the action in the main script.
    --- @param timeout number? After how many seconds it will give a timeout error.
    --- @return table action The created action instance.
    function self.create(func, line, timeout)
        self.func = func
        self.line = line
        self.timeout = timeout or 9999999 -- or in 2777 hrs
        self.state = STATES.RUNNING
        self.end_time = utils.time_seconds() + self.timeout
        self.co = coroutine.create(function() return self.func() end)
        register_action(self)
        return self
    end

    --- Updates the state of the action by resuming the coroutine.
    --- @throws Error if the action has timed out or if there is an error in coroutine execution.
    function self.update()
        if self.state ~= STATES.RUNNING then return end

        local _, err = coroutine.resume(self.co)

        if err then error(tostring(err)) end
        if utils.time_seconds() > self.end_time then error("Action on line " .. tostring(self.line) .. " has timed out!") end
        if coroutine.status(self.co) == "dead" then self.terminate() end
    end

    --- Whether the action is still going on.
    --- @return boolean
    function self.is_running() return self.state == STATES.RUNNING end

    --- Terminates the action
    function self.terminate() self.state = STATES.TERMINATED end

    --- Whether the action has been terminated.
    ---@return boolean
    function self.is_terminated() return self.state == STATES.TERMINATED end

    return self
end

--- Updates all registered actions, allowing them to proceed or complete.
function async_actions.update()
    for _, action in pairs(actions) do
        action.update()
    end
end

--- Coroutine-friendly version of os.sleep(), to be used in actions.
--- @param duration number? The duration to yield in seconds. If nil, yield once.
function async_actions.pause(duration)
    if not coroutine.running() then return end
    local end_time = utils.time_seconds() + (duration or 0)
    repeat
        coroutine.yield()
    until utils.time_seconds() > end_time
end

--- Pause code execution of a thread until all the given actions have been terminated.
--- @param ... table A variable number of actions to wait on.
function async_actions.pause_until_terminated(...)
    if not coroutine.running() then return end
    repeat
        local all_completed = true
        for _, action in pairs({ ... }) do
            if not action.is_terminated() then
                all_completed = false
                break
            end
        end
        if not all_completed then coroutine.yield() end
    until all_completed
end

return async_actions
