--Logging facility

local lib = {}
local net = require("libnet")
local io = require("io")
local serialization = require("serialization")

lib.Level = {
    ["FATAL"] = 1,
    ["ERROR"] = 2,
    ["WARNING"] = 3,
    ["INFO"] = 4,
    ["DEBUG"] = 5,
    [5] = "DEBUG",
    [4] = "INFO",
    [3] = "WARNING",
    [2] = "ERROR",
    [1] = "FATAL",
}

local DisplayLevel = lib.Level["ERROR"]
local RecordLevel = lib.Level["WARNING"]
local BroadcastLevel = lib.Level["INFO"]

local RecordPath = "/var/log/"
local LOGPORT = 1110
local ListenerId = nil


function lib.SetDisplayLevel(level)
    if (type(level) ~= "number") then
        level = lib.Level[level];
    end

    DisplayLevel = level
end

function lib.SetRecordLevel(level)
    if (type(level) ~= "number") then
        level = lib.Level[level];
    end

    RecordLevel = level
end

function lib.SetBroadcastLevel(level)
    if (type(level) ~= "number") then
        level = lib.Level[level];
    end

    BroadcastLevel = level
end

local function Record(level, message, application, from)
    local numberLevel
    if (type(level) == "number") then
        numberLevel = level
        level = lib.Level[level]
    else
        numberLevel = lib.Level[level]
    end

    if (numberLevel >= RecordLevel) then
        return
    end

    if (application == nil) then
        application = "general"
    end

    if (from == nil) then
        from = "local"
    end

    local handle = io.open(RecordPath..from..application..".log", "a")
    handle:write("[" .. tostring(os.time) .. "] <".. application .."> @ ".. from .." - " .. level .. " - " .. message)
    handle:close()
end

local function Broadcast(level, message, application)
    local numberLevel
    if (type(level) == "number") then
        numberLevel = level
        level = lib.Level[level]
    else
        numberLevel = lib.Level[level]
    end

    if (numberLevel >= BroadcastLevel) then
        return
    end

    if (application == nil) then
        application = "general"
    end

    local payload = {Time = os.time(), Level = level, Application = application, Message = message}

    local interfaces = net.GetInterfaces()
    for _,interface in ipairs(interfaces) do
        payload.From = interface
        net.Broadcast(payload, LOGPORT, interface)
    end
end

local function Display(level, message, application, from)
    local numberLevel
    if (type(level) == "number") then
        numberLevel = level
        level = lib.Level[level]
    else
        numberLevel = lib.Level[level]
    end

    if (numberLevel >= DisplayLevel) then
        return
    end

    print("[".. application .."] @ " .. from .. " - " .. level .. " - " .. message)
end

local function Log(level, message, who)
    Display(level, message)
    Broadcast(level, message)
    Record(level, message)
end

local function Sink(_, _, _, data)
    local data = serialization.unserialize(data)
    Display(data.Level, data.Message, data.Application, data.From)
    Record(data.Level, data.Message, data.Application, data.From)
end

function lib.Fatal(message)
    Log("FATAL", message)
    error(message)
end

function lib.Error(message)
    Log("ERROR", message)
end

function lib.Warning(message)
    Log("WARNING", message)
end

function lib.Info(message)
    Log("INFO", message)
end

function lib.Debug(message)
    Log("DEBUG", message)
end

function lib.StartService()
    ListenerId = net.StartListening(LOGPORT, Sink)
end

function lib.StopService()
    net.StopListening(LOGPORT)
    ListenerId = nil
end

function lib.ServiceStatus()
    if (ListenerId ~= nil) then
        print("LogSink Deamon is currently RUNNING")
    else
        print("LogSink Deamon is currently STOPPED")
    end

    return ListenerId ~= nil
end

return lib