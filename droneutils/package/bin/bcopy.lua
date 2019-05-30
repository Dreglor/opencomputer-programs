local shell = require("shell")
local filesystem = require("filesystem")
local serialization = require("serialization")

local log = require("liblog")
local drone = require("libdrone")

local args, ops = shell.parse(...)
local usage = "Usage: bcopy FILE DEST\n"
local source
local destination

filesystem.


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

local handle = filesystem.open(source, 'rb')
local data = handle:read("*a")

local head = "local filesystem=require('filesystem');serialization=require('serialization');local handle=filesystem.open('" .. destination .. "','w');local data=serialization.unserialize('"
local body = serialization.serialize()
local tail = "');handle:write(data);handle:close()"

drone.Broadcast(head..body..tail)