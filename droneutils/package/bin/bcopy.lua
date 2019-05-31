local shell = require("shell")
local io = require("io")
local serialization = require("serialization")

local log = require("liblog")
local drone = require("libdrone")

local args, ops = shell.parse(...)
local usage = "Usage: bcopy FILE DEST\n"
local source
local destination

if (#ops > 0) then
    print(usage)
    log.error("Unknown option specified!")
    return
end

if (args[1] == nil) then
    log.Error("File must be specified!")
    print(usage)
    return
end

if (args[2] == nil) then
    log.Error("Destination must be specified!")
    print(usage)
    return
end

if (#args > 2) then
    log.Error("extra arguments specified, are the arguments enclosed in quotes?")
    print(usage)
    return
end

source = args[1]
destination = args[2]

local handle = io.open(source, 'r')

if (handle == nil) then
    log.fatal("Source File does not exist or could not be opened for reading!")
end

local data = handle:read("*a")
handle:close()

local head = "local io=require('io');local handle=io.open('" .. destination .. "','w');local data="
local body = serialization.serialize(data)
local tail = ";print(data);handle:write(data);handle:close()"

drone.Broadcast(head..body..tail)
