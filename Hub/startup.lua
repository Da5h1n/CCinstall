local ws_url = "ws://skinnerm.duckdns.org:25565"
rednet.open("back")

local ws = nil
local send_queue = {}

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
    while #send_queue > 0 do
        ws.send(table.remove(send_queue, 1))
    end
end

local function safeSend(data)
    -- Convert tables to strings so the WebSocket can handle them
    local msg = type(data) == "table" and textutils.serializeJSON(data) or tostring(data)
    
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

connect()

while true do
    local event = {os.pullEvent()}
    
    if event[1] == "websocket_message" then
        local msg = event[3]
        local words = {}
        for word in msg:gmatch("%S+") do table.insert(words, word) end
        
        if #words >= 2 then
            if words[1]:lower() == "all" then
                rednet.broadcast(words[2])
            else
                local id = tonumber(words[1])
                if id then rednet.send(id, words[2]) end
            end
        end

    elseif event[1] == "rednet_message" then
        local senderID = event[2]
        local message = event[3]
        
        -- Create a structured table to send to the PC
        local dataToPC = {
            type = "turtle_response",
            id = senderID,
            content = message
        }
        
        print("From Turtle " .. senderID .. ": [Data Received]")
        safeSend(dataToPC)

    elseif event[1] == "websocket_closed" then
        print("Connection lost!")
        ws = nil
        connect()
    end
end
