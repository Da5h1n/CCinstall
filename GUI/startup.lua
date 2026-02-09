print("Startup clearing monitors...")

local monitors = {peripheral.find("monitor")}

for _, monitor in ipairs(monitors) do
    monitor.setTextScale(1)
    monitor.setTextColor(colours.white)
    monitor.setBackgroundColor(colours.black)
    monitor.clear()
    monitor.setCursorPos(1,1)
end