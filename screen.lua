-- screen I/O --

sys.dofile(0, "font.lua")

local screen = {}
-- color palette taken from VICE with no CRT emulation filter
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
-- If VRAM is available, this containst the VRAM buffers for every character
local charBuffers = {}

function computeXY(index)
  local y = math.floor(index / 40)
  local x = index % 40
  return x*4, y*2+1 -- displayed font is 4x2 chars or 8x8 pixels
end

local function generateCharBuffer(code, fg, bg)
  if charBuffers[code+1] then
    if charBuffers[code+1][2] == fg and charBuffers[code+1][3] == bg then
      return charBuffers[code+1][1]
    end
  end
  sys.debug("Generate char buffer for " .. code .. ", " .. fg .. ", " .. bg)
  local charBuf = (charBuffers[code+1] or {sys.gpu.allocateBuffer(4, 2)})[1]
  charBuffers[code+1] = { charBuf, fg, bg }
  local colsw
  if code > 127 then
    colsw = true
    code = code - 128
  end
  if colsw then
    fg, bg = bg, fg
  end
  sys.gpu.setActiveBuffer(charBuf)
  sys.gpu.inBuffer = true
  sys.gpu.setForeground(fg)
  sys.gpu.setBackground(bg)
  sys.gpu.set(1, 1, unicode.sub(sys.font[code], 1,4))
  sys.gpu.set(1, 2, unicode.sub(sys.font[code], 6))
  sys.gpu.inBuffer = false
  sys.gpu.setActiveBuffer(0)
  return charBuf
end

local function drawchar(index, code, color)
  local draw = sys.font[code] or sys.font[0]
  local x, y = computeXY(index)
  local fg, bg = palette[sys.ram.get(647) == 1 and color or sys.ram.get(646)], palette[sys.ram.get(53281)]
  if sys.gpu.bitblt then -- if the OpenComputers version supports GPU buffers
    local buf = generateCharBuffer(code, fg, bg)
    sys.gpu.bitblt(0, x+1, y, 4, 2, buf)
  else
    local colsw = false
    if code > 127 then
      colsw = true
      code = code - 128
    end
    if colsw then
      fg, bg = bg, fg
    end
    sys.gpu.setForeground(fg)
    sys.gpu.setBackground(bg)
    --component.proxy(component.list("sandbox")()).log(x, y, fg, bg, color, code, draw)
    sys.gpu.set(x+1, y, unicode.sub(draw, 1,4))
    sys.gpu.set(x+1, y+1, unicode.sub(draw, 6))
  end
end

screen.editedChars = {}
for i=1024, 2023 do screen.editedChars[i] = true end

local buf
-- XXX: this will be slow with GPU buffers and painfully so without.
function screen.refresh()
  for i=1024, 2023, 1 do
    if screen.editedChars[i] == true then
      drawchar(i - 1024, sys.ram.get(i), sys.ram.get(55296 + i - 1024))
    end
  end
  screen.editedChars = {}
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
