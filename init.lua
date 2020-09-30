-- basics --

_G.sys = {}

sys.gpu = component.proxy((component.list("gpu", true)()))
sys.mounts = {[0] = component.proxy(computer.getBootAddress())}
sys.gpu.bind((component.list("screen", true)()))

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

sys.dofile(0, "ram.lua")
sys.dofile(0, "screen.lua")
sys.dofile(0, "basic.lua")
