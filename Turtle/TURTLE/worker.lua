-- Ensure modem is open
peripheral.find("modem", rednet.open)
sleep(0.5) -- Critical: Give the modem a moment to initialize after boot

local version_protocol = "fleet_status"

-- Identity check logic
local function getRole()
    -- Advanced Peripherals chunkloaders usually register as "chunk_loader" 
    -- but we check for "chunk" to be safe.
    for _, name in ipairs(peripheral.getNames()) do
        local pType = peripheral.getType(name)
        if pType and pType:find("chunk") then return "chunky" end
        if pType and pType:find("pickaxe") then return "miner" end
    end
    return "worker"
end

local function getStatusReport()
    local version = "unknown"
    if fs.exists("/.installer/versions.json") then
        local f = fs.open("/.installer/versions.json", "r")
        local data = textutils.unserializeJSON(f.readAll())
        f.close()
        version = data["TURTLE"] and data["TURTLE"].version or "0"
    end

    return {
        type = "version_report",
        id = os.getComputerID(),
        role = getRole(),
        v = version,
        fuel = turtle.getFuelLevel(),
        maxFuel = turtle.getFuelLimit()
    }
end

-- Report status on boot using a specific protocol
rednet.broadcast(getStatusReport(), version_protocol)

print("Turtle Online. Role: " .. getRole())

while true do
    -- Listen for messages on our specific protocol
    local id, msg, protocol = rednet.receive()
    
    -- Handle both direct messages and protocol-specific broadcasts
    if msg == "SEND_VERSION" or msg == "IDENTIFY_TYPE" or protocol == version_protocol then
        rednet.send(id, getStatusReport(), version_protocol)

    elseif type(msg) == "table" and msg.type == "INSTALLER_UPDATE" then
        print("Update signal received...")
        rednet.send(id, {
            type = "turtle_response", 
            id = os.getComputerID(), 
            content = "Updating..."
        }, version_protocol)
        
        if not fs.exists("installer") then
            shell.run("pastebin", "get", "S3HkJqdw", "installer")
        end
        
        shell.run("installer", "update", msg.pkg)
        sleep(1)
        os.reboot()
    end
end
