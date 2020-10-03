-- memory emulation. ram-hungry, heh --

local ram = {}

sys.ram = {}
sys.rom = {}

function sys.ram.get(index)
  if index > 0xFFFF or index < 0 then
    error("attempt to get RAM index >64k or <0")
  end
  if index >= 0xE000 then
		return sys.rom[index - 0xE000 + 1] or 0
	end
  return ram[index] or 0
end

function sys.ram.set(index, byte)
  if byte > 255 then
    error("invalid RAM request: byte cannot be >255")
  end
  ram[index] = byte
end

for i=1, 0xFFFF do
	sys.ram[i] = 0 -- preallocate memory to both avoid nil values and hash map allocation
end
