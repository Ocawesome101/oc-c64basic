-- memory emulation. ram-hungry, heh --

local ram = {}

sys.ram = {}
function sys.ram.get(index)
  if index > 0xFFFF or index < 0 then
    error("attempt to get RAM index >64k or <0")
  end
  return ram[index] or 0
end

function sys.ram.set(index, byte)
  if byte > 255 or byte < 0 then
    error("invalid RAM request: byte cannot be >255 or <0")
  end
  ram[index] = byte
end
