local ws_url = "ws://skinnerm.duckdns.org:25565"
local version_protocol = "fleet_status" 
peripheral.find("modem", rednet.open)

local ws = nil
local active_pairs = {}
local fleet_cache = {} 

local function safeSend(data)
    if ws then
        local msg = type(data) == "table" and textutils.serializeJSON(data) or tostring(data)
        pcall(function() ws.send(msg) end)
    end
end

local function getHubVersion()
    local path = "/.installer/versions.json"
    if fs.exists(path) then
        local f = fs.open(path, "r")
        local content = f.readAll()
        f.close()
        local data = textutils.unserializeJSON(content)
        -- Accessing the dynamic version from the installer's JSON
        return (data and data["HUB"]) and data["HUB"].version or "?"
    end
    return "unknown"
end

local function connect()
    print("Connecting to PC Dashboard...")
    ws, err = http.websocket(ws_url)
    if not ws then 
        print("Connection Failed: " .. tostring(err)) 
        return false 
    end
    
    print("Connected!")
    
    -- 1. Identify self to Dashboard
    safeSend({
        type = "version_report", 
        id = "HUB", 
        name = "Central Command Hub", 
        role = "hub", 
        v = getHubVersion(), 
        fuel = 0, 
        maxFuel = 0
    })

    -- 2. FORCE REFRESH: Tell all turtles to report in immediately
    -- This populates the dashboard instantly after a Hub reboot
    print("Requesting fleet status...")
    rednet.broadcast("IDENTIFY_TYPE", version_protocol)
    
    return true
end

local function coordinateFleetUpdate()
    local pending = {}
    local count = 0
    -- Use the cache built from the last "Refresh" or automatic check-ins
    for id, _ in pairs(fleet_cache) do
        pending[id] = true
        count = count + 1
    end

    if count == 0 then
        print("No turtles in cache. Try refreshing first.")
    end

    print("Updating Fleet. Waiting for " .. count .. " units...")
    rednet.broadcast({type="INSTALLER_UPDATE", pkg="TURTLE"}, version_protocol)
    
    local timeout = os.startTimer(60)
    while count > 0 do
        local event, id, msg, protocol = os.pullEvent()
        if event == "rednet_message" and protocol == version_protocol then
            if type(msg) == "table" and msg.type == "update_complete" then
                if pending[id] then
                    pending[id] = nil
                    count = count - 1
                    print("Turtle " .. id .. " Updated OK. (" .. count .. " left)")
                    safeSend({type="turtle_response", id=id, content="Update success."})
                end
            end
        elseif event == "timer" and id == timeout then
            print("Update timeout reached. Some units may have failed.")
            break
        end
    end

    print("Updating Hub...")
    shell.run("installer", "update", "HUB")
    os.reboot()
end

local function refreshPairs()
    print("Scanning fleet...")
    local miners, chunkies = {}, {}
    fleet_cache = {} 
    
    rednet.broadcast("IDENTIFY_TYPE", version_protocol)
    local timer = os.startTimer(3)
    while true do
        local event, id, msg, protocol = os.pullEvent()
        if event == "rednet_message" and protocol == version_protocol then
            if type(msg) == "table" and msg.type == "version_report" then
                fleet_cache[id] = true 
                if msg.role == "miner" then table.insert(miners, id)
                elseif msg.role == "chunky" then table.insert(chunkies, id) end
                safeSend(msg) -- Forward each status report to the Web UI
            end
        elseif event == "timer" and id == timer then break end
    end

    active_pairs = {}
    for i = 1, math.min(#miners, #chunkies) do
        table.insert(active_pairs, { miner = miners[i], chunky = chunkies[i] })
    end
    safeSend({ type = "pairs_report", pairs = active_pairs })
    print("Pairs synced.")
end

-- Initial startup
connect()

while true do
    local event = {os.pullEvent()}
    
    -- Handle Web Dashboard Commands
    if event[1] == "websocket_message" then
        local msg = event[3]
        if msg == "update fleet" then 
            coordinateFleetUpdate()
        elseif msg == "refresh" then 
            refreshPairs()
        elseif msg == "recall" then
            print("Dashboard command: RECALL ALL")
            rednet.broadcast({type = "RECALL"}, version_protocol)
            safeSend({type="turtle_response", id="HUB", content="Recall signal sent to fleet."})
        end

    -- Handle Turtle Check-ins
    elseif event[1] == "rednet_message" then
        local senderID = event[2]
        local message = event[3]
        local protocol = event[4]

        if protocol == version_protocol and type(message) == "table" then
            -- Store turtle in cache so we know they exist for updates
            fleet_cache[senderID] = true
            -- Forward any turtle reports (status, fuel, version) to the Web UI
            safeSend(message)
        end

    -- Auto-reconnect if websocket drops
    elseif event[1] == "websocket_closed" then
        print("Websocket lost. Retrying in 5s...")
        sleep(5)
        connect()
    end
end
