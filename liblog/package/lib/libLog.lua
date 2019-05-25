--Logging facility

local Log = {}

function Log.Fatal(message)
    error("FATAL: " .. message)
end

function Log.Error(message)
    print("ERROR: " .. message)
end

function Log.Warning(message)
    print("WARNING: " .. message)
end

function Log.Info(message)
    print("INFO: " .. message)
end

return Log