local GUI = ...

---@class Label : UIElement
local Label = setmetatable({}, GUI.UIElement)
Label.__index = Label

function Label:new(opts)
    local self = GUI.UIElement.new(self, opts)
    self.text = opts.text or ""
    self.align = opts.align or "left"
    self.lastText = nil
    return self
end

function Label:setText(text)
    self.text = tostring(text or "")
end

function Label:render()
    if self.text == self.lastText then return end

    local m = self.mon
    m.setBackgroundColor(self.bg)
    m.setTextColor(self.fg)

    m.setCursorPos(self.x, self.y)
    m.write((" "):rep(self.w))

    local txt = self.text:sub(1, self.w)
    local x

    if self.align == "center" then
        x = self.x + math.floor((self.w - #txt) / 2)
    elseif self.align == "right" then
        x = self.x + self.w - #txt
    else
        x = self.x
    end

    m.setCursorPos(x, self.y)
    m.write(txt)

    self.lastText = self.text
end

GUI.register("Label", Label)