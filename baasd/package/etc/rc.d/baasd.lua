local implementation = require("libbaas")

function start()
    implementation.StartService()
end

function stop()
    implementation.StopService()
end

function status()
    implementation.ServiceStatus()
end