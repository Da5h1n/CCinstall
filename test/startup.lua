local configPath = ".monitors"
local screens = {}

--BUFFER
local frameBuffer = {}
local MAX_BUFFER = 50

--VARS
local frameCount = 0
local lastFrameTime = os.epoch("utc")
local renderDuration = 0
local frameDuration = 0

local fps = 0
local framesInSecond = 0
local nextFpsUpdate = os.epoch("utc") + 1000

local debugMon = peripheral.wrap("right")

local function saveConfig(data)
    local f = fs.open(configPath, "w")
    f.write(textutils.serialiseJSON(data))
    f.close()
end

local function loadConfig()
    if not fs.exists(configPath) then return nil end
    local f = fs.open(configPath, "r")
    local data = textutils.unserialiseJSON(f.readAll())
    f.close()
    return data
end

local function getTextColour(bgColour)
    if bgColour == colours.black or bgColour == colours.blue or bgColour == colours.grey then
        return colours.white
    end
    return colours.black
end

local rowColours = {colours.blue, colours.green, colours.red, colours.yellow, colours.purple, colours.orange}

local function runSetup()
    term.clear()
    term.setCursorPos(1, 1)
    print("--- MONTIOR SETUP ---")
    print(" Touch the Top-Left monitor.")

    local layout = { monitors = {}, grid = { columns = 0, rows = 1 } }
    local controlerSide = nil
    local currentRow = 1
    local colCountInRow = 0
    local maxCols = 0

    while true do
        local event, side, x, y = os.pullEvent("monitor_touch")

        if controlerSide and side == controlerSide then
            if y == 2 then
                currentRow = currentRow + 1
                colCountInRow = 0
                print("Moved to row " .. currentRow)
                local m = peripheral.wrap(side)
                m.setCursorPos(1, 1)
                m.write("Current Row: " .. currentRow .. " ")
                goto continue
            elseif y == 4 then
                layout.grid.rows = currentRow
                layout.grid.columns = maxCols
                layout.amount = #layout.monitors
                break
            end
        end

        local alreadyAdded = false
        for _, m in ipairs(layout.monitors) do
            if m.name == side then alreadyAdded = true end
        end

        if not alreadyAdded then
            if not controlerSide then
                controlerSide = side
                print("Controler set to: " .. side)
            end

            colCountInRow = colCountInRow + 1
            if colCountInRow > maxCols then maxCols = colCountInRow end

            local mObj = peripheral.wrap(side)
            local w, h = mObj.getSize()
            local bgColour = rowColours[((currentRow - 1) % #rowColours) + 1]

            table.insert(layout.monitors, {
                name = side,
                x_pos = colCountInRow,
                y_pos = currentRow,
                width = w,
                height = h
            })

            mObj.setBackgroundColour(bgColour)
            mObj.setTextColour(getTextColour(bgColour))
            mObj.clear()

            if side == controlerSide then
                mObj.setCursorPos(1, 1)
                mObj.write("R:" .. currentRow .. " C:" .. colCountInRow)
                mObj.setCursorPos(1, 2)
                mObj.write("[NEXT ROW]")
                mObj.setCursorPos(1, 4)
                mObj.setTextColour(colours.red)
                mObj.write("[DONE]")
            else
                mObj.setCursorPos(1, 1)
                mObj.write("R:" .. currentRow .. " C:" .. colCountInRow)
            end
        end
        
        ::continue::
    end

    saveConfig(layout)
    return layout
end

local function updateDebug()
    debugMon.setBackgroundColour(colours.black)
    debugMon.setTextColour(colours.yellow)
    debugMon.clear()
    debugMon.setCursorPos(1, 1)
    debugMon.write("DEBUG INFO")
    debugMon.setTextColour(colours.white)
    debugMon.setCursorPos(1, 3)
    debugMon.write("Frame: " .. frameCount)

    if fps >= 15 then debugMon.setTextColour(colours.green)
    elseif fps >= 10 then debugMon.setTextColour(colours.orange)
    else debugMon.setTextColour(colours.red) end

    debugMon.setCursorPos(1, 4)
    debugMon.write("FPS: " .. fps)

    debugMon.setTextColour(colours.white)
    debugMon.setCursorPos(1, 6)
    debugMon.write("Render Dur: " .. renderDuration .. "ms")
    debugMon.setCursorPos(1, 7)
    debugMon.write("Frame Dur: " .. frameDuration .. "ms")

    debugMon.setCursorPos(1, 9)
    debugMon.write("Buffer: " .. #frameBuffer .. "/" .. MAX_BUFFER)

    debugMon.setCursorPos(1, 11)
    local tw = config.grid.columns * config.monitors[1].width
    local th = config.grid.rows * config.monitors[1].height
    debugMon.write("Res: " .. tw .. "x" .. th)
    debugMon.setCursorPos(1, 12)
    debugMon.write("Grid: " .. config.grid.columns .. "x" .. config.grid.rows)
end

config = loadConfig() or runSetup()

for _, m in ipairs(config.monitors) do
    local obj = peripheral.wrap(m.name)
    if obj then
        obj.setTextScale(0.5)
        m.width, m.height = obj.getSize()
    end
end

print("System Ready. Grid: " .. config.grid.columns .. "x" .. config.grid.rows)

-- Calculate total grid size for the server
local totalW = config.grid.columns * config.monitors[1].width
local totalH = config.grid.rows * config.monitors[1].height

-- Use 'localhost' or your PC's IP
local ws, err = http.websocket("ws://192.168.0.62:8000/ws")

if not ws then
    print("Connection failed: " .. tostring(err))
    return
end

print("Connected! Sending Play Command...")
ws.send(textutils.serialiseJSON({
    command = "play",
    url = "https://www.youtube.com/watch?v=8u4UzzJZAUg", -- Put your link here
    w = totalW,
    h = totalH
}))

parallel.waitForAny(
    function() -- RECIEVER 
        while true do
            local _, _, msg = os.pullEvent("websocket_message")
            local data = textutils.unserialiseJSON(msg)
            if data and data.type == "frame" then
                table.insert(frameBuffer, data.data)
                if #frameBuffer > MAX_BUFFER then
                    while #frameBuffer > (MAX_BUFFER / 2) do sleep(0.05) end
                end
            end
        end
    end,
    function() -- RENDERER
        local monitorObjects = {}
        for _, m in ipairs(config.monitors) do
            monitorObjects[m.name] = peripheral.wrap(m.name)
        end

        print("Buffering...")
        while #frameBuffer < 15 do
            sleep(0.1)
            updateDebug()
        end
        print("Playing!")

        while true do
            if #frameBuffer > 0 then
                local startRender = os.epoch("utc")

                local data = table.remove(frameBuffer, 1)

                frameDuration = startRender - lastFrameTime
                lastFrameTime = startRender

                framesInSecond = framesInSecond + 1
                local now = os.epoch("utc")
                if now >= nextFpsUpdate then
                    fps = framesInSecond
                    framesInSecond = 0
                    nextFpsUpdate = now + 1000
                end

                for _, m in ipairs(config.monitors) do
                    local screenObj = monitorObjects[m.name]
                    local mHeight = m.height
                    local mWidth = m.width
                    local xOffset = (m.x_pos - 1) * mWidth
                    local yOffset = (m.y_pos - 1) * mHeight

                    for row = 1, mHeight do
                        local fullRowText = data[yOffset + row]
                        if fullRowText then
                            local section = string.sub(fullRowText, xOffset + 1, xOffset + mWidth)
                            screenObj.setCursorPos(1, row)
                            screenObj.blit(string.rep(" ", mWidth), section, section)
                        end
                    end
                end

                renderDuration = os.epoch("utc") - startRender
                frameCount = frameCount + 1

                updateDebug()
            else
                sleep(0.05)
            end
        end
    end,
    function()
        while true do
            local _, _, msg = os.pullEvent("websocket_closed")
            print("Server closed connection.")
            return
        end
    end
)
