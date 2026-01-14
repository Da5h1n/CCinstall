-- Reset rednet to ensure a clean state
rednet.close()
peripheral.find("modem", rednet.open)
sleep(1) -- Wait for modded peripherals (Chunkloaders) to initialize

local version_protocol = "fleet_status"

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

-- 2. Configuration based on detected role
local myRole = getRole()
local myID = os.getComputerID()

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

local function getGPSData()
    local x, y, z = gps.locate(2)
    if not x then return nil end

    local facing = "unknown"
    -- move to detect orientation
    if not turtle.detect() then
        if turtle.forward() then
            local x2, y2, z2 = gps.locate(2)
            if x2 then
                if x2 > x then facing = "east"
                elseif x2 < x then facing = "west"
                elseif z2 > z then facing = "south"
                elseif z2 < z then facing = "north"
                end
            end
            turtle.back()
        end
    end
    return { x = x, y = y, z = z, facing = facing }
end

-- 3. Package status for Hub/Dashboard
local function getStatusReport(checkGPS)
    local version = "unknown"
    if fs.exists("/.installer/versions.json") then
        local f = fs.open("/.installer/versions.json", "r")
        local data = textutils.unserializeJSON(f.readAll())
        f.close()
        version = (data and data["TURTLE"]) and data["TURTLE"].version or "0"
    end

    local report = {
        type = "version_report",
        id = myID,
        name = myName,
        role = myRole,
        v = version,
        fuel = turtle.getFuelLevel(),
        maxFuel = turtle.getFuelLimit(),
        inventory = getInventory()
    }

    if checkGPS then
        report.pos = getGPSData()
    end
    return report
end

-- --- MAIN BOOT ---
rednet.broadcast(getStatusReport(false), version_protocol)
print("Booted: " .. myName)

while true do
    local id, msg, protocol = rednet.receive(version_protocol)
    
    -- "IDENTIFY_TYPE" triggers a full scan (with movement)
    -- "SEND_VERSION" triggers a quick update (no movement)
    if msg == "IDENTIFY_TYPE" then
        rednet.send(id, getStatusReport(true), version_protocol)

    elseif msg == "SEND_VERSION" then
        rednet.send(id, getStatusReport(false), version_protocol)

    elseif type(msg) == "table" and msg.type == "INSTALLER_UPDATE" then
        print("Update signal received...")
        rednet.send(id, {type = "turtle_response", id = myID, content = "Update starting..."}, version_protocol)
        
        if not fs.exists("installer") then
            shell.run("pastebin", "get", "S3HkJqdw", "installer")
        end
        
        shell.run("installer", "update", msg.pkg)
        rednet.send(id, {type = "update_complete", id = myID}, version_protocol)
        
        sleep(2)
        os.reboot()
    end
end
