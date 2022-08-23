-- basics --

_G.sys = {}

sys.ocemu = component.proxy((component.list("ocemu", true)()))
sys.gpu = component.proxy((component.list("gpu", true)()))
sys.mounts = {[0] = component.proxy(computer.getBootAddress())}
sys.gpu.bind((component.list("screen", true)()))

-- optimise setBackground and setForeground (this saves a bit of call budget)
local _setBackground = sys.gpu.setBackground
local _setForeground = sys.gpu.setForeground
local cur_bg, cur_fg = -1, -1
function sys.gpu.setBackground(value)
  if cur_bg ~= value or sys.gpu.inBuffer then
    _setBackground(value)
    if not sys.gpu.inBuffer then cur_bg = value end
  end
end

function sys.gpu.setForeground(value)
  if cur_fg ~= value or sys.gpu.inBuffer then
    _setForeground(value)
    if not sys.gpu.inBuffer then cur_fg = value end
  end
end

local ENABLE_LOG = true
function sys.debug(str)
	if ENABLE_LOG and sys.ocemu then
		sys.ocemu.log(str)
	elseif logHandle then
		mount.write(logHandle, str .. "\n")
	end
end

-- loadfile
function sys.loadfile(drv, file)
  checkArg(1, file, "string")
  local handle = assert(sys.mounts[drv].open(file))
  local data = ""
  repeat
    local chunk = sys.mounts[drv].read(handle, math.huge)
    data = data .. (chunk or "")
  until not chunk
  sys.mounts[drv].close(handle)
  if file:sub(-4) == ".lua" then
    return load(data, "="..file, "bt", _G)
  else
    return function() return sys.run(data) end
  end
end

function sys.dofile(d,f) return assert(sys.loadfile(d,f))() end

sys.dofile(0, "mapper.lua")
sys.dofile(0, "screen.lua")
sys.dofile(0, "c64/6502.lua")
