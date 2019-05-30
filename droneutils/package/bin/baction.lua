local shell = require("shell")
local os = require("os")
local serialization = require("serialization")
local event = require("event")

local log = require("liblog")
local drone = require("libdrone")

local args, ops = shell.parse(...)
local usage = "Usage: baction (OPTIONS) 'COMMAND'\n" ..
              "Options:\n"..
              "[--time=seconds] - number for seconds to wait for all responses to return\n" ..
              "[-t seconds] - same as --time\n"

local timeout = 0.1
local commandIndex = 1
local code
local responses = {}
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

code = args[commandIndex]

local function EventHandler(_, interface, from, response)
    responses[#responses + 1] = {
        ["interface"] = interface,
        ["from"] = from,
        ["successful"] = response[1],
        ["result"] = response[2]
    }
end

event.listen(drone.RESPONSEEVENT, EventHandler)
drone.Broadcast(code)
os.sleep(timeout)

for _, response in ipairs(responses) do
    print("[" .. response.from .. "] @ [" .. response.interface .. "] returned (successful?: " ..
          response.successful .. "): " .. response.result)
end

event.ignore(drone.RESPONSEEVENT, EventHandler)