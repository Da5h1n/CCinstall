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
        local data = textutils.unserialiseJSON(f.readAll())
        f.close()
        return (data and data["HUB"]) and data["HUB"].version or "?"
    end
    return "unknown"
end

local function connect()
    print("Connecting to PC...")
    ws, err = http.websocket(ws_url)
    if not ws then print("Failed: " .. tostring(err)) return false end
    print("Connected!")
    safeSend({type="version_report", id="HUB", name="Central Command Hub", role="hub", v=getHubVersion(), fuel=0, maxFuel=0})
    return true
end

local function coordinateFleetUpdate()
    local pending = {}
    local count = 0
    -- Use the cache built from the last "Refresh"
    for id, _ in pairs(fleet_cache) do
        pending[id] = true
        count = count + 1
    end

    if count == 0 then
        print("No turtles in cache. Refresh first?")
    end

    print("Updating Fleet. Waiting for " .. count .. " confirmations...")
    rednet.broadcast({type="INSTALLER_UPDATE", pkg="TURTLE"}, version_protocol)
    
    local timeout = os.startTimer(60)
    while count > 0 do
        local event, id, msg, protocol = os.pullEvent()
        if event == "rednet_message" and protocol == version_protocol then
            if type(msg) == "table" and msg.type == "update_complete" then
                if pending[id] then
                    pending[id] = nil
                    count = count - 1
                    print("Turtle " .. id .. " OK. (" .. count .. " left)")
                    safeSend({type="turtle_response", id=id, content="Update success."})
                end
            end
        elseif event == "timer" and id == timeout then
            print("Timeout reached.")
            break
        end
    end

    print("Updating Hub...")
    shell.run("installer", "update", "HUB")
    os.reboot()
end

local function refreshPairs()
    print("Scanning...")
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
                safeSend(msg) -- Forward status to UI
            end
        elseif event == "timer" and id == timer then break end
    end

    active_pairs = {}
    for i = 1, math.min(#miners, #chunkies) do
        table.insert(active_pairs, { miner = miners[i], chunky = chunkies[i] })
    end
    safeSend({ type = "pairs_report", pairs = active_pairs })
end

connect()

while true do
    local event = {os.pullEvent()}
    if event[1] == "websocket_message" then
        local msg = event[3]
        if msg == "update fleet" then coordinateFleetUpdate()
        elseif msg == "refresh" then refreshPairs()
        end
    elseif event[1] == "rednet_message" then
        if event[4] == version_protocol and type(event[3]) == "table" then
            if event[3].type == "version_report" then
                fleet_cache[event[2]] = true
            end
            safeSend(event[3])
        end
    elseif event[1] == "websocket_closed" then
        sleep(5)
        connect()
    end
end
