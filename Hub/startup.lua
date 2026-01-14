local ws_url = "ws://skinnerm.duckdns.org:25565"
local modem_side = "back" -- Adjust as needed

rednet.open(modem_side)
print("Connecting to: " .. ws_url)

local ws, err = http.websocket(ws_url)
if not ws then error("Connection failed: " .. tostring(err)) end

print("Bridge Active. Type 'all <cmd>' for broadcast.")

while true do
    local _, _, msg = os.pullEvent("websocket_message")
    
    local words = {}
    for word in msg:gmatch("%S+") do table.insert(words, word) end

    local target = words[1]:lower()
    local command = words[2]

    if target == "all" then
        -- BROADCAST FEATURE
        print("Broadcasting: " .. command)
        rednet.broadcast(command)
        ws.send("Broadcasted '" .. command .. "' to all workers.")
    else
        -- SINGLE TARGET
        local id = tonumber(target)
        if id and command then
            rednet.send(id, command)
            ws.send("Sent to [" .. id .. "]: " .. command)
        else
            ws.send("Invalid target/command.")
        end
    end
end
