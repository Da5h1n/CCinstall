local ws_url = "ws://skinnerm.duckdns.org:25565"
local installer_pkg = "HUB"
peripheral.find("modem", rednet.open)

local ws = nil
local active_pairs = {}

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
        local success, err = pcall(function() ws.send(msg) end)
        if not success then print("Send error: " .. err) end
    end
end

-- Function to handle connection with auto-retry
local function connect()
    print("Connecting to PC Dashboard...")
    ws, err = http.websocket(ws_url)
    if not ws then
        print("Failed: " .. tostring(err))
        return false
    end
    print("Connected to WebSocket!")
    
    -- Immediately report Hub status to populate the dashboard
    safeSend({
        type = "version_report",
        id = "HUB",
        role = "hub",
        v = "1.0", -- Adjust based on your manifest
        fuel = 0,
        maxFuel = 0
    })
    return true
end

-- Dynamic Pairing Logic
local function refreshPairs()
    print("Scanning for turtles...")
    local miners, chunkies = {}, {}
    active_pairs = {}

    rednet.broadcast("IDENTIFY_TYPE")
    
    -- Wait 2 seconds for turtles to report back via Rednet
    local timer = os.startTimer(2)
    while true do
        local event, id, msg = os.pullEvent()
        if event == "rednet_message" and type(msg) == "table" and msg.type == "version_report" then
            if msg.role == "miner" then table.insert(miners, id)
            elseif msg.role == "chunky" then table.insert(chunkies, id) end
        elseif event == "timer" and id == timer then break end
    end

    -- Match them 1-to-1
    local count = math.min(#miners, #chunkies)
    for i = 1, count do
        table.insert(active_pairs, { miner = miners[i], chunky = chunkies[i] })
    end

    print("Paired " .. count .. " teams.")
    -- Send report to Python/Web Dashboard
    safeSend({ type = "pairs_report", pairs = active_pairs })
end

-- Fleet Update logic
local function coordinateFleetUpdate()
    print("Broadcasting Update to Turtles...")
    rednet.broadcast({type="INSTALLER_UPDATE", pkg="TURTLE"})
    
    print("Waiting 5s for turtles to initiate...")
    sleep(5) 
    
    print("Updating Hub...")
    runInstaller("HUB")
    os.reboot()
end

-- Initial Connection
connect()

-- Main Loop
while true do
    local event = {os.pullEvent()}
    local eventName = event[1]

    if eventName == "websocket_message" then
        local msg = event[3]
        if msg == "update fleet" then
            coordinateFleetUpdate()
        elseif msg == "refresh" then
            refreshPairs()
        elseif msg == "version check" then
            rednet.broadcast("IDENTIFY_TYPE") -- Re-use identify to trigger reports
        end

    elseif eventName == "rednet_message" then
        -- Forward turtle version/status data to the Dashboard
        safeSend(event[3])

    elseif eventName == "websocket_closed" then
        print("Connection lost. Retrying in 5s...")
        ws = nil
        sleep(5)
        connect()
    end
end
