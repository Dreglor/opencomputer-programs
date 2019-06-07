local component = require('component')
local log = require('libLog')

--[[
    must return:
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

--consts
local LocatorItem = "minecraft:stone_hoe"
local BeeAlvearyName = "forestry:alveary.plain"
local BeeHouseName = "forestry:bee_house"
local InterfaceName = "appliedenergistics2:interface"


--statics
local result = {}

local devices = {
    databases = {},
    interfaces = {},
    housings = {},
    transposers = {},
}

--functions
local function LocateSideType(proxy, name)
    for i=0,5 do
        local sidename, _ = proxy.getInventoryName(i)
        if (sidename == name) then
            return i
        end
    end

    return -1
end

local function LocateSideItem(proxy, name)
    for i=0,5 do
        local inventory, _ = proxy.getAllStacks(i)
        if (inventory ~= nil) then
            for _,item in ipairs(inventory) do
                if (item.name == name) then
                    return i
                end
            end
        end
    end

    return -1
end

--Execution

--collect devices
log.Info("Collecting device info...")
for address, type in component.list() do
    if (type == 'database') then
        devices.databases[#devices.databases + 1] = component.proxy(address)
    end

    if (type == 'me_interface') then
        devices.interfaces[#devices.interfaces + 1] = component.proxy(address)
    end

    --both Alvearies and "bee house" show as this
    if (type == 'bee_housing') then
        devices.housings[#devices.housings + 1] = component.proxy(address)
    end

    if (type == 'transposer') then
        local proxy = component.proxy(address)
        --ensure its connected to a proper
        if (LocateSideType(proxy, InterfaceName) >= 0 and
            (LocateSideType(proxy, BeeAlvearyName) >= 0 or LocateSideType(proxy, BeeHouseName) >= 0)) then
            devices.transposers[#devices.transposers + 1] = proxy
        end
    end
end

--must at least have 1 database
if (#devices.databases <= 0) then
    log.Error("Failure to find a single database component")
    return result;
end

--that database must have a database that is big enough
local successful, _ = pcall(component.database.computeHash, #devices.interfaces)
if (successful == false) then
    log.Error("Database not big enough for array ")
    return result;
end

if (#devices.interfaces <= 0) then
    log.Error("Failure to find a single interface component")
    return result;
end

--must have equal number of interfaces, beehousings, and transposers
if (#devices.interfaces == #devices.housings and #devices.interfaces == devices.transposers) then
    log.Error("Failure to find a equal number of interfaces, bee housings, transposers!")
    return result;
end

if (component.me_interface.getItemsInNetwork({name = LocatorItem})["n"] == 0) then
    log.Error("Failure the finding item used for inspecting clusters (" .. LocatorItem ..
            ") make sure there is at least one of them stored")
    return result;
end

--inspect clusters
log.Info("Inspecting clusters...")
local DatabaseSlot = 1
for _, interfaceDevice in ipairs(devices.interfaces) do
    --use an unrelated item to find adjecent transposers

    component.database.clear(1)
    component.me_interface.store({name = LocatorItem}, component.database.address, DatabaseSlot, 1)
    interfaceDevice.setInterfaceConfiguration(DatabaseSlot, component.database.address, DatabaseSlot, 1)
    component.database.clear(1)

    for deviceIndex,transposerDevice in ipairs(devices.transposers) do
        local side = LocateSideItem(transposerDevice, LocatorItem)

        interfaceDevice.setInterfaceConfiguration(DatabaseSlot, component.database.address, 1, 1) --clear config
        if (side >= 0) then
            --valid cluster found
            log.Info("found a cluster: {" .. transposerDevice.address .. "},{" .. interfaceDevice.address .. "}")
            local cluster = {}

            cluster.transposer = transposerDevice.address
            cluster.interfaceSide = LocateSideType(transposerDevice, InterfaceName)
            cluster.beeSide = LocateSideType(transposerDevice, BeeAlvearyName)
            cluster.interface = interfaceDevice.address
            cluster.database = component.database.address
            cluster.databaseSlot = DatabaseSlot

            DatabaseSlot = DatabaseSlot + 1

             --also support "bee house"
            if (cluster.beeSide < 0) then
                cluster.beeSide = LocateSideType(transposerDevice, BeeHouseName)
            end

            result[#result + 1] = cluster

            --do not consider this device for any other interface
            table.remove(devices.transposers,deviceIndex)
            break
        end
    end
end

return result;