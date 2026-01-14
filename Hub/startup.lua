local ws_url = "ws://skinnerm.duckdns.org:25565"
rednet.open("back")

local ws = nil
local send_queue = {}

-- Function to handle connection
local function connect()
    while not ws do
        print("Connecting to PC...")
        ws, err = http.websocket(ws_url)
        if not ws then
            print("Failed. Retrying in 5s...")
            sleep(5)
        end
    end
    print("Connected!")
    -- Send queued messages
    while #send_queue > 0 do
        ws.send(table.remove(send_queue, 1))
    end
end

-- Function to safely send or queue
local function safeSend(msg)
    if ws then
        local success = pcall(function() ws.send(msg) end)
        if not success then 
            ws = nil
            table.insert(send_queue, msg)
        end
    else
        table.insert(send_queue, msg)
    end
end

-- Main logic
connect()

while true do
    -- Listen for BOTH WebSocket and Rednet (Turtle) messages
    local event = {os.pullEvent()}
    
    if event[1] == "websocket_message" then
        local msg = event[3]
        local words = {}
        for word in msg:gmatch("%S+") do table.insert(words, word) end
        
        if words[1]:lower() == "all" then
            rednet.broadcast(words[2])
        else
            local id = tonumber(words[1])
            if id then rednet.send(id, words[2]) end
        end

    elseif event[1] == "rednet_message" then
        -- COMMUNICATION BACK: Turtle talks to Bridge
        local senderID = event[2]
        local message = event[3]
        print("From Turtle " .. senderID .. ": " .. message)
        safeSend("Turtle " .. senderID .. " says: " .. message)

    elseif event[1] == "websocket_closed" then
        print("Connection lost!")
        ws = nil
        connect()
    end
end
