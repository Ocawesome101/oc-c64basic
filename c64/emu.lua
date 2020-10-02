local kernalRom = {}
local ram = {}
for i=1, 0xFFFF do
	ram[i] = 0
end

local rom = io.open("init.bin")
local str = rom:read("*a")
-- not really the kernal, more like init code
for i=1, #str do
	kernalRom[i] = string.byte(str:sub(i, i))
end
rom:close()

function peek(addr)
	if addr >= 0xE000 then
		return kernalRom[addr - 0xE000 + 1] or 0
	end
	return ram[addr + 1] or 0
end

function poke(addr, value)
	ram[addr + 1] = value & 0xFF
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
			io.write('\r')
		elseif a == 78 then
			io.write('\n')
		else
			io.write(string.char(a))
		end
	end
}

local function push(value)
	poke(0x100 + sp, value)
	sp = (sp - 1) & 0xFF
end

local function pop()
	sp = (sp + 1) & 0xFF
	return peek(0x100 + sp)
end

local function readAbsoluteAddr(addr)
	return (peek(addr+1) << 8) | peek(addr)
end

local function cmp(value)
	fz = a == value
	fc = a >= value
	fn = 0 -- todo
end

local operations = {
	[0x00] = function() -- BRK (implied)
		os.exit(0)
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
	[0x60] = function() -- RTS (implied)
		local high = pop()
		local low = pop()
		pc = (high << 8) | low + 1
	end,
	[0x68] = function() -- PLA (implied)
		a = pop()
	end,
	[0x9A] = function() -- TXS (implied)
		sp = x
	end,
	[0xA2] = function() -- LDX (immediate)
		pc = pc + 1
		x = peek(pc)
	end,
	[0xBA] = function() -- TSX (implied)
		x = sp
	end,
	[0xBD] = function() -- LDA (absolute,X)
		local addr = readAbsoluteAddr(pc+1) + x
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
	local op = peek(pc)
	--print(string.format("%x: 0x%x", pc, op))
	if operations[op] then
		operations[op]()
	else
		print("Unknown opcode (" .. string.format("0x%x") .. ") !")
	end
	a = a & 0xFF
	x = x & 0xFF
	y = y & 0xFF

	pc = pc + 1
	os.sleep(0.01)
end