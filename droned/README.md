# OpenComputer-Programs - Drone Deamon
Drone Deamon is a simple deamon wrapper for libdrone.

## Drone
Drone provides a simple RCE (remote code execution) enviroment so that a controlling device may push raw lua code over a network to provide a action and reponse model
drones feature comprise of
* hotplugging of network devices
* multi device listening
* basic multi-controller support
* large messages via packet fragmentation (both directions)

#usage
it is intended that libdronecontrol be used to interact with drones on the network however you may opt to send messages directly since the "protocol" is dead simple
sending the lua code (as a string eg, send a whole lua file) to the specified client on port 1111 will cause the client to load and pcall the sent code and the reponse will be sent back if any.
note: if the code is larger than the defined packet size (4k) you must fragment the message then finally the last packet MUST be smaller than the max packet size to indicate the message is complete.
the response will always take the form of: "{bool wasSuccessful, [any results ...],int n=count}" it is intended to use table.unpack() after deserailization.
if load failed or pcall failed the error message will be the only result.