-- memory emulation. ram-hungry, heh --

local ram = {}
local rasterCounter = 0

sys.ram = {}
sys.rom = {}
sys.basicRom = {}

sys.io = {}
sys.io.pressedKeys = {}

function sys.ram.get(index)
  if index > 0xFFFF or index < 0 then
    error("attempt to get RAM index >64k or <0")
  end
  if index >= 0xA000 and index <= 0xBFFF then
    return sys.basicRom[index - 0xA000 + 1] or 0
  elseif index >= 0xE000 then
		return sys.rom[index - 0xE000 + 1] or 0
	elseif index == 0xD012 then -- raster counter
    -- TODO: look at the number of cycles from the CPU and compute the value from it
    rasterCounter = (rasterCounter + 1) & 0xFF
    return rasterCounter
  elseif index == 0xDD00 then -- data port A (CIA 2)
    return ram[index] | 0xC0 -- serial input is always high (inactive)
  end
  return ram[index]
end

-- 8 rows, 8 columns
local kbdMatrix = {
  "", "Q", "", " ", "2", "ctrl", "backspace", "1",
  "/", "^", "=", "rshift", "home", ";", "*", "£",
  ",", "@", ":", ".", "-", "L", "P", "+",
  "N", "O", "K", "M", "0", "J", "I", "9",
  "V", "U", "H", "B", "8", "G", "Y", "7",
  "X", "T", "F", "C", "6", "D", "R", "5",
  "lshift", "E", "S", "Z", "4", "A", "W", "3",
  "crsrUD", "f5", "f3", "f1", "f7", "crsrLR", "return", "delete"
}

function sys.ram.set(index, byte)
  if byte > 255 or byte < 0 then
    error("invalid RAM request: byte cannot be >255 or <0")
  end
  ram[index] = byte
  if sys.screen and index >= 0x0400 and index <= 0x7EF7 then
    sys.screen.editedChars[index] = true
    sys.screen.refresh()
  elseif index == 0xDC00 then -- data port A (CIA 1) = keyboard matrix write
    sys.ocemu.log(string.format("WRITE 0x%x to 0xDC00", byte))
    local column = 0
    local orgByte = byte
    while column < 8 do
      byte = byte >> 1
      column = column + 1
      if (byte & 0x1) == 0 then
        break
      end
    end
    column = 7 - column -- reverse column

    local columnBits = 0
    for i=1, 8 do
      local keyIdx = column*8+i
      local present = false
      for _, v in ipairs(sys.io.pressedKeys) do
        if v == kbdMatrix[keyIdx] then present = true end
      end
      if present then
        columnBits = columnBits | (1 << (8-i))
      end
    end
    ram[0xDC01] = columnBits
    if columnBits ~= 0 then
      sys.ocemu.log(string.format("0xDC01: %x (for %x)", columnBits, orgByte))
    end
  end
end

for i=1, 0xFFFF do
	ram[i] = 0 -- preallocate memory to both avoid nil values and hash map allocation
end
ram[0] = 0x2F -- default value for CPU reg 0
ram[1] = 0x27 -- default value for CPU reg 1
