local GUI = ...

---@class Dropdown : UIElement
local Dropdown = setmetatable({}, GUI.UIElement)
Dropdown.__index = Dropdown

function Dropdown:new(opts)
    local self = GUI.UIElement.new(self, opts)
    self.options = opts.options or {}
    self.selected = opts.selected or 1
    self.isOpen = false
    self.onSelect = opts.onSelect or function() end
    
    self.bg_open = opts.bg_open or colours.grey

    self.bg_list = opts.bg_list or colours.lightGrey
    self.fg_list = opts.fg_list or colours.black

    self.bg_sel = opts.bg_sel or colours.yellow
    self.fg_sel = opts.fg_sel or colours.black

    self.closedH = 1
    self.expandedH = #self.options + 1
    self.h = self.closedH
    return self
end

function Dropdown:render()
    local m = self.mon
    
    local headerBG = self.isOpen and self.bg_open or self.bg

    m.setBackgroundColor(headerBG)
    m.setTextColor(self.fg)
    m.setCursorPos(self.x, self.y)

    local arrow = self.isOpen and "v" or ">"
    local txt = arrow .. " " .. tostring(self.options[self.selected] or "None")
    m.write(txt:sub(1, self.w)..string.rep(" ", self.w - #txt))

    if self.isOpen then
        for i, option in ipairs(self.options) do
            m.setCursorPos(self.x, self.y + i)

            if i == self.selected then
                m.setBackgroundColor(self.bg_sel)
                m.setTextColor(self.fg_sel)
            else
                m.setBackgroundColor(self.bg_list)
                m.setTextColor(self.fg_list)
            end
            local optTxt = "  " .. tostring(option)
            m.write(optTxt:sub(1, self.w)..string.rep(" ", self.w - #optTxt))
        end
    end
end

function Dropdown:click(x, y)
    -- Clicked the header?
    if y == self.y then
        self.isOpen = not self.isOpen
        self.h = self.isOpen and self.expandedH or self.closedH
    elseif self.isOpen then
        -- Clicked an option?
        local index = y - self.y
        if self.options[index] then
            self.selected = index
            self.isOpen = false
            self.h = self.closedH
            self.onSelect(self.options[index], index)
        end
    end
    -- Trigger a re-render of the parent frame to clear the old list area
    if self.parentFrame then self.parentFrame:render(true) else self:render() end
end

GUI.register("Dropdown", Dropdown)