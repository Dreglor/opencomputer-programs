--Logging facility

local lib = {}
local net = require("libnet")
local os = require("os")

lib.Level {
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

local LogName = "general"
local RecordPath = "/var/log/"
local LOGPORT = 1110

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

function lib.SetLogName(name)
    LogName = name
end

local function Record(level, message)
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

    local handle = os.open(RecordPath..LogName, "a")
    handle:write("[" .. tostring(os.time) .. "] <".. level .."> - " .. message)
    handle:close()
end

local function Broadcast(level, message)
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

    local payload = {Time = os.time(), Name = LogName, Level = level, Message = message}
    net.Broadcast(payload, LOGPORT)
end

local function Display(level, message)
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

    print("[".. level .."] - " .. message)
end

local function Log(level, message)
    Display(level, message)
    Broadcast(level, message)
    Record(level, message)
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

return lib