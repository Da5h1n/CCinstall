local ws_url = "ws://192.168.0.62:25565"
local version_protocol = "fleet_status" 
peripheral.find("modem", rednet.open)

local ws = nil
local fleet_cache = {}
local fleet_roles = {}
local fleet_pairs = {}

local refuel_queue = {}
local current_refueler = nil

local OFFSETS = {
    mine_down  = {x = 3, y = 0, z = -5},
    mine_up    = {x = 3, y = 0, z = -4},
    fuel_chest = {x = 6, y = 1, z = -5},
    item_drop  = {x = 6, y = 1, z = -4},
    ground_y = 0
}

local function getHubPos()
    local x, y, z = gps.locate(2)
    if not x then
        print("Error: Hub cannot find GPS location!")
        return nil
    end
    return {x = x, y = y, z = z}
end

local function getAbsoluteWaypoints()
    local h = getHubPos()
    if not h then return nil end

    return {
        mine_down    = {x = h.x + OFFSETS.mine_down.x,  z = h.z + OFFSETS.mine_down.z},
        mine_up      = {x = h.x + OFFSETS.mine_up.x,    z = h.z + OFFSETS.mine_up.z},
        fuel_chest   = {x = h.x + OFFSETS.fuel_chest.x, y = h.y + OFFSETS.fuel_chest.y,  z = h.z + OFFSETS.fuel_chest.z},
        item_drop    = {x = h.x + OFFSETS.item_drop.x,  y = h.y + OFFSETS.item_drop.y,   z = h.z + OFFSETS.item_drop.z},
        ground_y     = h.y + OFFSETS.ground_y
    }
end

local function safeSend(data)
    if ws then
        local msg = type(data) == "table" and textutils.serializeJSON(data) or tostring(data)
        local success = pcall(function () ws.send(msg) end)
        if not success then
            print("Send failed. Closing socket.")
            ws.close()
            ws = nil
        end
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

            local hPos = getHubPos()

                -- 1. Identify HUB to Dashboard
            safeSend({
                type = "version_report", 
                id = "HUB", 
                name = "Central Command Hub", 
                role = "hub", 
                v = getHubVersion(), 
                fuel = 0, 
                maxFuel = 0,
                pos = hPos
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

local function updatePairs()
    local miners = {}
    local chunky = {}

    for id, role in pairs(fleet_roles) do
        local numericID = tonumber(id)
        if numericID then
            if role == "miner" then table.insert(miners, numericID)
            elseif role == "chunky" then table.insert(chunky, numericID) end
        end
    end

    table.sort(miners)
    table.sort(chunky)

    fleet_pairs = {}
    local pairCount = math.min(#miners, #chunky)
    for i = 1, pairCount do
        fleet_pairs[tostring(miners[i])] = tostring(chunky[i])
    end

    safeSend({
        type = "pairs_report",
        pairs = fleet_pairs,
        count = pairCount
    })
    print("Pairs Synced: " .. pairCount)
end

local function coordinateFleetUpdate(whitelist)
    if not whitelist or #whitelist == 0 then return end
    print("Starting Staggered Update for " .. #whitelist .. " units...")

    for _, id in ipairs(whitelist) do
        print("Updating Turtle " .. id)
        rednet.send(id, {type="INSTALLER_UPDATE", command="INSTALLER_UPDATE", pkg="TURTLE"}, version_protocol)

        local timeout = os.startTimer(60)
        while true do
            local event, rid, msg, protocol = os.pullEvent()
            if event == "rednet_message" and rid == id and protocol == version_protocol then
                if type(msg) == "table" then
                    if msg.type == "update_complete" then
                        print("Turtle " .. id .. " Update Success.")
                        safeSend({type="turtle_response", id=id, content="Update success."})
                        break
                    elseif msg.type == "turtle_response" and msg.content:find("fail") then
                        print("Turtle " .. id .. ": ERROR - " .. msg.content)
                        break
                    end
                end
            elseif event == "timer" and rid == timeout then
                print("Warning: Turtle " .. id .. ": TIMEOUT. Skipping...")
                break
            end
        end
        sleep(2)
    end

    print("All fleet updates processed. Updating Hub...")
    shell.run("installer", "update", "HUB")
    os.reboot()
end

local function processRefuelQueue()
    if current_refueler == nil and #refuel_queue > 0 then
        local nextID = table.remove(refuel_queue, 1)
        local waypoints = getAbsoluteWaypoints()

        if waypoints then
            current_refueler = nextID
            print("Refuel Station Clear. Sending Turtle " .. nextID)
            rednet.send(nextID, { type = "REFUEL_ORDER", waypoints = waypoints }, version_protocol)
            safeSend({type="turtle_response", id=nextID, content="Proceeding to refuel station."})
        end
    end
end

local function sendParkingOrder(id)
    local hubPos = getHubPos()
    if not hubPos then return end

    local role = fleet_roles[id] or "worker"
    local roleLineMap = { chunky=1, miner=2, excavator=3, lumberjack=4, farmer=5, worker=6 }
    local lineNum = roleLineMap[role] or 7


    local slotNum = 0
    local sortedIDs = {}
    for cid, crole in pairs(fleet_roles) do
        if crole == role then table.insert(sortedIDs, cid) end
    end
    table.sort(sortedIDs)

    for i, cid in ipairs(sortedIDs) do
        if cid == id then
            slotNum = i - 1
            break
        end
    end

    local tx = hubPos.x - 2 - slotNum
    local ty = hubPos.y
    local tz = hubPos.z - 2 - ((lineNum - 1) * 2)

    rednet.send(id, {
        type = "RECALL_POSITION",
        x = tx, y = ty, z = tz
    }, version_protocol)

    print("Sent individual parking order to " .. id)
end

local function relayTargetCommand(targetID, command, whitelist)
    if targetID == "broadcast" then
        print("Broadcasting CMD ["..command.."] to all units.")
        rednet.broadcast({
            type = "DIRECT_COMMAND",
            cmd = command,
            whitelist = whitelist
        }, version_protocol)
    else
        local id = tonumber(targetID)
        if id then
            print("Relaying CMD ["..command.."] to Turtle " .. targetID)
            rednet.send(id, {
                type = "DIRECT_COMMAND",
                cmd = command
            }, version_protocol)
        else
            print("Error: Invalid Target ID: " .. tostring(targetID))
        end
    end
end

local function generateStripQueue(startX, startY, startZ, distance)
    local queue = {}

    for i = 0, distance - 1 do
        local cz = startZ - i

        table.insert(queue, {x = startX, y = startY, z = cz})
        table.insert(queue, {x = startX, y = startY + 1, z = cz})

        if i % 4 == 0 then
            -- west branch
            table.insert(queue, {x = startX - 1, y = startY, z = cz})
            table.insert(queue, {x = startX - 1, y = startY + 1, z = cz})

            -- East branch
            table.insert(queue, {x = startX + 1, y = startY, z = cz})
            table.insert(queue, {x = startX + 1, y = startY + 1, z = cz})

            -- Bottom
            table.insert(queue, {x = startX, y = startY - 1, z = cz})
        end
    end
    return queue
end

-- --- MAIN BOOT ---

connect()

local hubHeartbeat = os.startTimer(15)

while true do
    local event, p1, p2, p3 = os.pullEvent()

    -- handle dashboard Comamnds
    if event == "websocket_message" then
        local raw = p2
        local success, msg = pcall(textutils.unserializeJSON, raw)

        if success and type(msg) == "table" then

            if msg.protocol == "fleet_ack" then
                if msg.target and msg.target ~= "HUB" then
                    rednet.send(tonumber(msg.target), "ACK", "fleet_ack")
                end
                
            elseif msg.type == "INSTALLER_UPDATE" then
                print("Starting Fleet Update Process...")
                coordinateFleetUpdate(msg.whitelist)

            elseif msg.target and msg.target ~= "HUB" then
                local cmd = tostring(msg.command or msg.type or "")
                relayTargetCommand(msg.target, cmd, msg.whitelist)

            elseif msg.type == "scan_nearby" then
                local side = "right"
                local geo = peripheral.wrap(side)
                if geo then
                    local radius = 8
                    local blocks = {}
                    local scandata = geo.scan(radius)

                    if scandata then 
                        local blocks_to_send = {}

                        local hubX, hubY, hubZ = gps.locate()
                        hubX = hubX or 0
                        hubY = hubY or 0
                        hubZ = hubZ or 0

                        -- offset logic
                        local offX, offY, offZ = 0, 0, 0
                        if side == "right" then offX = 1
                        elseif side == "left" then offX = -1
                        elseif side == "top" then offY = 1
                        elseif side == "bottom" then offY = -1
                        elseif side == "front" then offZ = -1
                        elseif side == "back" then offZ = 1
                        end

                        for _, block in pairs(scandata) do
                            if block.name ~= "minecraft:air" then
                                local cleanTags = {}
                                if block.tags then
                                    for tag, value in pairs(block.tags) do
                                        cleanTags[tag] = value
                                    end
                                end

                                table.insert(blocks_to_send, {
                                    x = hubX + offX + block.x,
                                    y = hubY + offY + block.y,
                                    z = hubZ + offZ + block.z,
                                    name = block.name,
                                    tags = cleanTags
                                })
                            end
                        end

                        local chunkSize = 250
                        for i = 1, #blocks_to_send, chunkSize do
                            local chunk = {}
                            for j = i, math.min(i + chunkSize - 1, #blocks_to_send) do
                                table.insert(chunk, blocks_to_send[j])
                            end

                            local response = {
                                type = "world_update",
                                id = os.getComputerID(),
                                blocks = chunk,
                                part = math.floor(i/chunkSize) + 1,
                                total_parts = math.ceil(#blocks_to_send / chunkSize)
                            }

                            ws.send(textutils.serializeJSON(response))
                            sleep(0.05)
                        end
                        print("Scan complete: Sent " .. #blocks_to_send .. " blocks.")
                    end
                else
                    print("No Geoscanner found on Right side.")
                    local err = {type="turtle_response", id=os.getComputerID(), content="Error: No Geo Scanner found"}
                    ws.send(textutils.serializeJSON(err))
                end

            else
                local cmd = tostring(msg.command or msg.type or "")
                print("Hub Command Recieved: " .. cmd)

                if cmd == "reboot" then
                    os.reboot()

                elseif cmd == "refresh" then
                    fleet_cache = {}
                    fleet_roles = {}
                    print("Broadcasting Global Refresh...")
                    rednet.broadcast("IDENTIFY_TYPE", version_protocol)
                    sleep(1)
                    updatePairs()

                elseif cmd == "recall" then
                    local hubPos = getHubPos()
                    if hubPos then
                        print("Calculating formation positions...")
                        local counters = { chunky=0, miner=0, excavator=0, lumberjack=0, farmer=0, worker=0 }
                        local roleLineMap = { chunky=1, miner=2, excavator=3, lumberjack=4, farmer=5, worker=6 }
                        local sortedIDs = {}
                        for id, _ in pairs(fleet_cache) do table.insert(sortedIDs, id) end
                        table.sort(sortedIDs)

                        for _, id in ipairs(sortedIDs) do
                            local role = fleet_roles[id] or "worker"
                            local lineNum = roleLineMap[role] or 7
                            local slotNum = counters[role] or 0
                            local tx = hubPos.x - 2 - slotNum
                            local ty = hubPos.y
                            local tz = hubPos.z - 2 - ((lineNum - 1) * 2)

                            rednet.send(id, { type = "RECALL_POSITION", x = tx, y = ty, z = tz}, version_protocol)
                            counters[role] = (counters[role] or 0) + 1
                        end
                        safeSend({type="turtle_response", id="HUB", content="Formation orders sent."})
                    end
                elseif cmd == "start_mining" then
                    local waypoints = getAbsoluteWaypoints()
                    if waypoints then
                        local miners = {}
                        for id, role in pairs(fleet_roles) do
                            if role == "miner" then table.insert(miners, id) end
                        end
                        table.sort(miners)

                        for i, minerID in ipairs(miners) do
                            local startX = waypoints.mine_down.x + ((i - 1) * 3)
                            local startY = tonumber(msg.y_level) or 30
                            local dist = tonumber(msg.distance) or 32
                            local startZ = waypoints.mine_down.z

                            local jobQueue = generateStripQueue(startX, startY, startZ, dist)

                            rednet.send(minerID, {
                                type = "COORD_MISSION",
                                queue = jobQueue,
                                waypoints = waypoints,
                                y_level = startY
                            }, version_protocol)
                            print("Mission dispached to " .. minerID)
                        end
                    end
                end
            end
        else
            print("Error: Recieved malformed JSON from Dashboard")
        end

        -- handle rednet messages
    elseif event == "rednet_message" then
        local senderID, message, protocol = p1, p2, p3
        if protocol == version_protocol then
            safeSend(message)
            if type(message) == "table" then
                    
                local isNew = fleet_cache[senderID] == nil

                fleet_cache[senderID] = true
                if message.role then fleet_roles[senderID] = message.role end

                safeSend(message)
                if isNew then updatePairs() end

                if message.lowFuel then
                    local state = tostring(message.state or ""):lower()
                    local alreadyInQueue = false
                    for _, qID in ipairs(refuel_queue) do if qID == senderID then alreadyInQueue = true end end

                    if not alreadyInQueue and current_refueler ~= senderID then
                        if state == "idle" or state == "parked" then
                            table.insert(refuel_queue, senderID)
                            print("Turtle " .. senderID .. " added to refuel queue. Position: " .. #refuel_queue)
                        end
                    end
                end

                if senderID == current_refueler and tostring(message.state or ""):lower() == "parked" then
                    current_refueler = nil
                    print("Turtle " .. senderID .. " has finished refueling and parked.")
                end
                processRefuelQueue()

            elseif message == "request_parking" then
                print("Turtle " .. senderID .. " requested parking.")
                sendParkingOrder(senderID)
            end
        end
        -- Heartbeat timer
    elseif event == "timer" and p1 == hubHeartbeat then
        local hPos = getHubPos()
        safeSend({type = "version_report", id = "HUB", name = "Central Command Hub", role = "hub", v = getHubVersion(), pos = hPos, online = true})
        hubHeartbeat = os.startTimer(15)

    -- RECONECT LOGIC
    elseif event == "websocket_closed" then
        print("Websocket lost! Reconnecting...")
        ws = nil
        connect()
    end
end
