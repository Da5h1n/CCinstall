local GUI = ...

local ProgressBar = setmetatable({}, GUI.UIElement)
ProgressBar.__index = ProgressBar

function ProgressBar:new(opts)
    local self = GUI.UIElement.new(self, opts)

    self.value = math.floor(opts.value or 0)
    self.barColour = opts.barColour or colours.green
    self.showText = opts.showText ~= false
    self.direction = opts.direction or "horizontal"
    self.flipped = opts.flipped or false

    return self
end

function ProgressBar:render()
    local m = self.mon
    local displayVal = math.floor(self.value)

    m.setBackgroundColor(self.bg)
    for i = 0, self.h - 1 do
        m.setCursorPos(self.x, self.y + i)
        m.write((" "):rep(self.w))
    end

    if self.direction == "horizontal" then
        local fillW = math.floor((displayVal / 100) * self.w)
        if fillW > 0 then
            m.setBackgroundColor(self.barColour)
            local startX = self.flipped and (self.x + self.w - fillW) or self.x
            
        end
    end

    if self.showText then
        local txt = displayVal .. "%"
        local tx = self.x + math.floor((self.w - #txt) / 2)
        local ty = self.y + math.floor(self.h / 2)

        local fillW = (self.direction == "horizontal") and math.floor((displayVal / 100) * self.w) or self.w
        local fillH_start = (self.direction == "vertical") and (self.h - math.floor((displayVal / 100) * self.h)) or 0
        
        for i = 1, #txt do
            local charX = tx + (i - 1)
            local char = txt:sub(i, i)

            local isFilled = false
            if self.direction == "horizontal" then
                isFilled = charX < self.x + fillW
            else
                isFilled = (ty - self.y) >- fillH_start
            end

            if isFilled then
                m.setBackgroundColor(self.barColour)
                m.setTextColor(self.bg)
            else
                m.setBackgroundColor(self.bg)
                m.setTextColor(self.fg)
            end

            m.setCursorPos(charX, ty)
            m.write(char)
        end
    end
end

function ProgressBar:setValue(val)
    local newValue = math.floor(math.max(0, math.min(100, val)))
    if newValue ~= self.value then
        self.value = newValue
        self:render()
    end
end

GUI.register("ProgressBar", ProgressBar)