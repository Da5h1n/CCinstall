local ws_url = "ws://skinnerm.duckdns.org:25565"
local installer_pkg = "HUB"
rednet.open("back")

local ws = nil

-- Helper to run the installer script
local function runInstaller(pkg)
    if not fs.exists("installer") then
        shell.run("pastebin", "get", "S3HkJqdw", "installer")
    end
    shell.run("installer", "update", pkg)
end

-- Function to safely send to WebSocket
local function safeSend(data)
    if ws then
        local msg = type(data) == "table" and textutils.serializeJSON(data) or tostring(data)
        pcall(function() ws.send(msg) end)
    end
end

-- Function to handle connection with auto-retry
local function connect()
    print("Connecting to PC...")
    ws, err = http.websocket(ws_url)
    if not ws then
        print("Failed: " .. tostring(err))
        return false
    end
    print("Connected to WebSocket!")
    return true
end

-- Fleet Update logic
local function coordinateFleetUpdate()
    print("Step 1: Updating all Turtles...")
    rednet.broadcast({type="INSTALLER_UPDATE", pkg="TURTLE"})
    print("Waiting 5s for fleet...")
    sleep(5) 
    print("Step 2: Updating Hub...")
    runInstaller("HUB")
    os.reboot()
end

-- Initial Connection
connect()

-- Main Loop
while true do
    -- Capture the full event table
    local event = {os.pullEvent()}
    local eventName = event[1]

    if eventName == "websocket_message" then
        local msg = event[3]
        if msg == "update fleet" then
            coordinateFleetUpdate()
        elseif msg == "version check" then
            rednet.broadcast("SEND_VERSION")
        end

    elseif eventName == "rednet_message" then
        -- Forward turtle data to PC
        safeSend(event[3])

    elseif eventName == "websocket_closed" then
        print("Connection lost. Retrying in 5s...")
        ws = nil
        sleep(5)
        connect()
    end
end
