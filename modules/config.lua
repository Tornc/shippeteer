-- Written by Ton, with love. Feel free to modify, consider this under the MIT license.

local completion = require("cc.completion")

--[[
    CONFIG MODULE
]]

local config = setmetatable({}, {})

--[[ STATE VARIABLES ]]

local configurations = {}

--[[ FUNCTIONS ]]

--- @param question string `"This is a question?"`
--- @param completions table `{"choice1", "choice2", ...}`
--- @param validity_func function?
--- @return string choice Choice of user.
function config.ask_setting(question, completions, validity_func)
    local input
    while true do
        print(question)
        write("> ")
        input = read(nil, nil, function(text) return completion.choice(text, completions) end)
        if validity_func and not validity_func(input, completions) then
            print("\"" .. input .. "\" is not valid.")
        else
            return input
        end
    end
end

--- @param var any
--- @param name string
--- @param type_conversion_func function?
function config.set_setting(var, name, type_conversion_func)
    local entry = var
    if type_conversion_func then entry = type_conversion_func(var) end
    settings.set(name, entry)
end

--- @param path string
function config.save_settings(path)
    if not settings.save(path) then error("Failed to save settings!") end
end

--- Note that this returns _all_ settings, including OS-specific stuff.
--- @return table? settings
function config.get_settings(path)
    if not settings.load(path) then return end
    for _, name in pairs(settings.getNames()) do
        configurations[name] = settings.get(name)
    end
    return configurations
end

return config
