local ws_url = "ws://skinnerm.duckdns.org:25565"
local installer_pkg = "HUB"
rednet.open("back")

-- Helper to run the installer script
local function runInstaller(pkg)
    if not fs.exists("installer") then
        shell.run("pastebin", "get", "S3HkJqdw", "installer")
    end
    shell.run("installer", "update", pkg)
end

-- Function to handle the fleet update sequence
local function coordinateFleetUpdate()
    print("Step 1: Updating all Turtles...")
    rednet.broadcast({type="INSTALLER_UPDATE", pkg="TURTLE"})
    
    -- We wait a bit for turtles to start their downloads 
    -- before the Hub reboots itself.
    print("Waiting for fleet to initiate...")
    sleep(5) 
    
    print("Step 2: Updating Hub...")
    runInstaller("HUB")
    print("Rebooting Hub...")
    os.reboot()
end

-- Main Loop
while true do
    local _, _, msg = os.pullEvent("websocket_message")
    
    if msg == "update fleet" then
        -- This triggers the safe sequence: Turtles first, then Hub.
        coordinateFleetUpdate()
    
    elseif msg == "version check" then
        -- Ask turtles for their version info to show on PC
        rednet.broadcast("SEND_VERSION")
        
    elseif event[1] == "rednet_message" then
        -- Forward version/status info from turtles to PC
        safeSend(event[3]) 
    end
end
