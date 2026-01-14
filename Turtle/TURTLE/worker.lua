peripheral.find("modem", rednet.open)

-- Identity check logic
local function getRole()
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "chunkloader" then return "chunky" end
        if peripheral.getType(name):find("pickaxe") then return "miner" end
    end
    return "worker"
end

-- Function to package current status for the Dashboard
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

-- Report status immediately on boot/startup
rednet.broadcast(getStatusReport())

print("Turtle Online. Role: " .. getRole())

while true do
    local id, msg = rednet.receive()
    
    -- "IDENTIFY_TYPE" is used by the Hub during the 'Refresh' sequence
    if msg == "SEND_VERSION" or msg == "IDENTIFY_TYPE" then
        rednet.send(id, getStatusReport())

    elseif type(msg) == "table" and msg.type == "INSTALLER_UPDATE" then
        print("Update signal received for: " .. msg.pkg)
        
        -- Send log to Hub -> Python -> Web Dashboard
        rednet.send(id, {
            type = "turtle_response", 
            id = os.getComputerID(), 
            content = "Updating to latest version..."
        })
        
        if not fs.exists("installer") then
            shell.run("pastebin", "get", "S3HkJqdw", "installer")
        end
        
        shell.run("installer", "update", msg.pkg)
        
        print("Done. Rebooting...")
        sleep(1)
        os.reboot()
    end
end
