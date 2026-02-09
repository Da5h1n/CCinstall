local GUI = ...

---@class Input : UIElement
local Input = setmetatable({}, GUI.UIElement)
Input.__index = Input

function Input:new(opts)
    local self = GUI.UIElement.new(self, opts)

    -- Have options for type of input + hidden
    self.MaxLen = opts.MaxLen or 20
end

function Input:render()
    
end

function Input:click()
    --- NEW FEATURE HERE? (ON SCREEN KEYBOARD ONLY ON MONITORS!!!)
end

GUI.register("Input", Input)