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
local myState = "idle"
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

    local data = textutils.unserialiseJSON(content)
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

local function getStatusReport(checkGPS)
    if checkGPS then getGPSData() end

    local currentFuel = turtle.getFuelLevel()
    local fuelLimit = turtle.getFuelLimit()

    local isLow = (currentFuel < 1000) or (currentFuel < (fuelLimit * 0.1))

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
        fuel = currentFuel,
        maxFuel = fuelLimit,
        lowFuel = isLow,
        inventory = getInventory(),
        pos = lastKnownPos,
        dir = getDirID(lastKnownPos.facing)
    }
end

local function broadcastStatus(fullScan)
    rednet.broadcast(getStatusReport(fullScan), version_protocol)
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

local function getGPSData(forceMove)
    local x, y, z = gps.locate(2)
    if not x then print("GPS lost!") return false end

    lastKnownPos.x, lastKnownPos.y, lastKnownPos.z = x, y, z
    
    if lastKnownPos.facing == "unknown" or forceMove then
        print("Calibrating facing...")
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
                print("Blocked... turning...")
                turnRight()
                turns = turns + 1
            end
        end

        if moveSuccess then
            local x2, y2, z2 = gps.locate(2)
            if x2 then
                local detFacing = "unknown"
                if x2 > x then detFacing = "east"
                elseif x2 < x then detFacing = "west"
                elseif z2 > z then detFacing = "south"
                elseif z2 < z then detFacing = "north"
                end

                local dirs = {"north", "east", "south", "west"}
                local currentIdx = 1
                for i, v in ipairs(dirs) do
                    if v == detFacing then
                        currentIdx = i
                    end
                end

                local originalIdx = (currentIdx - turns - 1) % 4 + 1
                updateFacing(dirs[originalIdx])
            end

            if movedUp then turtle.down() else turtle.back() end
        end

        for i = 1, turns do turnLeft() end
    end
    return true
end

local function faceDirection(dir)
    if lastKnownPos.facing == "unknown" then getGPSData() end
    if lastKnownPos.facing == dir then return end

    local dirs = {north=1, east=2, south=3, west=4}
    local start = dirs[lastKnownPos.facing]
    local target = dirs[dir]

    local diff = (target - start + 4) % 4

    if diff == 3 then
        turnLeft()
    else
        for i = 1, diff do
            turnRight()
        end
    end
end

local function gotoCoords(tx, ty, tz)
    myState = "traveling"
    targetPos = {x = tx, y = ty, z = tz}
    broadcastStatus(false)

    -- flight level
    while lastKnownPos.y < ty + 2 do
        if not smartStep(function() return syncMove(turtle.up, "up") end) then
            break
        end
    end

    -- X alignment
    while lastKnownPos.x ~= tx do
        faceDirection(lastKnownPos.x < tx and "east" or "west")
        if not smartStep(function() return syncMove(turtle.forward, "forward") end) then
            break
        end
    end

    -- Z alignment
    while lastKnownPos.z ~= tz do
        faceDirection(lastKnownPos.z < tz and "south" or "north")
        if not smartStep(function() return syncMove(turtle.forward, "forward") end) then
            break
        end
    end

    -- Y desent
    while lastKnownPos.y > ty do
        if not smartStep(function() return syncMove(turtle.down, "down") end) then
            break
        end
    end

    myState = "parked"
    targetPos = nil
    broadcastStatus(false)
    
end

local function getDirID(facing)
    local mapping = { north = 0, east = 1, south = 2, west = 3}
    return mapping[facing] or "????"
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
getGPSData(true)
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
                rednet.send(id, {type = "turtle_response", id = myID, content = "Updating..."}, version_protocol)
                
                local path = "/installer"
                -- 1. Ensure fresh download
                if fs.exists(path) then fs.delete(path) end
                
                print("Downloading installer...")
                shell.run("pastebin", "get", "S3HkJqdw", path)

                if fs.exists(path) then
                    print("Executing update...")
                    -- 2. Use dofile to execute the script directly from the path
                    -- This bypasses the "No such program" shell error
                    local success, err = pcall(function()
                        -- This effectively runs: installer update [PKG]
                        local pkg = msg.pkg or "TURTLE"
                        shell.run(path, "update", pkg)
                    end)

                    if success then
                        rednet.send(id, {type = "update_complete", id = myID}, version_protocol)
                        sleep(1)
                        os.reboot()
                    else
                        print("Exec Error: " .. tostring(err))
                        rednet.send(id, {type = "turtle_response", id = myID, content = "Exec fail: "..tostring(err)}, version_protocol)
                    end
                else
                    print("Download failed.")
                    rednet.send(id, {type = "turtle_response", id = myID, content = "Download failed"}, version_protocol)
                end

            elseif command == "IDENTIFY_TYPE" then
                getGPSData(true)
                broadcastStatus(true)

            elseif command == "SEND_VERSION" then
                broadcastStatus(false)

            elseif msgType == "RECALL_POSITION" then
                getGPSData(true)
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
