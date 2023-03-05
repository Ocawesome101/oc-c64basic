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
  if index >= 0xDC00 and index <= 0xDC00 then
    sys.ocemu.log(string.format("READ from 0x%x", index))
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
  "crsrUD", "f5", "f3", "f1", "f7", "crsrLR", "return", "delete",
  "lshift", "E", "S", "Z", "4", "A", "W", "3",
  "X", "T", "F", "C", "6", "D", "R", "5",
  "V", "U", "H", "B", "8", "G", "Y", "7",
  "N", "O", "K", "M", "0", "J", "I", "9",
  ",", "@", ":", ".", "-", "L", "P", "+",
  "/", "^", "=", "rshift", "home", ";", "*", "£",
  "", "Q", "", " ", "2", "ctrl", "backspace", "1",
}

function sys.ram.set(index, byte)
  if byte > 255 or byte < 0 then
    sys.ocemu.log("invalid RAM request: byte cannot be >255 or <0, got " .. byte)
    sys.ocemu.log(debug.traceback("invalid RAM request"))
    error("dead")
  end
  ram[index] = byte
  if sys.screen and index >= 0x0400 and index <= 0x7EF7 then
    sys.screen.editedChars[index] = true
    sys.screen.refresh()
  elseif index == 0xDC00 then -- data port A (CIA 1) = keyboard matrix write
    --sys.ocemu.log(string.format("WRITE 0x%x to 0xDC00", byte))
    local enabledColumns = {}
    local orgByte = byte
    for column=8, 1, -1 do
      if (byte & 0x80) == 0 then
        enabledColumns[column] = true
      else
        enabledColumns[column] = false
      end
      if column ~= 8 or true then
        byte = byte << 1
      end
    end

    local columnBits = 0xFF
    for i=1, 8 do
      for column=1, 7 do
        local keyIdx = (column-1)*8+i
        local present = false
        for _, v in ipairs(sys.io.pressedKeys) do
          if v == kbdMatrix[keyIdx] then present = true end
        end
        if present and enabledColumns[column] then
          columnBits = columnBits & ~(1 << (8-i))
        end
      end
    end
    ram[0xDC01] = columnBits
    if true then
      sys.ocemu.log(string.format("0xDC01: %x (for %x)", columnBits, orgByte))
    end
  elseif index == 0xDC01 then -- data port B (CIA 1)
    -- TODO
  elseif index == 0xDC02 then -- data direction A
    --sys.ocemu.log(string.format("WRITE 0x%x to 0xDC02", byte))
  elseif index == 0xDC03 then -- data direction B
    --sys.ocemu.log(string.format("WRITE 0x%x to 0xDC03", byte))
  end
  if index >= 0xDC00 and index <= 0xDCFF then
    sys.ocemu.log(string.format("WRITE 0x%x to 0x%x", byte, index))
  end
end

for i=1, 0xFFFF do
	ram[i] = 0 -- preallocate memory to both avoid nil values and hash map allocation
end
ram[0] = 0x2F -- default value for CPU reg 0
ram[1] = 0x27 -- default value for CPU reg 1
