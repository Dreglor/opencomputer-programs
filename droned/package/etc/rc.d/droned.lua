local implementation = require("libdrone")

function start()
    implementation.StartService(true)
end

function stop()
    implementation.StopService()
end