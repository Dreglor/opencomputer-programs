local shell = require("shell")
local os = require("os")
local event = require("event")
local serialization = require("serialization")

local log = require("liblog")
local drone = require("libdrone")

local args, ops = shell.parse(...)
local usage = "Usage: bexec (OPTIONS) 'FILE'\n" ..
              "Options:\n"..
              "[--time=seconds] - number for seconds to wait for all responses to return\n" ..
              "[-t seconds] - same as --time\n"

local timeout = 0.1
local commandIndex = 1
local optionCount = 0

if (ops['t'] ~= nil and ops['time'] ~= nil) then
    log.Error("Only one -t or --time can be specified at a time!")
    print(usage)
    return
end

if (ops['t'] ~= nil) then
    timeout = tonumber(args[1])
    commandIndex = commandIndex + 1
    optionCount = optionCount + 1
end

if (ops['time'] ~= nil) then
    timeout = tonumber(ops['time'])
    optionCount = optionCount + 1
end

if (args[commandIndex] == nil) then
    log.Error("Command must be specified!")
    print(usage)
    return
end

if (args[commandIndex + 1] ~= nil) then
    log.Error("extra parameters specified, command must be enclosed in quotes!")
    print(usage)
    return
end

if (#ops > optionCount) then
    print(usage)
    log.error("Unknown option specified!")
    return
end

local file = args[commandIndex]

local handle = io.open(file, "rb")
local code = handle:read("*a")

handle:close()

local function EventHandler(_, interface, from, response)
    local result = serialization.unserialize(response)
    if (result[2] == nil) then
        print("[" .. from .. "] @ [" .. interface .. "] returned (successful?: " .. tostring(result[1]) .. ")")
    else
        print("[" .. from .. "] @ [" .. interface .. "] returned (successful?: " .. tostring(result[1]) .. "): " ..
              serialization.serialize(result[2], true, 10000))
    end
end

event.listen(drone.RESPONSEEVENT, EventHandler)
drone.Broadcast(code)
os.sleep(timeout)
event.ignore(drone.RESPONSEEVENT, EventHandler)