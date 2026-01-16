local myID = os.getComputerID()
local version_protocol = "fleet_status"
local myState = "idle"
local hubID = nil
local lastKnownPos = {x = 0, y = 0, z = 0, facing = "unknown"}

-- Reset rednet to ensure a clean state
rednet.close()
peripheral.find("modem", rednet.open)


local function getRole()
    -- 1. Check for Chunkloader (Standard Peripheral)
    local names = peripheral.getNames()
    for _, name in ipairs(names) do
        local pType = peripheral.getType(name)
        if pType and pType:find("chunk") then return "chunky" end
    end

    -- 2. Check Equipped Items (The "Hand" check)
    -- We check both hands just in case you equip it on the left
    local hands = { turtle.getEquippedRight(), turtle.getEquippedLeft() }
    
    for _, item in ipairs(hands) do
        if item and item.name then
            local name = item.name:lower()
            if name:find("pickaxe") then return "miner"
            elseif name:find("shovel") then return "excavator"
            elseif name:find("axe") then return "lumberjack"
            elseif name:find("hoe") then return "farmer"
            elseif name:find("sword") then return "combat"
            end
        end
    end
    return "worker"
end

-- Configuration based on detected role
local myRole = getRole()


local roleNames = {
    miner = "Deep-Core Driller",
    excavator = "Excavation Unit",
    lumberjack = "Forester Unit",
    farmer = "Agricultural Unit",
    chunky = "Support Loader",
    combat = "Security Unit",
    worker = "General Worker"
}

local myName = (roleNames[myRole] or "Unit") .. " " .. myID

-- Set the physical label in Minecraft
os.setComputerLabel(myName)

local function getInventory()
    local inv = {}
    for i = 1, 16 do
        local detail = turtle.getItemDetail(i)
        if detail then
            table.insert(inv, {
                    slot = i,
                    name = detail.name:gsub("minecraft:", ""),
                    count = detail.count
                })
        else
            table.insert(inv, { slot = i, name = "empty", count = 0 })
        end
    end
    return inv
end

local function smartStep(direction)
    local retries = 0
    local oldState = myState
    while not direction() do
        myState = "BLOCKED"
        broadcastStatus(false)

        if retries >= 3 then
            myState = oldState
            return false
        end
        sleep(1)
        retries = retries + 1
    end
    if myState ~= "PARKED" then myState = "MOVING" end
    return true
end

local function getGPSData()
    local x, y, z = gps.locate(2)
    if not x then print("GPS lost! Standing still...") return false end

    lastKnownPos.x, lastKnownPos.y, lastKnownPos.z = x, y, z
    
    if lastKnownPos.facing == "unknown" then
        local moveSuccess = false
        local movedUp = false
        local turns = 0

        while not moveSuccess and turns < 4 do
            if not turtle.detect() then
                moveSuccess = turtle.forward()
            elseif not turtle.detectUp() then
                moveSuccess = turtle.up()
                movedUp = true
            else
                turtle.turnRight()
                turns = turns + 1
            end
        end

        if moveSuccess then
            local x2, y2, z2 = gps.locate(2)
            if x2 then
                local detFacing = "unknown"
                if x2 > x then lastKnownPos.facing = "east"
                elseif x2 < x then lastKnownPos.facing = "west"
                elseif z2 > z then lastKnownPos.facing = "south"
                elseif z2 < z then lastKnownPos.facing = "north"
                end

                local dirs = {"north", "east", "south", "west"}
                local currentIdx = 1
                for i, v in ipairs(dirs) do if v == detFacing then currentIdx = i end end

                local originalIdx = (currentIdx - turns - 1) % 4 + 1
                lastKnownPos.facing = dirs[originalIdx]
            end

            if movedUp then turtle.down() else turtle.back() end
        end

        for i = 1, turns do turtle.turnLeft() end
    end
    return true
end

local function getDirID(facing)
    local mapping = { north = 0, east = 1, south = 2, west = 3}
    return mapping[facing] or "????"
end

local function getStatusReport(checkGPS)
    if checkGPS then getGPSData() end

    local version = "0"
    if fs.exists("/.installer/versions.json") then
        local f = fs.open("/.installer/versions.json", "r")
        local data = textutils.unserialiseJSON(f.readAll())
        f.close()
        version = (data and data["TURTLE"]) and data["TURTLE"].version or "?"
    end

    return {
        type = "version_report",
        id = myID,
        name = myName,
        role = myRole,
        v = version,
        state = myState,
        fuel = turtle.getFuelLevel(),
        maxFuel = turtle.getFuelLimit(),
        inventory = getInventory(),
        pos = lastKnownPos,
        dir = getDirID(lastKnownPos.facing)
    }
end

local function broadcastStatus(fullScan)
    rednet.broadcast(getStatusReport(fullScan), version_protocol)
end

local function faceDirection(dir)
    local directions = {"north", "east", "south", "west"}
    local function getDirIdx(d)
        for i, v in ipairs(directions) do if v == d then return i end end
        return 1
    end

    if lastKnownPos.facing == "unknown" then getGPSData() end

    while lastKnownPos.facing ~= dir do
        turtle.turnRight()
        local curIdx = getDirIdx(lastKnownPos.facing)
        local nextIdx = (curIdx % 4) + 1
        lastKnownPos.facing = directions[nextIdx]
    end
end

local function gotoCoords(tx, ty, tz)
    myState = "traveling"
    targetPos = {x = tx, y = ty, z = tz}
    broadcastStatus(false)

    -- flight level
    while lastKnownPos.y < ty + 2 do
        if smartStep(turtle.up) then lastKnownPos.y = lastKnownPos.y + 1 else break end
    end

    -- X alignment
    while lastKnownPos.x ~= tx do
        faceDirection(lastKnownPos.x < tx and "east" or "west")
        if smartStep(turtle.forward) then
            lastKnownPos.x = (lastKnownPos.x < tx) and lastKnownPos.x + 1 or lastKnownPos.x - 1 
        end
        if math.abs(lastKnownPos.x % 5) == 0 then broadcastStatus(false) end
    end

    -- Z alignment
    while lastKnownPos.z ~= tz do
        faceDirection(lastKnownPos.z < tz and "south" or "north")
        if smartStep(turtle.forward) then
            lastKnownPos.z = (lastKnownPos.z < tz) and lastKnownPos.z + 1 or lastKnownPos.z - 1
        end
        if math.abs(lastKnownPos.z % 5) == 0 then broadcastStatus(false) end
    end

    -- Y desent
    while lastKnownPos.y > ty do
        if smartStep(turtle.down) then lastKnownPos.y = lastKnownPos.y - 1 else break end
    end

    myState = "parked"
    targetPos = nil
    broadcastStatus(false)
    
end

local function mineTo(tx, ty, tz)
    local function moveAndSync(moveFunc, axis, delta)
        if moveFunc() then
            local nx, ny, nz = gps.locate(2)
            if nx then
                lastKnownPos.x, lastKnownPos.y, lastKnownPos.z = nx, ny, nz
            else
                lastKnownPos[axis] = lastKnownPos[axis] + delta
            end
            broadcastStatus(false)
            return true
        end
        return false
    end

    while lastKnownPos.y < ty do
        while turtle.detectUp() do turtle.digUp() end
        moveAndSync(turtle.up, "y", 1)
    end
    while lastKnownPos.y > ty do
        while turtle.detectDown() do turtle.digDown() end
        moveAndSync(turtle.down, "y", -1)
    end

    local dx = tx - lastKnownPos.x
    local dz = tz - lastKnownPos.z

    if dx ~= 0 then
        faceDirection(dx > 0 and "east" or "west")
        while turtle.detect() do turtle.dig() end
        moveAndSync(turtle.forward, "x", (dx > 0 and 1 or -1))
    elseif dz ~= 0 then
        faceDirection(dz > 0 and "south" or "north")
        while turtle.detect() do turtle.dig() end
        moveAndSync(turtle.forward, "z", (dz > 0 and 1 or -1))
    end
end

local function executeCoordMission(msg)
    myState = "mining"
    broadcastStatus(false)

    gotoCoords(msg.waypoints.mine_down.x, msg.y_level, msg.waypoints.mine_down.z)
    lastKnownPos = getGPSData()

    for i, coord in ipairs(msg.queue) do
        if turtle.getFuelLevel() < 100 then break end
        if turtle.getItemCount(16) > 0 then break end

        mineTo(coord.x, coord.y, coord.z)

        if i % 10 == 0 then broadcastStatus(false) end
    end

    myState = "returning"
    gotoCoords(msg.waypoints.mine_up.x, msg.y_level + 1, msg.waypoints.mine_up.z)

    gotoCoords(msg.waypoints.item_drop.x, msg.waypoints.item_drop.y, msg.waypoints.item_drop.z)
    for i = 1, 16 do
        turtle.select(i)
        turtle.drop()
    end
    turtle.select(1)
    myState = "idle"
end

-- --- MAIN BOOT ---
local heartbeatTimer = os.startTimer(20)
print("Initializing system...")
broadcastStatus(true)
print("Booted: " .. myName)

while true do
    local event, id, msg, protocol = os.pullEvent()

    if event == "timer" and id == heartbeatTimer then
        broadcastStatus(false)
        heartbeatTimer = os.startTimer(20)
    
    elseif event == "turtle_inventory" then
        broadcastStatus(false)

    elseif event == "rednet_message" and protocol == version_protocol then
        hubID = id
        local command = ""
        local msgType = ""
        local whitelist = nil

        if type(msg) == "table" then
            command = msg.cmd or msg.command or ""
            msgType = msg.type or ""
            whitelist = msg.whitelist
        else
            command = tostring(msg)
        end

        local isAllowed = true
        if whitelist then
            isAllowed = false
            for _, allowedID in ipairs(whitelist) do
                if tonumber(allowedID) == myID then
                    isAllowed = true
                    break
                end
            end
        end

        if isAllowed then
            if msgType == "INSTALLER_UPDATE" then
                print("Update signal received...")
                rednet.send(id, {type = "turtle_response", id = myID, content = "Update starting..."}, version_protocol)
                
                -- Ensure we use an absolute path to the root
                local installerPath = "/installer"
                
                if not fs.exists(installerPath) then
                    print("Downloading installer...")
                    -- Force download to the root
                    shell.run("pastebin", "get", "S3HkJqdw", installerPath)
                end

                -- Final check before execution
                if fs.exists(installerPath) then
                    print("Running: " .. installerPath)
                    -- Use the absolute path to avoid "no such program"
                    shell.run(installerPath, "update", msg.pkg or "TURTLE")
                    
                    rednet.send(id, {type = "update_complete", id = myID}, version_protocol)
                    sleep(1)
                    os.reboot()
                else
                    print("Error: Installer not found!")
                    rednet.send(id, {type = "turtle_response", id = myID, content = "Update failed: No installer file"}, version_protocol)
                end

            elseif command == "IDENTIFY_TYPE" then
                getGPSData()
                broadcastStatus(true)

            elseif command == "SEND_VERSION" then
                broadcastStatus(false)

            elseif msgType == "RECALL_POSITION" then
                print("Parking at: ".. msg.x .. ", " .. msg.z)
                gotoCoords(msg.x, msg.y, msg.z)
                faceDirection("east")
                myState = "PARKED"
                broadcastStatus(false)

            elseif msgType == "COORD_MISSION" then
                executeCoordMission(msg)
                rednet.send(hubID, "request_parking", version_protocol)

            elseif msgType == "MINER_STEP" and myRole == "chunky" then
                print("Shadowing partner...")
                gotoCoords(msg.x, msg.y, msg.z)

            elseif msgType == "DIRECT_COMMAND" or command ~= "" then
                local executeCmd = (msgType == "DIRECT_COMMAND") and command or command
                print("Exec: " .. executeCmd)
                myState = "BUSY"
                broadcastStatus(false)

                pcall(function() shell.run(executeCmd) end)

                myState = "IDLE"
                broadcastStatus(false)
            end
        end
    end
end
