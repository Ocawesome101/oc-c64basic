-- screen I/O --

sys.dofile(0, "font.lua")

local screen = {}
-- color palette taken from VICE with no CRT emuation filter
local palette = {
  [0] = 0x000000,
  [1] = 0xffffff,
  [2] = 0xb5685e,
  [3] = 0xa9f3ff,
  [4] = 0xcd6fd4,
  [5] = 0x89e581,
  [6] = 0x6953f5,
  [7] = 0xffff7b,
  [8] = 0xc69232,
  [9] = 0x8d7900,
  [10]= 0xf5ab96,
  [11]= 0x818181,
  [12]= 0xb6b6b6,
  [13]= 0xcdffc6,
  [14]= 0xb19eff,
  [15]= 0xe0e0e0
}

local lfg, lbg = palette[1], palette[0] -- last foreground and background, to reduce needed component calls

-- memory innefficient: yes. faster: also yes, so if we have the ram lets do it
local screenChars, screenColsfg, screenColsbg, getSetCharBuffer
if computer.freeMemory() > 8000 then -- 8k ought to be enough
  -- yes tables exist but they succ memory, and were dealing with single bytes here so anything else is overkill
  screenChars = string.rep(string.char(0), 1000)
  screenColsfg = string.rep(string.char(0), 1000)
  screenColsbg = string.rep(string.char(0), 1000)

  getSetCharBuffer = function(index, code, fgi, bgi) -- get/set/check whether this character needs to be changed
    index = index % 1000
    local sc, sfg, sbg = screenChars:byte(index+1), screenColsfg:byte(index+1), screenColsbg:byte(index+2)
    if sc == code and sfg == fgi and sbg == bgi then
      return false
    end
    screenChars = screenChars:sub(1,index+1) .. string.char(code % 256) .. screenChars:sub(index+3)
    screenColsfg = screenColsfg:sub(1,index+1) .. string.char(fgi % 256) .. screenColsfg:sub(index+3)
    screenColsbg = screenColsbg:sub(1,index+1) .. string.char(bgi % 256) .. screenColsbg:sub(index+3)
    --sys.gpu.set(1,1,tostring(#screenChars)..","..tostring(#screenColsfg)..","..tostring(#screenColsbg).."              ")
    return true
  end
end

function computeXY(index)
  local y = math.floor(index / 40)
  local x = index % 40
  return x*4, y*2+1 -- displayed font is 4x2 chars or 8x8 pixels
end

local function drawchar(index, code, color)
  local doDraw = true
  local colsw
  local fgi, bgi = sys.ram.get(647) == 1 and color or sys.ram.get(646), sys.ram.get(53281)
  if screenChars ~= nil then
    doDraw = getSetCharBuffer(index, code, fgi, bgi)
  end
  if doDraw then
    local fg, bg = palette[fgi], palette[bgi]
    local draw = sys.font[code] or sys.font[63] or sys.font[0]
    local x, y = computeXY(index)
    if colsw then
      fg, bg = bg, fg
    end
    if fg ~= lfg then
      sys.gpu.setForeground(fg)
    end
    if bg ~= lbg then
      sys.gpu.setBackground(bg)
    end
    lfg = fg
    lbg = bg
    --component.proxy(component.list("sandbox")()).log(x, y, fg, bg, color, code, draw)
    sys.gpu.set(x+1, y, unicode.sub(draw, 1,4))
    sys.gpu.set(x+1, y+1, unicode.sub(draw, 6,9))
  --else
  --  local x, y = computeXY(index)
  --  sys.gpu.set(x+1, y, string.char(code+64)) -- testing
  end
end

local buf
-- XXX: this will be slow with GPU buffers and painfully so without.
function screen.refresh()
  if sys.gpu.bitblt then -- we have buffer capability
    buf = buf or sys.gpu.allocateBuffer(160, 50)
    sys.gpu.setActiveBuffer(buf)
  end
  --sys.gpu.fill(1, 1, 160, 50, " ") -- this shouldnt be needed, nor should it work, but it is/does
  for i=1024, 2023, 1 do
    drawchar(i - 1024, sys.ram.get(i), sys.ram.get(55296 + i - 1024))
  end
  if sys.gpu.bitblt then
    sys.gpu.bitblt(0, 1, 1, 160, 50, buf)
    sys.gpu.setActiveBuffer(0)
  end
end

function screen.clear()
  for i=1024, 2023, 1 do
    sys.ram.set(i, 32)
  end
  for i=55296, 56295, 1 do
    sys.ram.set(i, 14)
  end
  sys.ram.set(53281, 6)
  sys.ram.set(646, 14)
  screenChars = string.rep(string.char(0), 1000)
  screenColsfg = string.rep(string.char(0), 1000)
  screenColsbg = string.rep(string.char(0), 1000)
  screen.refresh()
end

function screen.clearbuffer()
  screenChars = string.rep(string.char(0), 1000)
  screenColsfg = string.rep(string.char(0), 1000)
  screenColsbg = string.rep(string.char(0), 1000)
end

screen.clear()
--[[while true do
  computer.pullSignal(2)
  for i=1024, 2023, 1 do
    sys.ram.set(i, math.random(0, 26))
  end
  screen.refresh()
end]]

sys.screen = screen
