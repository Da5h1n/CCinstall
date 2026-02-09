local GUI = ...

---@class Frame : UIElement
local Frame = setmetatable({}, GUI.UIElement)
Frame.__index = Frame

function Frame:new(opts)
    local self = GUI.UIElement.new(self, opts)
    self.text = opts.text or ""
    self.align = opts.align or "left"
    self.side = opts.side or "top"
    self.children = {}
    self:setupWindow()
    return self
end

function Frame:setupWindow()
    self.window = window.create(
        self.mon,
        self.x + 1,
        self.y + 1,
        self.w - 2,
        self.h - 2,
        true
    )
end

function Frame:drawBorder()
    local m = self.mon
    m.setBackgroundColor(self.bc)

    for i = 0, self.h - 1 do
        m.setCursorPos(self.x, self.y + i)
        m.write(" ")
        m.setCursorPos(self.x + self.w - 1, self.y + i)
        m.write(" ")
    end

    for i = 0, self.w - 1 do
        m.setCursorPos(self.x + i, self.y)
        m.write(" ")
        m.setCursorPos(self.x + i, self.y + self.h - 1)
        m.write(" ")
    end

    if self.text == "" then return end

    m.setBackgroundColor(self.bg)
    m.setTextColor(self.fg)

    local isVertical = (self.side == "left" or self.side == "right")
    local maxLen = isVertical and (self.h - 2) or (self.w - 4)
    local txt = self.text:sub(1, maxLen)

    if not isVertical then
        local y = (self.side == "bottom") and (self.y + self.h - 1) or self.y
        local x

        if self.align == "center" then
            x = self.x + math.floor((self.w - (#txt + 2)) / 2)
        elseif self.align == "right" then
            x = self.x + self.w - (#txt + 2) - 1
        else
            x = self.x + 1
        end

        m.setCursorPos(x, y)
        m.write(" " .. txt .. " ")
    else
        local x = (self.side == "right") and (self.x + self.w - 1) or self.x
        
        local paddedLen = #txt + 2
        local y 
        
        if self.align == "center" then
            y = self.y + math.floor((self.h - paddedLen) / 2)
        elseif self.align == "right" then
            y = self.y + self.h - paddedLen - 1
        else
            y = self.y + 1
        end

        m.setCursorPos(x, y)
        m.write(" ")

        for i = 1, #txt do
            m.setCursorPos(x, y + i)
            m.write(txt:sub(i, i))
        end

        m.setCursorPos(x, y + #txt + 1)
        m.write(" ")
    end
end

function Frame:addChild(element)
    element.parentFrame = self

    table.insert(self.children, element)
    return element
end

function Frame:render(clearBG)
    self:drawBorder()
    
    if clearBG then
        self.window.setBackgroundColor(self.bg)
        self.window.clear()
    end

    for _, child in ipairs(self.children) do
        child:render()
    end
end

function Frame:click(x, y)
    local ix = x - self.x
    local iy = y - self.y

    for _, child in ipairs(self.children) do
        if ix >= child.x and ix < child.x + child.w and
           iy >= child.y and iy < child.y + child.h then
            if child.click then child:click(ix, iy) end
        end
    end
end

GUI.register("Frame", Frame)