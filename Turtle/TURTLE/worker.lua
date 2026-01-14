-- Reset rednet to ensure a clean state
rednet.close()
peripheral.find("modem", rednet.open)
-- Critical: Give modded peripherals (Advanced Peripherals) time to load
sleep(1) 

local version_protocol = "fleet_status"

-- Identity check logic
local function getRole()
    local names = peripheral.getNames()
    local role = "worker" -- Default

    for _, name in ipairs(names) do
        local pType = peripheral.getType(name)
        if pType then
            -- Check for Chunkloader (Advanced Peripherals)
            if pType:find("chunk") then 
                return "chunky" 
            end
            -- Check for Pickaxe (Diamond or otherwise)
            if pType:find("pickaxe") or pType:find("mining") then 
                role = "miner" 
            end
        end
    end
    return role
end

-- Function to package current status
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
        id = os.getComputerID(),
        role = getRole(),
        v = version,
        fuel = turtle.getFuelLevel(),
        maxFuel = turtle.getFuelLimit()
    }
end

-- Report status immediately on boot/startup using the protocol
rednet.broadcast(getStatusReport(), version_protocol)
print("Turtle Online. Role: " .. getRole())

while true do
    -- Listen specifically on the fleet protocol
    local id, msg, protocol = rednet.receive(version_protocol)
    
    if msg == "SEND_VERSION" or msg == "IDENTIFY_TYPE" then
        rednet.send(id, getStatusReport(), version_protocol)

    elseif type(msg) == "table" and msg.type == "INSTALLER_UPDATE" then
        print("Update signal received for: " .. msg.pkg)
        
        -- Send "Starting" log to Dashboard
        rednet.send(id, {
            type = "turtle_response", 
            id = os.getComputerID(), 
            content = "Update starting..."
        }, version_protocol)
        
        if not fs.exists("installer") then
            shell.run("pastebin", "get", "S3HkJqdw", "installer")
        end
        
        -- Run the update
        shell.run("installer", "update", msg.pkg)
        
        -- HANDSHAKE: Signal completion to the Hub before rebooting
        print("Update complete. Signaling Hub...")
        rednet.send(id, {
            type = "update_complete",
            id = os.getComputerID()
        }, version_protocol)
        
        sleep(2) -- Brief pause to ensure message is sent
        os.reboot()
    end
end
