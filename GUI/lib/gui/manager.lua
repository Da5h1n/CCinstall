local Manager = {}
Manager.classes = {}
Manager.activeFrames = {}

function Manager.register(name, classTable)
    Manager.classes[name] = classTable
    Manager["new" .. name] = function(opts)
        return classTable:new(opts)
    end
end

---@class UIElement
Manager.UIElement = {}
Manager.UIElement.__index = Manager.UIElement

function Manager.UIElement:new(opts)
    local self = setmetatable({}, self)
    self.id = opts.id
    self.x = opts.x or 1
    self.y = opts.y or 1
    self.w = opts.w or 18
    self.h = opts.h or 12
    self.bg = opts.bg or colours.blue
    self.fg = opts.fg or colours.white
    self.bc = opts.bc or colours.lightGrey
    self.mon = opts.parent or opts.mon or term
    self.children = {}
    return self
end

function Manager.getByID(id)
    if not id then return nil end
    for _, f in ipairs(Manager.activeFrames) do
        if f.id == id then return f end
        for _, child in ipairs(f.children or {}) do
            if child.id == id then return child end
        end
    end
    return nil
end

function Manager.init(config)
    local frames = config.frames or config
    Manager.activeFrames = frames
    local scale = config.scale or 0.5

    local mainMon = frames[1].mon
    if mainMon.setTextScale then mainMon.setTextScale(scale) end

    local function redraw()
        mainMon.setBackgroundColor(colours.black)
        mainMon.clear()
        for _, f in ipairs(Manager.activeFrames) do f:render() end
    end

    redraw()

    while true do
        local timerID = os.startTimer(0.1)
        local event = {os.pullEvent()}
        local e = event[1]

        if e == "mouse_click" or e == "monitor_touch" then
            local _, side, x, y = table.unpack(event)
            for _, f in ipairs(Manager.activeFrames) do
                if x >= f.x and x < f.x + f.w and y >= f.y and y < f.y + f.h then
                    if f.click then f:click(x, y) end
                end
            end
        elseif e == "monitor_resize" then
            redraw()
        end

        if config.onUpdate then
            config.onUpdate()
            
        end

        for _, frame in ipairs(Manager.activeFrames) do
            if frame.update then frame:update() end
            for _, child in ipairs(frame.children or {}) do
                if child.update then child:update() end
            end
        end
    end
end

local classDir = "lib/gui/elements"

if fs.exists(classDir) and fs.isDir(classDir) then
    local files = fs.list(classDir)
    table.sort(files)
    
    for _, file in ipairs(files) do
        local path = classDir .. "/" .. file
        local chunk, err = loadfile(path)
        
        if chunk then
            -- 1. Use the standard global environment
            setfenv(chunk, _G) 
            
            -- 2. Pass the Manager (this table) as an argument to the chunk
            local success, runErr = pcall(chunk, Manager) 
            
            if not success then
                print("Error running " .. file .. ": " .. runErr)
            end
        else
            print("Error loading " .. file .. ": " .. err)
        end
    end
end

return Manager