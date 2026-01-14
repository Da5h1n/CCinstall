rednet.open("right") -- Adjust modem side
print("Turtle ID: " .. os.getComputerID() .. " ready.")

while true do
    local id, msg = rednet.receive()
    if msg == "dance" then
        print("Dancing!")
        for i=1,4 do turtle.turnRight() end
    elseif msg == "move" then
        turtle.forward()
    end
end
