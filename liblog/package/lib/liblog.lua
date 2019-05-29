--Logging facility

local lib = {}

function lib.Fatal(message)
    error("FATAL: " .. message)
end

function lib.Error(message)
    print("ERROR: " .. message)
end

function lib.Warning(message)
    print("WARNING: " .. message)
end

function lib.Info(message)
    print("INFO: " .. message)
end

return lib