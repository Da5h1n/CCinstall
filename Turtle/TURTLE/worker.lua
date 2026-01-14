perhipheral.find("modem", rednet.open)

-- Identity check logic
local function getRole()
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "chunkloader" then return "chunky" end
        if peripheral.getType(name):find("pickaxe") then return "miner" end
    end
    return "worker"
end

while true do
    local id, msg = rednet.receive()
    
    if msg == "SEND_VERSION" then
        -- Send back role and version (if stored in registry)
        local version = "unknown"
        if fs.exists("/.installer/versions.json") then
            local f = fs.open("/.installer/versions.json", "r")
            local data = textutils.unserializeJSON(f.readAll())
            f.close()
            version = data["TURTLE"] and data["TURTLE"].version or "0"
        end
        rednet.send(id, {type="version_report", role=getRole(), v=version})

    elseif type(msg) == "table" and msg.type == "INSTALLER_UPDATE" then
        print("Update signal received for: " .. msg.pkg)
        
        -- Let the Hub know we are starting
        rednet.send(id, "Turtle " .. os.getComputerID() .. " starting update...")
        
        if not fs.exists("installer") then
            shell.run("pastebin", "get", "S3HkJqdw", "installer")
        end
        
        shell.run("installer", "update", msg.pkg)
        
        print("Done. Rebooting...")
        sleep(1)
        os.reboot()
    end
end
