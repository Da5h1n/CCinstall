-- Reset rednet to ensure a clean state
rednet.close()
peripheral.find("modem", rednet.open)
sleep(1) -- Wait for modded peripherals (Chunkloaders) to initialize

local version_protocol = "fleet_status"

-- 1. Identity logic: Scans peripherals AND inventory for tools
local function getRole()
    -- Check peripherals (This catches the Chunkloader)
    local names = peripheral.getNames()
    for _, name in ipairs(names) do
        local pType = peripheral.getType(name)
        if pType and pType:find("chunk") then return "chunky" end
    end

    -- Check inventory for Pickaxe (This catches the Miner)
    -- We scan all 16 slots at boot to find the tool
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and (item.name:find("pickaxe") or item.name:find("mining")) then
            return "miner"
        end
    end

    return "worker"
end

-- 2. Configuration based on detected role
local myRole = getRole()
local myID = os.getComputerID()
local myName = (myRole == "miner") and ("Deep-Core Driller " .. myID) or 
               (myRole == "chunky") and ("Support Loader " .. myID) or 
               ("Worker " .. myID)

-- 3. Package status for Hub/Dashboard
local function getStatusReport()
    local version = "unknown"
    if fs.exists("/.installer/versions.json") then
        local f = fs.open("/.installer/versions.json", "r")
        local data = textutils.unserializeJSON(f.readAll())
        f.close()
        version = (data and data["TURTLE"]) and data["TURTLE"].version or "0"
    end

    return {
        type = "version_report",
        id = myID,
        name = myName,
        role = myRole,
        v = version,
        fuel = turtle.getFuelLevel(),
        maxFuel = turtle.getFuelLimit()
    }
end

-- --- MAIN BOOT ---
rednet.broadcast(getStatusReport(), version_protocol)
print("Booted: " .. myName)

while true do
    local id, msg, protocol = rednet.receive(version_protocol)
    
    -- Handle Hub requests
    if msg == "SEND_VERSION" or msg == "IDENTIFY_TYPE" then
        rednet.send(id, getStatusReport(), version_protocol)

    -- Handle Hub Fleet Update
    elseif type(msg) == "table" and msg.type == "INSTALLER_UPDATE" then
        print("Update signal received...")
        
        rednet.send(id, {
            type = "turtle_response", 
            id = myID, 
            content = "Update starting..."
        }, version_protocol)
        
        if not fs.exists("installer") then
            shell.run("pastebin", "get", "S3HkJqdw", "installer")
        end
        
        shell.run("installer", "update", msg.pkg)
        
        -- Handshake: Hub waits for this specific signal
        print("Handshaking Hub...")
        rednet.send(id, {
            type = "update_complete",
            id = myID
        }, version_protocol)
        
        sleep(2)
        os.reboot()
    end
end
