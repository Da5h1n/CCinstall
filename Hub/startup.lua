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
    while true do
        print("Connecting to PC Dashboard...")
        local socket, err = http.websocket(ws_url)

        if socket then
            print("Connected!")
            ws = socket

                -- 1. Identify HUB to Dashboard
            safeSend({
                type = "version_report", 
                id = "HUB", 
                name = "Central Command Hub", 
                role = "hub", 
                v = getHubVersion(), 
                fuel = 0, 
                maxFuel = 0
            })

            print("Requesting fleet status...")
            rednet.broadcast("IDENTIFY_TYPE", version_protocol)
            return true
        else
            print("Connection Failed: " ..tostring(err))
            print("Retrying in 5 seconds...")
            sleep(5)
        end
    end
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

-- Initial startup
connect()

local hubHeartbeat = os.startTimer(15)

while true do
    local event, p1, p2, p3 = os.pullEvent()
    
    -- Handle Web Dashboard Commands
    if event == "websocket_message" then
        local msg = p2
        print("Web CMD: " .. tostring(msg))

        if msg == "update fleet" then 
            coordinateFleetUpdate()
        elseif msg == "refresh" then 
            print("Broadcasting Global Refresh...")
            rednet.broadcast("IDENTIFY_TYPE", version_protocol)
        elseif msg == "recall" then
            print("Broadcasting: RECALL")
            rednet.broadcast({type = "RECALL"}, version_protocol)
            safeSend({type="turtle_response", id="HUB", content="Recall signal sent to fleet."})
        end

    -- Handle Turtle Check-ins
    elseif event == "rednet_message" then
        local senderID, message, protocol = p1, p2, p3

        if protocol == version_protocol and type(message) == "table" then
            -- Store turtle in cache so we know they exist for updates
            fleet_cache[senderID] = true
            -- Forward any turtle reports (status, fuel, version) to the Web UI
            if not safeSend(message) then
                print("Warning: Web UI link down. Report cashed locally.")
            end
        end

    elseif event == "timer" and p1 == hubHeartbeat then

        safeSend({
            type = "version_report",
            id = "HUB",
            name = "Central Command Hub",
            role = "hub",
            v = getHubVersion(),
            online = true
        })
        hubHeartbeat = os.startTimer(15)

    -- Auto-reconnect if websocket drops
    elseif event == "websocket_closed" then
        print("Websocket lost!")
        ws = nil
        connect()
    end
end
