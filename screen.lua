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

function computeXY(index)
  index = index + 0
  local y = math.floor(index / 40)
  local x = index % 40
  return x*4, y*2+1 -- displayed font is 4x2 chars or 8x8 pixels
end

local function drawchar(index, code, color)
  local colsw
  if code > 127 then
    colsw = true
    code = code - 128
  end
  local draw = sys.font[code] or sys.font[0]
  local x, y = computeXY(index)
  local fg, bg = palette[sys.ram.get(647) == 1 and color or sys.ram.get(646)], palette[sys.ram.get(53281)]
  if colsw then
    fg, bg = bg, fg
  end
  sys.gpu.setForeground(fg)
  sys.gpu.setBackground(bg)
  --component.proxy(component.list("sandbox")()).log(x, y, fg, bg, color, code, draw)
  sys.gpu.set(x+1, y, unicode.sub(draw, 1,4))
  sys.gpu.set(x+1, y+1, unicode.sub(draw, 6))
end

local buf
-- XXX: this will be slow with GPU buffers and painfully so without.
function screen.refresh()
  if sys.gpu.bitblt then -- we have buffer capability
    buf = buf or sys.gpu.allocateBuffer(160, 50)
    sys.gpu.setActiveBuffer(buf)
  end
  for i=1024, 2023, 1 do
    drawchar(i - 1024, sys.ram.get(i), sys.ram.get(55296 + i - 1024))
  end
  if sys.gpu.bitblt then
    sys.gpu.bitblt(0, 1, 1, 160, 50, buf)
    sys.gpu.setActiveBuffer(0)
  end
end

for i=1024, 2023, 1 do
  sys.ram.set(i, 32)
end
for i=55296, 56295, 1 do
  sys.ram.set(i, 14)
end
sys.ram.set(53281, 6)
sys.ram.set(646, 14)

screen.refresh()
--[[while true do
  computer.pullSignal(2)
  for i=1024, 2023, 1 do
    sys.ram.set(i, math.random(0, 26))
  end
  screen.refresh()
end]]

sys.screen = screen
