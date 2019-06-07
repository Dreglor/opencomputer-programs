local lib = {}

--includes
local os = require("os")
local event = require("event")
local serialization = require("serialization")
local io = require("io")

local log = require("liblog")
local drone = require("libdrone")

--const
local FRAGMENTPATH = "/usr/srv/baas/fragments/"

--static
local Running = false

--[[
    {
        [<address>] = <interface>
    }
]]
local InterfaceMap = {} --remote address Map to modem device addresses

--[[
    {
        [<address>] = {
            LastTime = <last response time>
            Action = <function to execute when response comes in>
        }
    }
]]
local Drones = {}

--[[
    [<me_interface address>] = {
        address = <remote address>
        database <address>
        transposer = <address>
        beeSide = <side for the bees>
        interfaceSide = <side for the interface>
        databaseSlot = <database slot used for tracking drones>
        isWorking = true
    }
]]
local Nodes = {} --information about all known Nodes (bee operators)

local function Send(address, data)
    drone.Send(InterfaceMap[address], address, data)
end

local function AwaitDrones()
    --wait for timeout
    local mostRecent
    while (true) do
        os.sleep(1)
        for _, operator in pairs(Drones) do
            if ((mostRecent == nil) or (mostRecent < operator.LastTime)) then
                mostRecent = operator.LastTime
            end
        end

        --if nothing new has come in the last second then finish discovery
        if ((mostRecent == nil) or ((mostRecent + 72) < os.time())) then
            return
        end
    end
end

local function Discover()
    log.Info("Discovering Drones")
    drone.Broadcast("") --send empty message to find out who's listening
    AwaitDrones()
end

local function SendFragment(address, file, callback)
    local handle = io.open(FRAGMENTPATH..file)
    local data = handle.read("*a")

    handle:close()

    Drones[address].Action = callback
    Send(address, data)
end

local function InspectCallback(remote, status, result)
    if (status == false) then
        return
    end

    if (status == false) then
        log.Error("Failed to inpsect node [" .. remote .. "]")
        return
    end

    --[[
    returns:
    {
        transposer = <transposer address>,
        interface = <me_interface address>,
        beeSide = <side of bee_housing>,
        interfaceSide = <side of bee_housing>},
        database = <database address>,
        databaseSlot = <database address>
         ...
    }
    ]]

    for _,cluster in ipairs(result) do
        local Node = {
            address = remote,
            transposer = cluster.transposer,
            interface = cluster.interface,
            beeSide = cluster.beeSide,
            interfaceSide = cluster.interfaceSide,
            database = cluster.database,
            databaseSlot = cluster.databaseSlot,
        }
        Nodes[Node.interface] = Node;
    end

    Nodes = {}
end

local function Inspect()
    --drones must follow the criteria to considered for a node
    --[[
        must contain at least 1 database that have enough slots for each "cluster"
        must have equal number of transposers, me_interfaces, and bee_housing components (these represent clusters)
    ]]

    log.Info("Inspecting Drones")

    for address, _ in pairs(Drones) do
        SendFragment(address, "inspect.lua", InspectCallback)
    end
    AwaitDrones()
end

local function SendNodeFragment(node, file, response)
    Send(Nodes[node].address, file, response)
end

function lib.GetNodes()
    return Nodes
end

function lib.GetStatus(node)
    local finished = false;
    local answer = nil;
    SendFragment(node, "status.lua", function(remote, status, result)
        finished = true;
        if (status == false) then
            log.Error("Failure to get status of node: " .. node)
            return
        end
        answer = result
    end)

    while(finished == false) do
        os.sleep(0.25)
    end

    return answer
end

function lib.GetFreeNodes()
    --todo
end

function lib.AssignWork(royalType, droneType)
    --todo
end

--Event handlers
function lib.OnResponse(_, interface, remote, data)
    local response = serialization.unserialize(data)
    local status = response[1]
    local result
    --keep packed
    table.remove( response, 1 )
    response.n = response.n - 1

    if (response.n == 0) then
        result = nil
    else
        result = response
    end

    if (InterfaceMap[remote] ~= interface) then
        InterfaceMap[remote] = interface
    end

    if (Drones[remote] ~= nil) then
        Drones[remote] = {}
    end

    local operator = Drones[remote]

    if (operator.Action ~= nil) then
        operator.Action(remote, status, result)
        operator.Action = nil --clear the action so it only gets called once
    end

    operator.LastTime = os.time()
end

--Service functions
function lib.StartService()
    drone.StartService()
    event.listen(drone.RESPONSEEVENT, lib.OnResponse)
    Discover()
    Inspect()

    if (#Drones == 0) then
        log.Fatal("No Drones found cannot start service.")
    end

    Inspect()
    if (#Nodes == 0) then
        log.Fatal("No capable drones can be identified as a node, cannot start service.")
    end

    log.Info("Bees as a Service started...")
    Running = true
end

function lib.StopService()
end

function lib.ServiceStatus()
    if (Running == true) then
        print("BaaS Deamon is currently RUNNING")
    else
        print("BaaS Deamon is currently STOPPED")
    end

    return Running
end

return lib