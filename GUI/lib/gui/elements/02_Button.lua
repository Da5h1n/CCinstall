local GUI = ...

---@class Button : UIElement
local Button = setmetatable({}, GUI.UIElement)
Button.__index = Button

function Button:new(opts)
    local self = GUI.UIElement.new(self, opts) 
    self.action = opts.action or function() end

    self.text = opts.text or "Button"
    self.action = opts.action or function() end
    self.bg_active = opts.bg_active or colours.white
    self.fg_active = opts.fg_active or colours.black
    self.isPressed = false
    return self
end

function Button:render()
    local m = self.mon
    -- Toggle colors based on press state
    local bg = self.isPressed and self.bg_active or self.bg
    local fg = self.isPressed and self.fg_active or self.fg
    
    -- Draw a solid background rectangle
    m.setBackgroundColor(bg)
    for i = 0, self.h - 1 do
        m.setCursorPos(self.x, self.y + i)
        m.write((" "):rep(self.w))
    end

    -- Draw centered text inside the button
    m.setTextColor(fg)
    local txt = self.text:sub(1, self.w - 2)
    local tx = self.x + math.floor((self.w - #txt) / 2)
    local ty = self.y + math.floor(self.h / 2)
    m.setCursorPos(tx, ty)
    m.write(txt)
end

function Button:click()
    self.isPressed = true
    self:render()
    
    -- Short delay for visual feedback
    sleep(0.1) 
    
    self.isPressed = false
    self:render()
    
    -- Execute the assigned action
    if self.action then self.action() end
end

GUI.register("Button", Button)