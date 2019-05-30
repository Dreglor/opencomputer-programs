local drone = require("libdrone")
local CODE = 'local component = require("component");component.computer.stop()'

drone.Broadcast(CODE)