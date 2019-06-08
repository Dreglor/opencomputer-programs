local lib = {}

--includes
local component = require("component")
local event = require("event")
local os = require("os")
local math = require("math")

--const
local MODEMTYPE = "modem"
local COMPONENTADDEVENT = "component_added"
local COMPONENTREMOVEEVENT = "component_removed"
local MODEMMESSAGEEVENT = "modem_message"
local WAKEMESSAGE = "WAKE"

--static
local Interfaces = {} --proxy table for all modem devices
local PACKETSIZE = 4096 --max packet size default in config is 8192

local MAXPACKETSRATE = 4
local Timer
local Listeners = {}

--device event handlers
function lib.OnAdd(_, address, type)
    if (type ~= MODEMTYPE) then
        return
    end

    local modem = component.proxy(address)

    modem.setWakeMessage(WAKEMESSAGE)
    Interfaces[address] = {
        proxy = modem,
        packetRate = 0
    }

    for port,_ in pairs(Listeners) do
        modem.open(port)
    end
end

function lib.OnRemove(_, address, type)
    if (type ~= MODEMTYPE) then
        return
    end

    if (Interfaces[address] == nil) then
        return
    end

    --no need to close the port the device removal will do that for us
    Interfaces[address] = nil
end

function lib.StartListening(port, callback)
    if (Listeners[port] == nil) then
        Listeners[port] = {}
        Listeners[port].callbacks = {} 
    end

    for _,interface in pairs(Interfaces) do
        interface.proxy.open(port)
    end

    if (callback ~= nil) then
        Listeners[port].callbacks[#Listeners[port].callbacks + 1] = callback
        return #Listeners[port].callbacks
    end

    return
end

function lib.StopListening(port, handle)
    if (handle == nil) then
        for _,interface in pairs(Interfaces) do
            interface.proxy.close(port)
        end
        Listeners[port] = nil
    else
        table.remove(Listeners[port].callbacks, handle)
    end

    if (#Listeners[port].callbacks == 0) then
        Listeners[port] = nil
        for _,interface in pairs(Interfaces) do
            interface.proxy.close(port)
        end 
    end
end

function lib.Cooldown(interface)
    local device = Interfaces[interface]
    if (device.packetRate > 0) then
        device.packetRate = device.packetRate - 1
    end
end

local function GatedSend(interface, to, port, payload)
    local device = Interfaces[interface]

    while (device.packetRate >= MAXPACKETSRATE) do
        os.sleep(1/MAXPACKETSRATE)
    end
    device.PacketRate = device.PacketRate + 1

    return device.proxy.send(to, port, payload)
end

local function GatedBroadcast(interface, port, payload)
    local device = Interfaces[interface]

    while (device.packetRate >= 0) do
        os.sleep(1/MAXPACKETSRATE)
    end
    device.PacketRate = MAXPACKETSRATE

    return device.proxy.broadcast(port, payload)
end

function lib.Send(interface, sendto, payload, port)
    if (#payload < PACKETSIZE) then
        if (GatedSend(Interfaces[interface], sendto, port, payload) == false) then
            log.Fatal("Unable to send message, this should always work unless the device has " ..
                          "been removed!")
        end
        return
    end

    -- if response is too large to send in a single packet then fragment it
    if (#payload >= PACKETSIZE) then
        if (#payload == PACKETSIZE) then
            -- pad out one character to ensure to avoid corner cases
            payload = payload .. " "
        end

        --split and send large results
        local i = 0
        local fragment = string.sub(payload, 1, PACKETSIZE)
        while (fragment ~= "") do
            if (GatedSend(Interfaces[interface], sendto, port, fragment) == false) then
                log.Fatal("Unable to send message fragment, this should always work unless the device has " ..
                          "been removed!")
            end

            i = i + 1
            fragment = string.sub(payload, (i * PACKETSIZE) + 1, (i + 1) * PACKETSIZE)
        end
    end
end

function lib.Broadcast(payload, port, interface)
    local broadcasting = {}
    if (interface == nil) then
        for address, _ in pairs(Interfaces) do
            broadcasting[#broadcasting + 1] = address
        end
    else
        broadcasting = {interface}
    end

    for _, address in ipairs(broadcasting) do
        if (#payload < PACKETSIZE) then
            GatedBroadcast(Interfaces[address], port, payload)
        else
            if (#payload == PACKETSIZE) then
                -- pad out one character to ensure to avoid corner cases
                payload = payload .. " "
            end

            --split and send large results
            local i = 0
            local fragment = string.sub(payload, 1, PACKETSIZE)
            while (fragment ~= "") do
                GatedBroadcast(Interfaces[address], port, fragment)
                i = i + 1
                fragment = string.sub(payload, (i * PACKETSIZE) + 1, (i + 1) * PACKETSIZE)
            end
        end
    end
end


function lib.Wake(interface, address)
    if (interface == nil) then
        if (address == nil) then
            for device, _ in pairs(Interfaces) do
                lib.GatedBroadcast(device, 1, WAKEMESSAGE)
            end
        else
            for device, _ in pairs(Interfaces) do
                lib.GatedSend(device, address, 1, WAKEMESSAGE)
            end
        end
    else
        lib.GatedSend(interface, address, 1, WAKEMESSAGE)
    end
end

function lib.GetInterfaces()
    local result = {}

    for address,_ in pairs(Interfaces) do
        result[#result] = address
    end
    return Interfaces
end

--event Handlers
function lib.OnNetwork(_, sentTo, from, port, _, data)
    local device = Interfaces[sentTo]
    device.packetRate = device.packetRate + 1
    if (Listeners[port] ~= nil and #Listeners[port].callbacks > 0) then
        for _,callback in ipairs(Listeners[port].callbacks) do
            callback(sentTo, from, port, data)
        end
    end
end

--general startup
if (Timer == nil) then
    Timer = event.timer(1/MAXPACKETSRATE, lib.Cooldown, math.huge)
    event.listen(COMPONENTADDEVENT, lib.OnAdd)
    event.listen(COMPONENTREMOVEEVENT, lib.OnRemove)
    event.listen(MODEMMESSAGEEVENT, lib.OnNetwork)
end

return lib