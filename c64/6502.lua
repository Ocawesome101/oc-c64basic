-- front end

-- cursor position stored locally because i can't figure out where the C64 does it
local cpos = 0
local eventQueue = {}
local ENABLE_LOG = true

local function pullEvent(timeout)
	local sig = table.pack(computer.pullSignal(timeout or math.huge))
	table.insert(eventQueue, sig)
end

local function pokeEvent()
	if #eventQueue == 0 then
		pullEvent()
	end
	return table.remove(eventQueue, 1)
end

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
		if cpos >= 960 then
			scroll()
		else
			cpos = cpos + 1
		end
	end
end

function print(t)
	write(tostring(t))
	cpos = cpos + (40 - (cpos % 40))
	if cpos >= 960 then
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
		local sig = pokeEvent()
		-- TODO: blink
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
local logHandle
if ENABLE_LOG then
	logHandle = assert(mount.open("/c64/cpu.log", "w"))
end

-- Load ROM
local handle = assert(mount.open("/c64/kernal.bin", "r"))
local str = ""
repeat
	local chunk = mount.read(handle, math.huge)
	str = str .. (chunk or "")
until not chunk
mount.close(handle)
for i=1, #str do
	sys.rom[i] = string.byte(str:sub(i, i))
end

-- Load BASIC ROM
local handle = assert(mount.open("/c64/basic.bin", "r"))
local str = ""
repeat
	local chunk = mount.read(handle, math.huge)
	str = str .. (chunk or "")
until not chunk
mount.close(handle)
for i=1, #str do
	sys.basicRom[i] = string.byte(str:sub(i, i))
end

-- yield to avoid "too long without yielding" errors
local function yield()
	pullEvent(0) -- this yields without discarding any event
	local evt = pokeEvent()
	local char
	if evt[1] == "key_down" or evt[1] == "key_up" then
		char = utf8.char(evt[3]):upper()
	end

	if evt[1] == "key_down" then
		local contains = false
		for _, v in pairs(sys.io.pressedKeys) do
			if v == char then
				contains = true
			end
		end
		if not contains then table.insert(sys.io.pressedKeys, char) end
	elseif evt[1] == "key_up" then
		local elemPos
		local contains = false
		for k, v in pairs(sys.io.pressedKeys) do
			if v == char then
				elemPos = k
			end
		end
		if elemPos then
			table.remove(sys.io.pressedKeys, elemPos)
		end
	end
end

-- registers
local pc = 0xE000
local a = 0
local x = 0
local y = 0
local sp = 0

-- flags
local fc, fz, fi, fd, fb, fv, fn = false, false, true, false, false, false, false

-- shortcuts for performance
local peek = sys.ram.get
local poke = sys.ram.set

local function debug(str)
	if ENABLE_LOG and sys.ocemu then
		sys.ocemu.log(str)
	elseif logHandle then
		mount.write(logHandle, str .. "\n")
	end
end

local function push(value)
	poke(0x100 + sp, value & 0xFF)
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

local function cmp(value, nocarry, overflow)
	fz = (value & 0xFF) == 0
	if nocarry ~= "nocarry" then fc = (value & 0xFF) ~= value end
	fn = (value & 0x80) ~= 0 -- todo
	if overflow == "overflow" then
		fv = value < -128 or value > 127
	end
end

local function php()
	local sr =
		((fn and 1 or 0) << 7) |
		((fv and 1 or 0) << 6) |
		--
		((fb and 1 or 0) << 4) |
		((fd and 1 or 0) << 3) |
		((fi and 1 or 0) << 2) |
		((fz and 1 or 0) << 1) |
		((fc and 1 or 0) << 0)
	push(sr)
end

local function plp()
	local sr = pop()
	fn = (sr & 0x80) ~= 0
	fv = (sr & 0x40) ~= 0
	--
	fb = (sr & 0x10) ~= 0
	fd = (sr & 0x08) ~= 0
	fi = (sr & 0x04) ~= 0
	fz = (sr & 0x02) ~= 0
	fc = (sr & 0x01) ~= 0
end

local function reset()
	pc = readAbsoluteAddr(0xFFFC) -- RESET vector
end
reset()


local function irq()
	-- push program counter and processor status
	push(pc & 0xFF)
	push((pc & 0xFF00) >> 8)
	php()
	fi = true -- disable interrupts
	pc = readAbsoluteAddr(0xFFFE) -- jump to IRQ vector
end

local operations = {
	[0x00] = function() -- BRK (implied)
		--os.exit(0)
		error(string.format("BRK at 0x%x", pc))
		sys.screen.refresh()
		while true do
			computer.pullSignal()
		end
	end,
	[0x05] = function() -- ORA (zeropage)
		pc = pc + 1
		local addr = peek(pc)
		a = a | peek(addr)
		cmp(a, "nocarry")
	end,
	[0x08] = function() -- PHP (implied)
		php()
	end,
	[0x09] = function() -- ORA (immediate)
		pc = pc + 1
		a = a | peek(pc)
		cmp(a, "nocarry")
	end,
	[0x0A] = function() -- ASL (implied)
		local bit7 = (a & 0x80) >> 7
		a = (a << 1)
		cmp(a, "nocarry")
		fc = bit7 == 1
	end,
	[0x0D] = function() -- ORA (absolute)
		local addr = readAbsoluteAddr(pc+1)
		pc = pc + 2
		a = a | peek(addr)
		cmp(a, "nocarry")
	end,
	[0x10] = function() -- BPL (relative)
		pc = pc + 1
		local rel = string.unpack("i1", string.char(peek(pc)))
		if not fn then
			pc = pc + rel
		end
	end,
	[0x16] = function() -- ASL (zeropage,X)
		pc = pc + 1
		local addr = (peek(pc) + x) & 0xFF
		local value = peek(addr)
		local bit7 = (value & 0x80) >> 7
		poke(addr, (value << 1) & 0xFF)
		cmp(value << 1, "nocarry")
		fc = bit7 == 1
	end,
	[0x18] = function() -- CLC (implied)
		fc = false
	end,
	[0x20] = function() -- JSR (absolute)
		local addr = readAbsoluteAddr(pc+1)
		pc = pc + 2
		pc = pc - 1
		push(pc & 0xFF)
		push((pc & 0xFF00) >> 8)
		pc = addr - 1
	end,
	[0x24] = function() -- BIT (zeropage)
		pc = pc + 1
		local addr = peek(pc)
		local value = peek(addr)
		fz = (value & a) == 0
		fn = (value & 0x80) ~= 0
		fv = (value & 0x40) ~= 0
	end,
	[0x28] = function() -- PLP (implied)
		plp()
	end,
	[0x29] = function() -- AND (immediate)
		pc = pc + 1
		a = a & peek(pc)
		cmp(a, "nocarry")
	end,
	[0x2A] = function() -- ROL (implied)
		local bit7 = (a & 0x80) >> 7
		local carry = fc and 1 or 0
		a = (a << 1) | carry
		cmp(a, "nocarry")
		fc = bit7 == 1
	end,
	[0x2C] = function() -- BIT (absolute)
		local addr = readAbsoluteAddr(pc+1)
		pc = pc + 2
		local value = peek(addr)
		fz = (value & a) == 0
		fn = (value & 0x80) ~= 0
		fv = (value & 0x40) ~= 0
	end,
	[0x30] = function() -- BMI (relative)
		pc = pc + 1
		local rel = string.unpack("i1", string.char(peek(pc)))
		if fn then
			pc = pc + rel
		end
	end,
	[0x38] = function() -- SEC (implied)
		fc = true
	end,
	[0x40] = function() -- RTI (implied)
		-- pull processor status and program counter
		plp()
		local high = pop()
		local low = pop()
		debug("RTI")
		pc = (high << 8) | low
	end,
	[0x46] = function() -- LSR (zeropage)
		pc = pc + 1
		local addr = peek(pc)
		local value = peek(addr)
		local bit0 = value & 1
		value = (value >> 1) | (bit0 << 7)
		fc = bit0 == 1
		cmp(a, "nocarry")
		poke(addr, value)
	end,
	[0x48] = function() -- PHA (implied)
		push(a)
	end,
	[0x49] = function() -- EOR (immediate)
		pc = pc + 1
		a = a ~ peek(pc)
	end,
	[0x4A] = function() -- LSR (implied)
		local bit0 = a & 1
		a = (a >> 1) | (bit0 << 7)
		cmp(a, "nocarry")
		fc = bit0 == 1
	end,
	[0x4C] = function() -- JMP (absolute)
		local addr = readAbsoluteAddr(pc+1)
		debug(string.format("JMP $%x", addr))
		pc = addr - 1
	end,
	[0x56] = function() -- LSR (zeropage,X)
		pc = pc + 1
		local addr = (peek(pc) + x) & 0xFF
		local value = peek(addr)
		local bit0 = value & 1
		value = (value >> 1) | (bit0 << 7)
		fc = bit0 == 1
		poke(addr, value)
	end,
	[0x58] = function() -- CLI (implied)
		fi = false -- enable maskable interrupts
	end,
	[0x60] = function() -- RTS (implied)
		local high = pop()
		local low = pop()
		debug("RTS")
		pc = (high << 8) | low + 1
	end,
	[0x65] = function() -- ADC (zeropage)
		pc = pc + 1
		local addr = peek(pc)
		a = a + peek(addr) + (fc and 1 or 0)
		cmp(a, nil, "overflow")
		debug(string.format("ADC $%x", addr))
	end,
	[0x68] = function() -- PLA (implied)
		a = pop()
	end,
	[0x69] = function() -- ADC (immediate)
		pc = pc + 1
		a = a + peek(pc) + (fc and 1 or 0)
		cmp(a, nil, "overflow")
		debug(string.format("ADC #$%x", peek(pc)))
	end,
	[0x6C] = function() -- JMP (indirect)
		local indirectAddr = readAbsoluteAddr(pc+1)
		local addr = readAbsoluteAddr(indirectAddr) -- TODO: account for the last byte vector bug (http://6502.org/tutorials/6502opcodes.html#JMP)
		debug(string.format("JMP ($%x) (= JMP $%x)", indirectAddr, addr))
		pc = addr - 1
	end,
	[0x70] = function() -- BVS (relative)
		pc = pc + 1
		local rel = string.unpack("i1", string.char(peek(pc)))
		if fv then
			pc = pc + rel
		end
	end,
	[0x78] = function() -- SEI (implied)
		fi = true -- disable maskable interrupts
	end,
	[0x84] = function() -- STY (zeropage)
		pc = pc + 1
		local addr = peek(pc)
		poke(addr, y)
		debug(string.format("STY $%x", addr))
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
		debug(string.format("STX $%x", addr))
	end,
	[0x88] = function() -- DEY (implied)
		y = y - 1
		cmp(y, "nocarry")
	end,
	[0x8A] = function() -- TXA (implied)
		a = x
		cmp(a, "nocarry")
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
	[0x90] = function() -- BCC (relative)
		pc = pc + 1
		local rel = string.unpack("i1", string.char(peek(pc)))
		if not fc then
			pc = pc + rel
		end
	end,
	[0x91] = function() -- STA (indirect indexed)
		pc = pc + 1
		local addr = readIndirectY(pc)
		poke(addr, a)
	end,
	[0x94] = function() -- STY (zeropage,X)
		pc = pc + 1
		local addr = (peek(pc) + x) & 0xFF
		poke(addr, y)
	end,
	[0x95] = function() -- STA (zeropage,X)
		pc = pc + 1
		local addr = (peek(pc) + x) & 0xFF
		poke(addr, a)
	end,
	[0x98] = function() -- TYA (implied)
		a = y
		cmp(a, "nocarry")
	end,
	[0x99] = function() -- STA (absolute,Y)
		local addr = readAbsoluteAddr(pc+1) + y
		pc = pc + 2
		poke(addr, a)
	end,
	[0x9A] = function() -- TXS (implied)
		sp = x
	end,
	[0x9D] = function() -- STA (absolute,X)
		local addr = readAbsoluteAddr(pc+1) + x
		pc = pc + 2
		poke(addr, a)
	end,
	[0xA0] = function() -- LDY (immediate)
		pc = pc + 1
		y = peek(pc)
		cmp(y, "nocarry")
	end,
	[0xA2] = function() -- LDX (immediate)
		pc = pc + 1
		x = peek(pc)
		cmp(x, "nocarry")
	end,
	[0xA4] = function() -- LDY (zeropage)
		pc = pc + 1
		local addr = peek(pc)
		y = peek(addr)
		cmp(y, "nocarry")
	end,
	[0xA5] = function() -- LDA (zeropage)
		pc = pc + 1
		local addr = peek(pc)
		a = peek(addr)
		cmp(a, "nocarry")
	end,
	[0xA6] = function() -- LDX (zeropage)
		pc = pc + 1
		local addr = peek(pc)
		x = peek(addr)
		cmp(x, "nocarry")
	end,
	[0xA8] = function() -- TAY (implied)
		y = a
		cmp(y, "nocarry")
	end,
	[0xA9] = function() -- LDA (immediate)
		pc = pc + 1
		a = peek(pc)
		cmp(a, "nocarry")
	end,
	[0xAC] = function() -- LDY (absolute)
		local addr = readAbsoluteAddr(pc+1)
		pc = pc + 2
		y = peek(addr)
		cmp(y, "nocarry")
	end,
	[0xAD] = function() -- LDA (absolute)
		local addr = readAbsoluteAddr(pc+1)
		pc = pc + 2
		a = peek(addr)
		cmp(a, "nocarry")
	end,
	[0xAE] = function() -- LDX (absolute)
		local addr = readAbsoluteAddr(pc+1)
		pc = pc + 2
		x = peek(addr)
		cmp(x, "nocarry")
	end,
	[0xAA] = function() -- TAX (implied)
		x = a
		cmp(x, "nocarry")
	end,
	[0xB0] = function() -- BCS (relative)
		pc = pc + 1
		local rel = string.unpack("i1", string.char(peek(pc)))
		if fc then
			pc = pc + rel
		end
	end,
	[0xB1] = function() -- LDA (indirect indexed)
		pc = pc + 1
		local addr = readIndirectY(pc)
		a = peek(addr)
		cmp(a, "nocarry")
		debug("lda " .. string.format("%x", addr) .. " ( y = " .. y .. ")")
	end,
	[0xB4] = function() -- LDY (zeropage,X)
		pc = pc + 1
		local addr = (peek(pc) + x) & 0xFF
		y = peek(addr)
		cmp(y, "nocarry")
	end,
	[0xB5] = function() -- LDA (zeropage,X)
		pc = pc + 1
		local addr = (peek(pc) + x) & 0xFF
		a = peek(addr)
		cmp(a, "nocarry")
	end,
	[0xB9] = function() -- LDA (absolute,Y)
		local addr = readAbsoluteAddr(pc+1) + y
		pc = pc + 2
		a = peek(addr)
		cmp(a, "nocarry")
	end,
	[0xBA] = function() -- TSX (implied)
		x = sp
	end,
	[0xBD] = function() -- LDA (absolute,X)
		local addr = readAbsoluteAddr(pc+1) + x
		pc = pc + 2
		a = peek(addr)
		cmp(a, "nocarry")
	end,
	[0xC0] = function() -- CPY (immediate)
		pc = pc + 1
		cmp(peek(pc) - y)
	end,
	[0xC4] = function() -- CPY (zeropage)
		pc = pc + 1
		local addr = peek(pc)
		cmp(peek(addr) - y)
		debug(string.format("CPY $%x -> CPY #%x (Y=0x%x)", addr, peek(addr), y))
	end,
	[0xC5] = function() -- CMP (zeropage)
		pc = pc + 1
		local addr = peek(pc)
		cmp(peek(addr) - a)
	end,
	[0xC6] = function() -- DEC (zeropage)
		pc = pc + 1
		local addr = peek(pc)
		local value = peek(addr)
		value = value - 1
		cmp(value, "nocarry")
		poke(addr, value & 0xFF)
	end,
	[0xC8] = function() -- INY (implied)
		y = y + 1
		cmp(y, "nocarry")
		debug("INY (y = " .. y .. ")")
	end,
	[0xC9] = function() -- CMP (immediate)
		pc = pc + 1
		cmp(peek(pc) - a)
	end,
	[0xCA] = function() -- DEX (implied)
		x = x - 1
		cmp(x, "nocarry")
	end,
	[0xCD] = function() -- CMP (absolute)
		local addr = readAbsoluteAddr(pc+1)
		pc = pc + 2
		cmp(peek(addr) - a)
	end,
	[0xD0] = function() -- BNE (relative)
		pc = pc + 1
		local rel = string.unpack("i1", string.char(peek(pc)))
		if not fz then
			pc = pc + rel
		end
	end,
	[0xD1] = function() -- CMP (indirect indexed)
		pc = pc + 1
		local addr = readIndirectY(pc)
		cmp(peek(addr) - a)
		debug(string.format("CMP ($%x),Y -> CMP $%x -> CMP #$%x (A = 0x%x)", peek(pc), addr, peek(addr), a))
	end,
	[0xD8] = function() -- CLD (implied)
		fd = false
	end,
	[0xDD] = function() -- CMP (absolute,X)
		local addr = readAbsoluteAddr(pc+1) + x
		pc = pc + 2
		cmp(peek(addr) - a)
	end,
	[0xE0] = function() -- CPX (immediate)
		pc = pc + 1
		cmp(peek(pc) - x)
	end,
	[0xE4] = function() -- CPX (zeropage)
		pc = pc + 1
		local addr = peek(pc)
		cmp(peek(addr) - x)
	end,
	[0xE5] = function() -- SBC (zeropage)
		pc = pc + 1
		local addr = peek(pc)
		a = a - peek(addr) - 1 + (fc and 1 or 0)
		cmp(a, nil, "overflow")
		debug(string.format("SBC $%x", addr))
	end,
	[0xE6] = function() -- INC (zeropage)
		pc = pc + 1
		local addr = peek(pc)
		local value = peek(addr)
		value = value + 1
		cmp(value, "nocarry")
		poke(addr, value)
	end,
	[0xE8] = function() -- INX (implied)
		x = x + 1
		cmp(x, "nocarry")
	end,
	[0xE9] = function() -- SBC (immediate)
		pc = pc + 1
		a = a - peek(pc) - 1 + (fc and 1 or 0)
		cmp(a, nil, "overflow")
		debug(string.format("SBC #$%x", peek(pc)))
	end,
	[0xEC] = function() -- CPX (absolute)
		local addr = readAbsoluteAddr(pc+1)
		pc = pc + 2
		cmp(peek(addr) - x)
	end,
	[0xF0] = function() -- BEQ (relative)
		pc = pc + 1
		local rel = string.unpack("i1", string.char(peek(pc)))
		if fz then
			pc = pc + rel
		end
	end,
}

local lastYield = computer.uptime()
local lastIrq = computer.uptime()
while true do
	-- TODO: yield at some time to receive events for interrupts and proper CHRIN routine
	if cpos >= 960 then
			--error(cpos)
			scroll()
	end
	local uptime = computer.uptime()

	local op = peek(pc)
	debug(string.format("%x: 0x%x", pc, op))
	if operations[op] then
		operations[op]()
	else
		error("Unknown opcode (" .. string.format("0x%x, pc = %x", op, pc) .. ") !")
	end
	if (pc & 0x0F) == 0 and uptime > lastYield + 0.1 then -- one second passed since last yield
		lastYield = uptime
		yield()
	end
	if uptime > lastIrq + 1/60 then -- 1/60s since last IRQ
		lastIrq = lastIrq + 1/60
		if not fi then
			irq()
			pc = pc - 1 -- account for the pc + 1 we do after
		end
	end
	a = a & 0xFF
	x = x & 0xFF
	y = y & 0xFF

	pc = pc + 1
	--os.sleep(0.01)
end
