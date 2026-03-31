-- Client.lua - CC:Tweaked
local configPath = "monitors.json"
local TARGET_FPS = 20
local AUDIO_RATE = 48000
local MAX_BUFFER = 500
local START_THRESHOLD_FRAME = 60
local START_THRESHOLD_AUDIO = 25

-- buffers & state
local frameBuffer, audioBuffer = {}, {}
local isStarted = false
local currentTime, videoDuration, totalSamplesPlayed = 0,0,0
local currentTitle, currentPlaylist, upcomingList = "Waiting...","",{}
local currentLatency = 0

local displayFps, lastFpsUpdate, fpsCount = 0, os.clock(), 0

local speakers = { peripheral.find("speaker") }
local infoMon = peripheral.wrap("right")

-- helpers
local bExtract, sByte, tConcat, osEpoch = bit32.extract, string.byte, table.concat, os.epoch
local hex = {}
for i=0,15 do hex[i+1] = string.format("%x", i) end
local cc_cols = {}
for i=0,15 do cc_cols[i+1] = 2^i end

-- config utils
local function saveConfig(data)
    local f=fs.open(configPath,"w")
    f.write(textutils.serialiseJSON(data))
    f.close()
end
local function loadConfig()
    if not fs.exists(configPath) then return nil end
    local f=fs.open(configPath,"r")
    local data=textutils.unserialiseJSON(f.readAll())
    f.close()
    return data
end

-- monitor setup
local rowColours = {colours.blue, colours.green, colours.red, colours.yellow, colours.purple, colours.orange}
local function runSetup()
    term.clear()
    term.setCursorPos(1,1)
    print("--- Monitor Setup ---")
    print(" Touch the Top-Left monitor.")
    local layout={ monitors={}, grid={columns=0, rows=1} }
    local controlerSide, currentRow, colCountInRow, maxCols = nil, 1, 0, 0

    while true do
        local event, side, x, y = os.pullEvent("monitor_touch")
        if controlerSide and side==controlerSide then
            if y==2 then currentRow=currentRow+1; colCountInRow=0; goto continue end
            if y==4 then layout.grid.rows=currentRow; layout.grid.columns=maxCols; layout.amount=#layout.monitors; break end
        end

        local alreadyAdded=false
        for _,m in ipairs(layout.monitors) do if m.name==side then alreadyAdded=true end end

        if not alreadyAdded then
            if not controlerSide then controlerSide=side end
            colCountInRow=colCountInRow+1
            if colCountInRow>maxCols then maxCols=colCountInRow end

            local mObj=peripheral.wrap(side)
            for i=0,15 do mObj.setPaletteColor(2^i, term.nativePaletteColor(2^i)) end
            mObj.setTextScale(0.5)
            local w,h=mObj.getSize()
            local bgColour=rowColours[((currentRow-1)%#rowColours)+1]
            table.insert(layout.monitors,{name=side,x_pos=colCountInRow,y_pos=currentRow,width=w,height=h})

            mObj.setBackgroundColour(bgColour)
            mObj.setTextColour(bgColour==colours.black and colours.white or colours.black)
            mObj.clear()
            mObj.setCursorPos(1,1)
            mObj.write("R:"..currentRow.." C:"..colCountInRow)
            if side==controlerSide then
                mObj.setCursorPos(1,2); mObj.write("[NEXT ROW]")
                mObj.setCursorPos(1,4); mObj.setTextColour(colours.red); mObj.write("[DONE]")
            end
        end
        ::continue::
    end
    saveConfig(layout)
    return layout
end

-- init monitors
local function initMonitors()
    local config = loadConfig() or runSetup()
    local objs = {}
    for _, m in ipairs(config.monitors) do
        local p = peripheral.wrap(m.name)
        if p then
            p.setTextScale(0.5)
            p.setBackgroundColour(colours.black)
            p.clear()
            objs[#objs+1]={obj=p,w=m.width,h=m.height}
        end
    end
    return config, objs
end
local config, monitorObjects = initMonitors()

-- info screen
local function formatTime(seconds)
    if not seconds or seconds<=0 then return "00:00" end
    return string.format("%02d:%02d", math.floor(seconds/60), math.floor(seconds%60))
end

local function updateInfo()
    if not infoMon then return end
    local w,h = infoMon.getSize()
    infoMon.clear()
    infoMon.setTextScale(0.5)
    infoMon.setCursorPos(1,1)
    infoMon.setTextColour(colours.yellow)
    infoMon.write("NOW: " .. (currentTitle or "Unknown"):sub(1,w))
    infoMon.setCursorPos(1,2)
    infoMon.setTextColour(colours.lightBlue)
    infoMon.write(formatTime(currentTime).." / "..formatTime(videoDuration))
    infoMon.setCursorPos(1,5)
    infoMon.setTextColour(colours.orange)
    infoMon.write("UP NEXT:")
    for i=1,5 do
        if upcomingList and upcomingList[i] then
            infoMon.setCursorPos(1,5+i)
            infoMon.setTextColour(colours.white)
            infoMon.write("- "..upcomingList[i]:sub(1,w-2))
        end
    end
    infoMon.setCursorPos(1,12)
    infoMon.setTextColour(colours.green)
    infoMon.write("FPS: "..displayFps.." | Lat: "..currentLatency.."ms")
    infoMon.setCursorPos(1,13)
    infoMon.write("Buf: F["..#frameBuffer.."] A["..#audioBuffer.."]")
end

-- websocket
local ws, err = http.websocket("ws://skinnerm.duckdns.org:10000/ws")
if not ws then error("Connection failed: "..tostring(err)) end

-- calculate wall size
local totalCanvasW, totalCanvasH = 0,0
for _, m in ipairs(config.monitors) do
    local farEdgeX = (m.x_pos-1)*m.width + m.width
    local farEdgeY = (m.y_pos-1)*m.height + m.height
    if farEdgeX>totalCanvasW then totalCanvasW=farEdgeX end
    if farEdgeY>totalCanvasH then totalCanvasH=farEdgeY end
end
print("Scaling video to total wall size: "..totalCanvasW.."x"..(totalCanvasH*2))

ws.send(textutils.serialiseJSON({
    command="play",
    url="https://www.youtube.com/watch?v=QDm0SowsP6M",
    w=totalCanvasW,
    h=totalCanvasH,
    monitors=config.monitors
}))

-- audio helper
local dfpwm = require("cc.audio.dfpwm")
local decoder = dfpwm.make_decoder()

local function bytesToLong(str, idx)
    local val=0
    for i=0,7 do val = val*256 + string.byte(str,idx+i) end
    return val
end

-- audio loop
local function playAudioLoop()
    local speakersReady = {}
    for i, sp in ipairs(speakers) do speakersReady[i]=true end
    while true do
        if #audioBuffer>0 then
            local chunkObj = table.remove(audioBuffer,1)
            local pcm = decoder(chunkObj.chunk)
            for i, sp in ipairs(speakers) do
                if speakersReady[i] then
                    speakersReady[i]=false
                    parallel.waitForAny(function()
                        while not sp.playAudio(pcm) do
                            local _, evName, evSide = os.pullEvent("speaker_audio_empty")
                            if evSide==peripheral.getName(sp) then break end
                        end
                        speakersReady[i]=true
                    end)
                end
            end
            totalSamplesPlayed = totalSamplesPlayed + #pcm
        else
            sleep(0.01)
        end
    end
end

-- main loop
parallel.waitForAll(
    function() -- RECEIVER
        while true do
            local _, _, msg, isBin = os.pullEvent("websocket_message")
            if isBin then
                local head = sByte(msg,1)
                if head==70 then -- video
                    currentLatency=osEpoch("utc")-bytesToLong(msg,2)
                    table.insert(frameBuffer,msg)
                    if #frameBuffer>MAX_BUFFER then table.remove(frameBuffer,1) end
                elseif head==65 then -- audio
                    local ts = bytesToLong(msg,2)/1000 -- ms to sec
                    table.insert(audioBuffer,{ts=ts,chunk=msg:sub(10)})
                    if #audioBuffer>MAX_BUFFER then table.remove(audioBuffer,1) end
                end
            else
                local data=textutils.unserialiseJSON(msg)
                if data and data.type=="meta" then
                    currentTitle, currentPlaylist = data.title, data.playlist
                    upcomingList, videoDuration = data.upcoming, data.duration or 0
                    isStarted, totalSamplesPlayed, currentTime = false,0,0
                    frameBuffer,audioBuffer={},{}
                    updateInfo()
                end
            end
        end
    end,

    function() -- RENDERER
        local c143,c131="\143","\131"
        local lastFrameIdx=-1
        while true do
            if not isStarted and #frameBuffer>=START_THRESHOLD_FRAME and #audioBuffer>=START_THRESHOLD_AUDIO then
                isStarted=true
            end
            if #frameBuffer>0 then
                local audioTime = totalSamplesPlayed/AUDIO_RATE
                currentTime = audioTime
                local targetFrameIdx = math.floor(audioTime*TARGET_FPS)
                while #frameBuffer>1 and lastFrameIdx<targetFrameIdx do table.remove(frameBuffer,1); lastFrameIdx=lastFrameIdx+1 end
                local data = table.remove(frameBuffer,1)
                lastFrameIdx = lastFrameIdx+1
                if data then
                    local ptr = 10
                    for i=1,#monitorObjects do
                        local m = monitorObjects[i]
                        local mObj = m.obj
                        if sByte(data,ptr)==1 then ptr=ptr+1
                            for cIdx=1,16 do
                                mObj.setPaletteColor(cc_cols[cIdx], sByte(data,ptr)/255, sByte(data,ptr+1)/255, sByte(data,ptr+2)/255)
                                ptr=ptr+3
                            end
                        else ptr=ptr+1 end
                        for y=1,m.h do
                            local t,f,b = {},{},{}
                            local x=1
                            while x<=m.w do
                                local count,val=sByte(data,ptr),sByte(data,ptr+1)
                                ptr=ptr+2
                                local fg,bg = hex[bExtract(val,4,4)+1],hex[bExtract(val,0,4)+1]
                                for i2=1,count do
                                    if x>m.w then break end
                                    t[x],f[x],b[x] = ((y+x)%2==0) and c143 or c131, fg,bg
                                    x=x+1
                                end
                            end
                            mObj.setCursorPos(1,y)
                            mObj.blit(tConcat(t), tConcat(f), tConcat(b))
                        end
                    end
                     fpsCount=fpsCount+1
                    if os.clock()-lastFpsUpdate>=1 then
                        displayFps = fpsCount
                        lastFpsUpdate,fpsCount = os.clock(), 0
                        updateInfo()
                    end
                end
            end
            sleep(0)
        end
    end,

    function() -- AUDIO
        playAudioLoop()
    end,

    function() -- INPUT
        while true do
            local _, key = os.pullEvent("key")
            if key==keys.s then ws.send(textutils.serialiseJSON({command="skip"})) end
        end
    end
)
