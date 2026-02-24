local mons = {}

peripheral.find("monitor", function (name, mon)
    table.insert(mons, { name = name, obj = mon })
end)

function writeAll(text)
    -- write to all attached monitors
    for _, mon in ipairs(mons) do
        mon.obj.clear()
        mon.obj.setCursorPos(1, 1)
        mon.obj.write(text)
    end
end

function writeMon(name, text)
    -- Write to a specific monitor
    for _, mon in ipairs(mons) do
        if mon.name == name then
            mon.obj.clear()
            mon.obj.setCursorPos(1, 1)
            mon.obj.write(text)
            return
        end
    end
end

function AttachMon(monName)
    -- create a Json file to save data? like width and height?
    for _, mon in ipairs(mons) do
        if mon.name == monName then
            local w, h = mon.obj.getSize()
            print("Attached monitor:")
            print("Name: " .. monName)
            print("Width: " .. w)
            print("Height: " .. h)
            return
        end
    end
end

writeAll("Please click the Top Left Monitor.")

while true do
  local event, side, x, y = os.pullEvent()

  if event == "monitor_touch" then
    AttachMon(side)
    writeMon(side, "ATTACHED!")
  end
end