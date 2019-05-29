local lib = {}

--includes
local component = require("component")
local event = require("event")
local serialization = require("serialization")
local log = require("liblog")

--const
local MODEMTYPE = "modem"
local STRINGTYPE = "string"
local COMPONENTADDEVENT = "component_added"
local COMPONENTREMOVEEVENT = "component_removed"
local MODEMMESSAGEEVENT = "modem_message"

local running = false
local PORT = 1111

--static
local Listeners = {} --proxy table for all modem devices
local Message = {} --message dictionary buffers keyed on localAddress+remoteAddress so race conditions shouldn't occur
local PACKETSIZE = 4096 --max packet size default in config is 8192

lib.REQUESTEVENT = "DroneRequest"
lib.RESPONSEEVENT = "DroneResponse"

--device event handlers
function lib.OnAdd(_, address, type)
    if (type ~= MODEMTYPE) then
        return
    end

    local modem = component.proxy(address)
    modem.open(PORT)
    if (modem.isOpen(PORT) == false) then
        log.Error("Failed to open " .. PORT .. " on device " .. address ..
                  " for listening, is there another instance using the port?")
        return
    end

    if (Listeners[address] ~= nil) then
        log.Warning("Device already registered for listening, closing device")
        Listeners[address].close(PORT)
        Listeners[address] = nil
    end

    Listeners[address] = modem
    log.Info("Started listening on port " .. PORT .. " with device " .. address)
end

function lib.OnRemove(_, address, type)
    if (type ~= MODEMTYPE) then
        return
    end

    if (Listeners[address] == nil) then
        log.Warning("Device was not registered for listening, ignoring")
        return
    end

    --no need to close the port the device removal will do that for us
    Listeners[address] = nil
    log.Info("Removed interface from listening list " .. address)
end

function lib.Send(interface, sendto, code)
    if (#code < PACKETSIZE) then
        if (Listeners[interface].send(sendto, PORT, code) == false) then
            log.Fatal("Unable to send message response back, this should always work unless the device has " ..
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
        local fragment = string.sub(code, i * PACKETSIZE, (i + 1) * PACKETSIZE)
        while (fragment ~= nil) do
            if (Listeners[interface].send(sendto, PORT, fragment) == false) then
                log.Fatal("Unable to send message fragment back, this should always work unless the device has " ..
                          "been removed!")
            end

            i = i + 1
            fragment = string.sub(code, i * PACKETSIZE, (i + 1) * PACKETSIZE)
        end
    end
end

function lib.Broadcast(code, interfaces)
    local broadcasting = {}
    if (interfaces ~= nil) then
        for address, _ in pairs(Listeners) do
            broadcasting[#broadcasting + 1] = {address}
        end
    else
        broadcasting[1] = {interfaces}
    end

    for _, address in ipairs(broadcasting) do
        if (#code < PACKETSIZE) then
            Listeners[address].broadcast(PORT, code)
        else
            if (#code == PACKETSIZE) then
                -- pad out one character to ensure to avoid corner cases
                code = code .. " "
            end

            --split and send large results
            local i = 0
            local fragment = string.sub(code, i * PACKETSIZE, (i + 1) * PACKETSIZE)
            while (fragment ~= nil) do
                if (Listeners[address].broadcast(PORT, fragment) == false) then
                    log.Fatal("Unable to send message fragment back, this should always work unless the device has " ..
                              "been removed!")
                end

                i = i + 1
                fragment = string.sub(code, i * PACKETSIZE, (i + 1) * PACKETSIZE)
            end
        end
    end
end

--event Handlers
function lib.OnRequest(_, sentTo, from, port, _, data)
    if (port ~= PORT) then
        return
    end

    if (Listeners[sentTo] == nil) then
        log.Error("Dropping traffic received on device that is not registered for listening [" .. from .. " -> "..
                  sentTo .. "]")
        return
    end

    if (type(data) ~= STRINGTYPE) then
        log.Error("Dropping traffic that was not a string type.")
        return
    end

    if (Message[sentTo..from] == nil) then
        Message[sentTo..from] = ""
    end

    --append message with recieved data
    Message[sentTo..from] = Message[sentTo..from] .. data

    if (#data < PACKETSIZE) then
        event.push(lib.REQUESTEVENT)
        local func, error = load(Message)

        --message complete, clear for next message
        Message[sentTo..from] = nil

        local response
        if (func == nil) then
            log.Error("Message sent could not be compiled into a lua function, reason follows: " .. error)

            --mimic packed protected call response to return the error
            response = serialization.serialize({false, "Load failed: " .. error, n=2})

        else
            --respond with result of protected call of the requested message
            response = serialization.serialize(pcall(table.pack(func())))

        end

        --send response
        lib.Send(sentTo, from, response)
    end
end

function lib.OnResponse(_, sentTo, from, port, _, data)
    if (port ~= PORT) then
        return
    end

    if (Listeners[sentTo] == nil) then
        log.Error("Dropping traffic received on device that is not registered for listening [" .. from .. " -> "..
                  sentTo .. "]")
        return
    end

    if (type(data) ~= STRINGTYPE) then
        log.Error("Dropping traffic that was not a string type.")
        return
    end

    if (Message[sentTo..from] == nil) then
        Message[sentTo..from] = ""
    end

    --append message with recieved data
    Message[sentTo..from] = Message[sentTo..from] .. data

    if (#data < PACKETSIZE) then
        event.push(lib.RESPONSEEVENT, sentTo, from, serialization.unserialize(Message[sentTo..from]))
        Message[sentTo..from] = nil
    end
end

--Service functions
function lib.StartService(client)
    if (running == true) then
        return
    end

    for device in component.list(MODEMTYPE) do
        lib.OnAdd(COMPONENTADDEVENT, device, MODEMTYPE)
    end

    --register event handlers
    event.listen(COMPONENTADDEVENT, lib.OnAdd)
    event.listen(COMPONENTREMOVEEVENT, lib.OnRemove)

    if (client == true) then
        event.listen(MODEMMESSAGEEVENT, lib.OnRequest)
    else
        event.listen(MODEMMESSAGEEVENT, lib.OnResponse)
    end

    running = true
    log.Info("Drone ready...")
end

function lib.StopService()
    if (running ~= true) then
        return
    end

    log.Info("Shutting down drone!")

    event.ignore(COMPONENTADDEVENT, lib.OnAdd)
    event.ignore(COMPONENTREMOVEEVENT, lib.OnRemove)
    event.ignore(MODEMMESSAGEEVENT, lib.OnRequest)
    event.ignore(MODEMMESSAGEEVENT, lib.OnResponse)

    for device in component.list(MODEMTYPE) do
        lib.OnRemove(COMPONENTREMOVEEVENT, device, MODEMTYPE)
    end

    Listeners = nil
    Message = nil

    running = false
end

return lib