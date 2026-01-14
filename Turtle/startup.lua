rednet.open("right")
local bridgeID = 0 -- Set this to your Bridge Computer's ID

print("Turtle ID: " .. os.getComputerID())

while true do
    local id, msg = rednet.receive()
    
    if msg == "dance" then
        turtle.turnRight()
        rednet.send(id, "I am finished dancing!") -- Sends back to bridge
    elseif msg == "status" then
        local fuel = turtle.getFuelLevel()
        rednet.send(id, "Fuel level is: " .. fuel)
    end
end
