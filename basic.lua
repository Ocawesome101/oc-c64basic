-- TODO: basic interpreter, not Lua REPL. this might be hard. --
-- won't be strictly Commodore BASIC: some slight tweaks; among
-- others, the editor is invoked separately for simplicity's sake. It is
-- similar to Unix's 'ed'. --

--[[
local gsub = {
  {"FOR(.)[ ?](%d+)TO(%d+)DO(.+)END","for %1 do %2 end"}
}]]

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

sys.gpu.fill(1, 1, 160, 50, "A")
sys.screen.clear()

print("OPEN LUA V0")
while true do
  if cpos >= 960 then
    --error(cpos)
    scroll()
  end
  print("")
  print("READY.")
  pcall(load(read(), "=input", "bt", _G))
end
