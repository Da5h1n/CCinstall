--FORWARD DECLARATION
local saveSettings, loadSettings, updateFacing
local getRole, getInventory, getDirID
local getStatusReport, broadcastStatus
local syncMove, syncTurn, turnRight, turnLeft, smartStep
local getGPSData, faceDirection, gotoCoords
local mineTo, executeCoordMission

-- VARIABLES
local myID = os.getComputerID()
local version_protocol = "fleet_status"
local myState = "IDLE"
local hubID = nil
local SETTINGS_FILE = "/.unit_data.json"

local function saveSettings(data)
    local f = fs.open(SETTINGS_FILE, "w")
    f.write(textutils.serialiseJSON(data))
    f.close()
end

local function loadSettings()
    local defaultValues = {
        facing = "unknown"
    }

    if not fs.exists(SETTINGS_FILE) then
        return defaultValues
    end

    local f = fs.open(SETTINGS_FILE, "r")
    local content = f.readAll()
    f.close()

    local data = textutils.unserializeJSON(content)
    return data or defaultValues
end

local memory = loadSettings()
local lastKnownPos = {
    x = 0,
    y = 0,
    z = 0,
    facing = memory.facing
}

-- Reset rednet to ensure a clean state
rednet.close()
peripheral.find("modem", rednet.open)

local function updateFacing(newFacing)
    lastKnownPos.facing = newFacing
    memory.facing = newFacing
    saveSettings(memory)
end

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

getDirID = function(facing)
    local mapping = { north = 0, east = 1, south = 2, west = 3}
    return mapping[facing] or "????"
end

local function getStatusReport(checkGPS)
    if checkGPS then getGPSData() end

    local currentFuel = turtle.getFuelLevel()
    local fuelLimit = turtle.getFuelLimit()

    local isLow = (currentFuel < 1000) or (currentFuel < (fuelLimit * 0.1))

    local version = "0"
    if fs.exists("/.installer/versions.json") then
        local f = fs.open("/.installer/versions.json", "r")
        local data = textutils.unserializeJSON(f.readAll())
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
        fuel = currentFuel,
        maxFuel = fuelLimit,
        lowFuel = isLow,
        inventory = getInventory(),
        pos = lastKnownPos,
        dir = getDirID(lastKnownPos.facing)
    }
end

local function broadcastStatus(fullScan)
    local report = getStatusReport(fullScan)
    local success = false
    local retries = 0

    while not success and retries < 3 do
        if hubID then
            rednet.send(hubID, report, version_protocol)
        else
            rednet.broadcast(report, version_protocol)
        end

        local id, msg = rednet.receive("fleet_ack", 0.5)
        if id then
            success = true
        else
            retries = retries + 1
            sleep(0.1)
        end
    end
end

function reportWorld(relDir)
    local success, data = nil, nil
    if relDir == "forward" then success, data = turtle.inspect()
    elseif relDir == "up" then success, data = turtle.inspectUp()
    elseif relDir == "down" then success, data = turtle.inspectDown()
    end

    if success then
        local bx, by, bz = lastKnownPos.x, lastKnownPos.y, lastKnownPos.z
        local f = lastKnownPos.facing

        if relDir == "up" then by = by + 1
        elseif relDir == "down" then by = by - 1
        elseif relDir == "forward" then
            if f == "north" then bz = bz - 1
            elseif f == "south" then bz = bz + 1
            elseif f == "east"  then bx = bx + 1
            elseif f == "west"  then bx = bx - 1
            end
        end

        rednet.broadcast({
            type = "world_update",
            id = myID,
            blocks = {{x = bx, y = by, z = bz, name = data.name}}
        }, version_protocol)
    end
end

function activeScan()
    reportWorld("up")
    reportWorld("down")

    for i = 1, 4 do
        reportWorld("forward")
        turnRight()
    end
end

function syncMove(moveFunc, direction)

    if turtle.getFuelLevel() == 0 then
        myState = "NO_FUEL"
        broadcastStatus(false)
        print("CRITICAL: Out of fuel!")
        return false
    end

    if moveFunc() then
        if direction == "up" then
            lastKnownPos.y = lastKnownPos.y + 1

        elseif direction == "down" then
            lastKnownPos.y = lastKnownPos.y - 1
        
        elseif direction == "forward" then
            local f = lastKnownPos.facing
            if f == "north" then lastKnownPos.z = lastKnownPos.z - 1
            elseif f == "south" then lastKnownPos.z = lastKnownPos.z + 1
            elseif f == "east" then lastKnownPos.x = lastKnownPos.x + 1
            elseif f == "west" then lastKnownPos.x = lastKnownPos.x - 1
            end
        elseif direction == "back" then
            local f = lastKnownPos.facing
            if f == "north" then lastKnownPos.z = lastKnownPos.z + 1
            elseif f == "south" then lastKnownPos.z = lastKnownPos.z - 1
            elseif f == "east"  then lastKnownPos.x = lastKnownPos.x - 1
            elseif f == "west"  then lastKnownPos.x = lastKnownPos.x + 1
            end
        end

        reportWorld("forward")
        reportWorld("up")
        reportWorld("down")

        broadcastStatus(false)
        return true
    end
    return false
end

function syncTurn(isRight)
    local dirs = {"north", "east", "south", "west"}
    local currentIdx = 1

    for i, v in ipairs(dirs) do 
        if v == lastKnownPos.facing then currentIdx = i end
    end
    
    if isRight then
        turtle.turnRight()
        currentIdx = (currentIdx % 4) + 1
    else
        turtle.turnLeft()
        currentIdx = (currentIdx - 2 + 4) % 4 + 1
    end

    updateFacing(dirs[currentIdx])
    broadcastStatus(false)
end

local function turnRight() syncTurn(true) end
local function turnLeft() syncTurn(false) end

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

getGPSData = function(forceMove)
    local x, y, z = gps.locate(2)
    if not x then print("GPS lost!") return false end

    lastKnownPos.x, lastKnownPos.y, lastKnownPos.z = x, y, z
    
    if lastKnownPos.facing == "unknown" or forceMove then
        print("Calibrating facing...")
        local success = false

        for i = 1, 4 do
            if not turtle.detect() and turtle.forward() then
                local x2, y2, z2 = gps.locate(3)
                if x2 then
                    local detFacing = "unknown"
                    if x2 > x then detFacing = "east"
                    elseif x2 < x then detFacing = "west"
                    elseif z2 > z then detFacing = "south"
                    elseif z2 < z then detFacing = "north"
                    end

                    updateFacing(detFacing)
                    success = true

                    turnRight()
                    turnRight()

                    while not turtle.forward() do
                        turtle.dig()
                        sleep(0.5)
                    end

                    turnRight()
                    turnRight()
                    
                    print("Calibrated: " .. lastKnownPos.facing)
                    break
                end
                turtle.back()
            end
            turnRight()
        end

        if not success then
            print("Calibration Failed: Unit is completely boxed in.")
            return false
        end
    end
    return true
end

local function faceDirection(dir)
    local dirs = {north=1, east=2, south=3, west=4}
    while lastKnownPos.facing ~= dir do
        turnRight()
    end
end

local function gotoCoords(tx, ty, tz)
    myState = "traveling"

    local dist = math.abs(lastKnownPos.x - tx) + math.abs(lastKnownPos.z - tz)

    if dist > 2 then
        while lastKnownPos.y < ty + 2 do
            if not smartStep(function() return syncMove(turtle.up, "up") end) then break end
        end
    end

    local function align(axis, target, pos1, neg1)
        while lastKnownPos[axis] ~= target do
            faceDirection(lastKnownPos[axis] < target and pos1 or neg1)
            if not smartStep(function() return syncMove(turtle.forward, "forward") end) then break end
            broadcastStatus(false)
        end
    end

    align("x", tx, "east", "west")
    align("z", tz, "south", "north")

    while lastKnownPos.y > ty do
        if not smartStep(function() return syncMove(turtle.down, "down") end) then break end
    end
    myState = "IDLE"
end

local function mineTo(tx, ty, tz)
    while lastKnownPos.y < ty do
        while turtle.detectUp() do turtle.digUp() end
        syncMove(turtle.up, "up")
    end
    while lastKnownPos.y > ty do
        while turtle.detectDown() do turtle.digDown() end
        syncMove(turtle.down, "down")
    end

    local dx = tx - lastKnownPos.x
    local dz = tz - lastKnownPos.z

    if dx ~= 0 then
        faceDirection(dx > 0 and "east" or "west")
        while lastKnownPos.x ~= tx do
            while turtle.detect() do turtle.dig() end
            if not syncMove(turtle.forward, "forward") then break end
        end
    end

    if dz ~= 0 then
        faceDirection(dz > 0 and "south" or "north")
        while lastKnownPos.z ~= tz do
            while turtle.detect() do turtle.dig() end
            if not syncMove(turtle.forward, "forward") then break end
        end
    end
    broadcastStatus(false)
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
    myState = "IDLE"
end

local function autoRefuel(waypoints)
    if not waypoints or not waypoints.fuel_chest then
        print("Error No fuel station coordinates")
        return false
    end

    local oldState = myState
    myState = "refueling"
    broadcastStatus(false)

    print("Navigating to Fuel Station...")

    gotoCoords(waypoints.fuel_chest.x - 1, waypoints.fuel_chest.y, waypoints.fuel_chest.z)

    faceDirection("east") -- FRONT TOWARDS CHEST

    local fueled = false
    for i = 1, 16 do
        if turtle.getItemCount(i) == 0 then
            turtle.select(i)
            while turtle.suck() do
                if turtle.refuel(0) then
                    turtle.refuel()
                    fueled = true
                else
                    turtle.drop()
                    break
                end
                if turtle.getFuelLevel() > 1000 then break end
            end
        end
        if fueled then break end
    end

    turtle.select(1)
    myState = "IDLE"
    broadcastStatus(false)
end

-- --- MAIN BOOT ---

print("Initializing system...")
pcall(function() getGPSData(true) end)
broadcastStatus(true)
print("Booted: " .. myName)

local heartbeatTimer = os.startTimer(5)

while true do
    local event, id, msg, protocol = os.pullEvent()

    if event == "timer" and id == heartbeatTimer then
        broadcastStatus(false)
        heartbeatTimer = os.startTimer(5)
    
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
            if command == "INSTALLER_UPDATE" then
                print("Update signal received...")
                rednet.send(id, {type = "turtle_response", id = myID, content = "Starting Update..."}, version_protocol)
                
                local path = "/installer"
                if not fs.exists(path) then
                
                    print("Downloading installer...")
                    local dlSuccess = shell.run("pastebin", "get", "S3HkJqdw", path)
                end
                
                if dlSuccess and fs.exists(path) then
                    print("Executing update...")
                    local pkg = msg.pkg or "TURTLE"

                    local success, err = pcall(function()
                        return shell.run(path, "update", pkg)
                    end)

                    if success then
                        rednet.send(id, {type = "update_complete", id = myID}, version_protocol)
                        sleep(1)
                        os.reboot()
                    else
                        rednet.send(id, {type = "turtle_response", id = myID, content = "Update fail: "..tostring(err)}, version_protocol)
                        print("Update failed: " .. tostring(err))
                    end
                else
                    rednet.send(id, {type = "turtle_response", id = myID, content = "Download failed (Pastebin)", version_protocol})
                    print("Download failed.")
                end

            elseif command == "IDENTIFY_TYPE" then
                getGPSData(true)
                broadcastStatus(true)

            elseif command == "SEND_VERSION" then
                broadcastStatus(false)

            elseif msgType == "REFUEL_ORDER" then
                print("Hub ordered refueling. Clearing station.")
                autoRefuel(msg.waypoints)
                rednet.send(hubID, "request_parking", version_protocol)

            elseif msgType == "RECALL_POSITION" then
                getGPSData(true)
                print("Parking at: ".. msg.x .. ", " .. msg.z)
                gotoCoords(msg.x, msg.y, msg.z)
                faceDirection("east")
                myState = "PARKED"
                broadcastStatus(false)
                print("Unit Parked. Queue station clear.")

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
