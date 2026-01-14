-- startup.lua
-- This file rarely changes! It just launches your main code.
if fs.exists("/TURTLE/worker.lua") then
    shell.run("/TURTLE/worker.lua")
else
    print("Waiting for initial package installation...")
end
