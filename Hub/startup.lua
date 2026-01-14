local ws_url = "ws://skinnerm.duckdns.org:25565"
local modem_side = "back" -- Adjust to your modem position

rednet.open(modem_side)
print("Connecting to PC at " .. ws_url)

local ws, err = http.websocket(ws_url)
if not ws then
    error("Could not connect: " .. tostring(err))
end

print("Connected to PC Command Center!")

while true do
    local event, url, msg = os.pullEvent("websocket_message")
    print("Signal Received: " .. msg)

    -- Expected format: "ID Command"
    local words = {}
    for word in msg:gmatch("%S+") do table.insert(words, word) end

    local targetID = tonumber(words[1])
    local command = words[2]

    if targetID and command then
        rednet.send(targetID, command)
        ws.send("Sent '" .. command .. "' to Turtle " .. targetID)
    else
        ws.send("Error: Use format 'ID Command'")
    end
end
