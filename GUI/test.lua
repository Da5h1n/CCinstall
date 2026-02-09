local GUI = require("lib.gui.manager")
local mon = peripheral.find("monitor") or term.current()

-- 1. Setup the Main Frames
local mainFrames = {
    -- Top Status Frame
    GUI.newFrame{ 
        id = "main_stats", 
        mon = mon, x = 2, y = 2, w = 25, h = 10, 
        text = "System Monitor", side = "top", align = "left",
        bg = colors.gray, bc = colors.blue 
    },
    
    -- Control Frame
    GUI.newFrame{ 
        mon = mon, x = 2, y = 13, w = 25, h = 20, 
        text = "Controls", side = "top", align = "center",
        bg = colors.black, bc = colors.red 
    }
}

-- 2. Add Elements to the Status Frame (Using Auto-Parenting)
local stats = mainFrames[1]

stats:addChild(GUI.newLabel{
    id = "lbl_time",
    parent = stats.window,
    x = 2, y = 2, w = 15, -- Shortened width to clear space
    text = "Time: 00:00",
    fg = colors.yellow
})

-- Horizontal Bar (Main Progress)
stats:addChild(GUI.newProgressBar{
    id = "main_progress",
    parent = stats.window,
    x = 2, y = 4, w = 16, h = 3, -- Adjusted width from 20 to 16
    direction = "horizontal",
    value = 0,
    bg = colors.black,
    barColor = colors.lime,
    fg = colors.white
})

-- NEW: Vertical Bar (Side Gauge)
stats:addChild(GUI.newProgressBar{
    id = "side_gauge",
    parent = stats.window,
    x = 19, y = 2, w = 4, h = 7, -- Positioned to the right
    direction = "vertical",
    value = 0,
    bg = colors.black,
    barColor = colors.orange,
    fg = colors.white,
    showText = true -- This will center the % in the middle of the vertical column
})

-- 3. Add Elements to the Control Frame
local controls = mainFrames[2]

controls:addChild(GUI.newButton{
    x = 2, y = 2, w = 10, h = 3,
    parent = controls.window,
    text = "BEEP",
    bg = colors.blue,
    action = function() os.queueEvent("random_beep") end
})

controls:addChild(GUI.newButton{
    x = 13, y = 2, w = 10, h = 3,
    parent = controls.window,
    text = "QUIT",
    bg = colors.red,
    action = function() error() end -- Force exit
})

controls:addChild(GUI.newDropdown{
    id = "theme_picker",
    parent = controls.window,
    x = 2, y = 6, w = 15,
    options = {"Blue", "Red", "Green", "Orange"},
    bg = colors.lightGray,
    fg = colors.black,
    onSelect = function(val, index)
        print("Selected: " .. val)
        -- You could change frame colors here!
    end
})

-- 4. Animation Logic
local barPercent = 0
GUI.init{
    scale = 0.5,
    frames = mainFrames,
    onUpdate = function()
        -- Update Clock
        local clock = GUI.getByID("lbl_time")
        if clock then
            local t = textutils.formatTime(os.time("local"), true)
            if clock.text ~= "Time: "..t then
                clock:setText("Time: "..t)
                clock:render()
            end
        end

        -- Update Loading Bar
        barPercent = (barPercent + 1) % 101 
        
        -- Update Horizontal Bar
        local barH = GUI.getByID("main_progress")
        if barH then barH:setValue(barPercent) end

        -- Update Vertical Bar
        local barV = GUI.getByID("side_gauge")
        if barV then 
            -- Let's make the vertical bar inverse for visual variety
            barV:setValue(100 - barPercent) 
        end
    end
}