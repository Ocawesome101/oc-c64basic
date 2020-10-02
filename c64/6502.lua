-- front end

-- cursor position stored locally because i can't figure out where the C64 does it
local cpos = 0
function scroll()
  sys.gpu.copy(1, 1, 160, 50, 0, -2)
  for i=1024, 2023, 1 do
    sys.ram.set(i, sys.ram.get(i+40))
  end
  for i=55296, 56295, 1 do
    sys.ram.set(i, sys.ram.get(i+40))
  end
  cpos = cpos - 40
  sys.screen.refresh()
end

local map
local function write(text)
  for c in text:lower():gmatch(".") do
    sys.ram.set(1024 + cpos, map(string.byte(c)) or 32)
    if cpos >= 999 then
      scroll()
    else
      cpos = cpos + 1
    end
  end
end

function print(t)
  write(tostring(t))
  cpos = cpos + (40 - (cpos % 40))
  if cpos >= 999 then
    scroll()
  end
  sys.screen.refresh()
end

map = function(k)
  if k >= 97 and k <= 122 then
    return k - 96
  else
    return k
  end
end

local function getkey()
  while true do
    local sig = table.pack(computer.pullSignal())
    if sig[1] == "key_down" then
      return map(sig[3]), string.char(sig[3])
    end
  end
end

local function read()
  local buf = ""
  local sc = cpos
  while true do
    cpos = sc
    write(buf.."\160 ")
    sys.screen.refresh()
    local key, char = getkey()
    if char == "\13" then
      cpos = sc
      write(buf .. "  ")
      print("")
      return buf
    elseif char == "\8" then
      if #buf > 0 then
        buf = buf:sub(0, -2)
      end
    elseif char ~= "\0" then
      buf = buf .. char
    end
  end
end

-- 6502 emulator

local kernalRom = {}
local ram = {}
for i=1, 0xFFFF do
	ram[i] = 0
end

local mount = sys.mounts[0]
local handle = assert(mount.open("/c64/init.bin", "r"))
local logHandle = assert(mount.open("/c64/cpu.log", "w"))
local str = ""
repeat
	local chunk = mount.read(handle, math.huge)
	str = str .. (chunk or "")
until not chunk
mount.close(handle)
for i=1, #str do
	sys.rom[i] = string.byte(str:sub(i, i))
end

-- yield to avoid "too long without yielding" errors
local function yield()
	coroutine.yield()
end

-- registers
local pc = 0xE000
local a = 0
local x = 0
local y = 0
local sp = 0

-- flags
local fc, fz, fi, fd, fb, fv, fn = false, false, false, false, false, false, false

-- High Level Emulation of the Kernal
local hle = {
	[0xFFD2] = function() -- CHROUT
		if a == 191 then
			--write('\r')
		elseif a == 78 then
			cpos = cpos + (40 - (cpos % 40))
		else
			write(string.char(a))
		end
		sys.screen.refresh()
		yield()
	end
}

-- shortcuts for performance
local peek = sys.ram.get
local poke = sys.ram.set

local function debug(str)
	mount.write(logHandle, str .. "\n")
end

local function push(value)
	poke(0x100 + sp, value)
	sp = (sp - 1) & 0xFF
	debug(string.format("(stack) push 0x%x", value))
end

local function pop()
	sp = (sp + 1) & 0xFF
	return peek(0x100 + sp)
end

local function readAbsoluteAddr(addr)
	return (peek(addr+1) << 8) | peek(addr)
end

local function readIndirectY(addr)
	local zp = peek(addr)
	local low = peek(zp)
	local high = peek(zp+1)
	return ((high << 8) | low) + y
end

local function cmp(value)
	fz = a == value
	fc = a >= value
	fn = 0 -- todo
end

local operations = {
	[0x00] = function() -- BRK (implied)
		--os.exit(0)
		--error(string.format("BRK at 0x%x", pc))
		while true do
			computer.pullSignal()
		end
	end,
	[0x20] = function() -- JSR (absolute)
		local addr = readAbsoluteAddr(pc+1)
		pc = pc + 2
		if hle[addr] then
			hle[addr]()
		else
			pc = pc - 1
			push(pc & 0xFF)
			push((pc & 0xFF00) >> 8)
			pc = addr - 1
		end
	end,
	[0x48] = function() -- PHA (implied)
		push(a)
	end,
	[0x4C] = function() -- JMP (absolute)
		local addr = readAbsoluteAddr(pc+1)
		debug(string.format("JMP $%x", addr))
		pc = addr - 1
	end,
	[0x60] = function() -- RTS (implied)
		local high = pop()
		local low = pop()
		debug("RTS")
		pc = (high << 8) | low + 1
	end,
	[0x68] = function() -- PLA (implied)
		a = pop()
	end,
	[0x84] = function() -- STY (zeropage)
		pc = pc + 1
		local addr = peek(pc)
		poke(addr, y)
	end,
	[0x85] = function() -- STA (zeropage)
		pc = pc + 1
		local addr = peek(pc)
		poke(addr, a)
	end,
	[0x86] = function() -- STX (zeropage)
		pc = pc + 1
		local addr = peek(pc)
		poke(addr, x)
	end,
	[0x8C] = function() -- STY (absolute)
		local addr = readAbsoluteAddr(pc+1)
		pc = pc + 2
		poke(addr, y)
	end,
	[0x8D] = function() -- STA (absolute)
		local addr = readAbsoluteAddr(pc+1)
		pc = pc + 2
		poke(addr, a)
	end,
	[0x8E] = function() -- STX (absolute)
		local addr = readAbsoluteAddr(pc+1)
		pc = pc + 2
		poke(addr, x)
	end,
	[0x9A] = function() -- TXS (implied)
		sp = x
	end,
	[0xA0] = function() -- LDY (immediate)
		pc = pc + 1
		y = peek(pc)
	end,
	[0xA2] = function() -- LDX (immediate)
		pc = pc + 1
		x = peek(pc)
	end,
	[0xB1] = function() -- LDA (indirect indexed)
		pc = pc + 1
		local addr = readIndirectY(pc)
		a = peek(addr)
		debug("lda " .. string.format("%x", addr) .. " ( y = " .. y .. ")")
	end,
	[0xBA] = function() -- TSX (implied)
		x = sp
	end,
	[0xBD] = function() -- LDA (absolute,X)
		local addr = readAbsoluteAddr(pc+1) + xs
		pc = pc + 2
		a = peek(addr)
	end,
	[0xC8] = function() -- INY (implied)
		y = y + 1
	end,
	[0xC9] = function() -- CMP (immediate)
		pc = pc + 1
		cmp(peek(pc))
	end,
	[0xD0] = function() -- BNE (relative)
		pc = pc + 1
		local rel = string.unpack("i1", string.char(peek(pc)))
		if not fz then
			pc = pc + rel
		end
	end,
	[0xE8] = function() -- INX (implied)
		x = x + 1
	end,
	[0xF0] = function() -- BEQ (relative)
		pc = pc + 1
		local rel = string.unpack("i1", string.char(peek(pc)))
		if fz then
			pc = pc + rel
		end
	end,
}

while true do
	if cpos >= 960 then
	    error(cpos)
	    scroll()
	end

	local op = peek(pc)
	debug(string.format("%x: 0x%x", pc, op))
	if operations[op] then
		operations[op]()
	else
		error("Unknown opcode (" .. string.format("0x%x, pc = %x", op, pc) .. ") !")
	end
	a = a & 0xFF
	x = x & 0xFF
	y = y & 0xFF

	pc = pc + 1
	--os.sleep(0.01)
end
