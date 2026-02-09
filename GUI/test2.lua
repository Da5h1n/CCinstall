local GUI = require("lib.gui.manager")
local mon = peripheral.find("monitor") or term.current()

local mainFrames = {


    GUI.newInput{
        x = 2, y = 2, w = 10, h = 3,
        mon = mon,
        bg = colors.blue,
    }
}



GUI.init{
    scale = 0.5,
    frames = mainFrames
}