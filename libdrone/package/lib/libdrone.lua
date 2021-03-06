local lib = {}

--includes
local component = require("component")
local event = require("event")
local serialization = require("serialization")
local os = require("os")
local math = require("math")
local log = require("liblog")

--const
local MODEMTYPE = "modem"
local STRINGTYPE = "string"
local COMPONENTADDEVENT = "component_added"
local COMPONENTREMOVEEVENT = "component_removed"
local MODEMMESSAGEEVENT = "modem_message"
local WAKEMESSAGE = "WAKE"

local Running = false
local REQUESTPORT = 1111
local RESPONSEPORT = 1112

--static
local Interfaces = {} --proxy table for all modem devices
local Message = {} --message dictionary buffers keyed on localAddress+remoteAddress so race conditions shouldn't occur
local PACKETSIZE = 4096 --max packet size default in config is 8192

local MAXPACKETSRATE = 4
local PacketRate = 0
local Timer

lib.REQUESTEVENT = "DroneRequest"
lib.RESPONSEEVENT = "DroneResponse"

--device event handlers
function lib.OnAdd(_, address, type)
    if (type ~= MODEMTYPE) then
        return
    end

    local modem = component.proxy(address)
    modem.open(REQUESTPORT)
    if (modem.isOpen(REQUESTPORT) == false) then
        log.Error("Failed to open " .. REQUESTPORT .. " on device " .. address ..
                  " for listening, is there another instance using the port?")
        return
    end

    modem.open(RESPONSEPORT)
    if (modem.isOpen(RESPONSEPORT) == false) then
        log.Error("Failed to open " .. RESPONSEPORT .. " on device " .. address ..
                  " for listening, is there another instance using the port?")
        return
    end

    if (Interfaces[address] ~= nil) then
        log.Warning("Device already registered for listening, closing device")
        Interfaces[address].close(REQUESTPORT)
        Interfaces[address].close(RESPONSEPORT)
        Interfaces[address] = nil
    end

    modem.setWakeMessage(WAKEMESSAGE)
    Interfaces[address] = modem
    log.Info("Started listening on port " .. REQUESTPORT .. " & " .. RESPONSEPORT .. " with device " .. address)
end

function lib.OnRemove(_, address, type)
    if (type ~= MODEMTYPE) then
        return
    end

    if (Interfaces[address] == nil) then
        log.Warning("Device was not registered for listening, ignoring")
        return
    end

    --no need to close the port the device removal will do that for us
    Interfaces[address] = nil
    log.Info("Removed interface from listening list " .. address)
end

function lib.Cooldown()
    if (PacketRate > 0) then
        PacketRate = PacketRate - 1
    end
end

local function GatedSend(device, to, port, data)
    while (PacketRate >= MAXPACKETSRATE) do
        os.sleep(1/MAXPACKETSRATE)
    end
    PacketRate = PacketRate + 1
    return device.send(to, port, data)
end

local function GatedBroadcast(device, port, data)
    while (PacketRate > 0) do
        os.sleep(1/MAXPACKETSRATE)
    end
    PacketRate = PacketRate + MAXPACKETSRATE
    return device.broadcast(port, data)
end

function lib.Send(interface, sendto, code, port)
    if (port == nil) then
        port = REQUESTPORT
    end

    if (#code < PACKETSIZE) then
        if (GatedSend(Interfaces[interface], sendto, port, code) == false) then
            log.Fatal("Unable to send message, this should always work unless the device has " ..
                          "been removed!")
        end
        return
    end

    -- if response is too large to send in a single packet then fragment it
    if (#code >= PACKETSIZE) then
        if (#code == PACKETSIZE) then
            -- pad out one character to ensure to avoid corner cases
            code = code .. " "
        end

        --split and send large results
        local i = 0
        local fragment = string.sub(code, 1, PACKETSIZE)
        while (fragment ~= "") do
            if (GatedSend(Interfaces[interface], sendto, port, fragment) == false) then
                log.Fatal("Unable to send message fragment, this should always work unless the device has " ..
                          "been removed!")
            end

            i = i + 1
            fragment = string.sub(code, (i * PACKETSIZE) + 1, (i + 1) * PACKETSIZE)
        end
    end
end

function lib.Broadcast(code, interface, port)
    if (port == nil) then
        port = REQUESTPORT
    end

    local broadcasting = {}
    if (interface == nil) then
        for address, _ in pairs(Interfaces) do
            broadcasting[#broadcasting + 1] = address
        end
    else
        broadcasting = {interface}
    end

    for _, address in ipairs(broadcasting) do
        if (#code < PACKETSIZE) then
            if (GatedBroadcast(Interfaces[address], port, code) == false) then
                log.Fatal("Unable to broadcast message, this should always work unless the device has " ..
                              "been removed!")
            end
        else
            if (#code == PACKETSIZE) then
                -- pad out one character to ensure to avoid corner cases
                code = code .. " "
            end

            --split and send large results
            local i = 0
            local fragment = string.sub(code, 1, PACKETSIZE)
            while (fragment ~= "") do
                if (GatedBroadcast(Interfaces[address], port, fragment) == false) then
                    log.Fatal("Unable to broadcast message, this should always work unless the device has " ..
                              "been removed!")
                end

                i = i + 1
                fragment = string.sub(code, (i * PACKETSIZE) + 1, (i + 1) * PACKETSIZE)
            end
        end
    end
end

--event Handlers
function lib.OnNetwork(_, sentTo, from, port, _, data)
    PacketRate = PacketRate + 1

    if (port ~= REQUESTPORT and port ~= RESPONSEPORT) then
        return
    end

    if (Interfaces[sentTo] == nil) then
        log.Error("Dropping traffic received on device that is not registered for listening [" .. from .. " -> "..
                  sentTo .. "]")
        return
    end

    if (type(data) ~= STRINGTYPE) then
        log.Error("Dropping traffic that was not a string type.")
        return
    end

    local key = sentTo..from

    if (Message[key] == nil) then
        Message[key] = ""
    end

    --append message with recieved data
    Message[key] = Message[key] .. data

    if (#data < PACKETSIZE) then
        if (port == REQUESTPORT) then
            --process request
            event.push(lib.REQUESTEVENT, sentTo, from, Message[key])
            local func, error = load(Message[key])

            local response
            if (func == nil) then
                log.Error("Message sent could not be compiled into a lua function, reason follows: " .. error)

                --mimic packed protected call response to return the error
                response = serialization.serialize({false, "Load failed: " .. error, n=2})
            else
                --respond with result of protected call of the requested message
                response = serialization.serialize(table.pack(pcall(func)))
            end

            --send response
            lib.Send(sentTo, from, response, RESPONSEPORT)
        else
            --process response (pass as string tables cannot be passed)
            event.push(lib.RESPONSEEVENT, sentTo, from, Message[key])
        end

        --message complete, clear for next message
        Message[key] = nil
    end
end

function lib.SendWake(interface, address)
    if (interface == nil) then
        for _, modem in pairs(Interfaces) do
            modem.broadcast(1, WAKEMESSAGE)
        end
    else
        Interfaces[interface].send(address, 1, WAKEMESSAGE)
    end
end

--Service functions
function lib.StartService()
    if (Running == true) then
        return
    end

    for device in component.list(MODEMTYPE) do
        lib.OnAdd(COMPONENTADDEVENT, device, MODEMTYPE)
    end

    --register event handlers
    event.listen(COMPONENTADDEVENT, lib.OnAdd)
    event.listen(COMPONENTREMOVEEVENT, lib.OnRemove)
    event.listen(MODEMMESSAGEEVENT, lib.OnNetwork)
    Timer = event.timer(1/MAXPACKETSRATE, lib.Cooldown, math.huge)

    Running = true
    log.Info("Drone ready...")
end

function lib.StopService()
    if (Running ~= true) then
        return
    end

    log.Info("Shutting down drone!")

    event.ignore(COMPONENTADDEVENT, lib.OnAdd)
    event.ignore(COMPONENTREMOVEEVENT, lib.OnRemove)
    event.ignore(MODEMMESSAGEEVENT, lib.OnNetwork)
    event.cancel(Timer)

    for device in component.list(MODEMTYPE) do
        lib.OnRemove(COMPONENTREMOVEEVENT, device, MODEMTYPE)
    end

    Interfaces = {}
    Message = {}

    Running = false
end

function lib.ServiceStatus()
    if (Running == true) then
        print("Drone Deamon is currently RUNNING")
    else
        print("Drone Deamon is currently STOPPED")
    end

    return Running
end

return lib