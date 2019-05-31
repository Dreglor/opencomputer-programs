local io = require("io")
local serialization = require("serialization")

local log = require("liblog")
local drone = require("libdrone")

local function PushFile(source)
    local handle = io.open(source, 'r')

    if (handle == nil) then
        log.fatal("Source File does not exist or could not be opened for reading!")
    end

    local data = handle:read("*a")
    handle:close()

    local head = "local io=require('io');local handle=io.open('" .. source .. "','w');local data="
    local body = serialization.serialize(data)
    local tail = ";handle:write(data);handle:close()"

    drone.Broadcast(head..body..tail)
end

PushFile("/usr/lib/liblog.lua")
PushFile("/usr/lib/libdrone.lua")
PushFile("/etc/rc.d/droned.lua")

drone.Broadcast("local computer=require('computer');computer.shutdown(true)")
