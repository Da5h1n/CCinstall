-- Network Sniffer for CC:Tweaked
local modem = peripheral.find("modem")

if not modem then
    print("Error: No modem attached!")
    return
end

-- Open all frequencies to listen to raw traffic
for i = 1, 65535 do
    rednet.open(peripheral.getName(modem))
end

print("--- SNIFFER ACTIVE ---")
print("Listening for all Rednet traffic...")

while true do
    local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
    
    print("\n[Packet Detected]")
    print("Channel: " .. channel)
    print("Distance: " .. (distance or "unknown"))
    
    if type(message) == "table" then
        -- Print key info if it looks like our fleet protocol
        if message.sProtocol == "fleet_status" then
            local data = message.message
            print("Protocol: fleet_status")
            print("From ID: " .. tostring(data.id))
            print("Type: " .. tostring(data.type))
            if data.pos then
                print("Pos: " .. data.pos.x .. "," .. data.pos.z)
            end
        else
            print("Other Protocol: " .. tostring(message.sProtocol))
        end
    else
        print("Raw Message: " .. tostring(message))
    end
end
