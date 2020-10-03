#!/usr/bin/env lua5.3

-- (this is not part of the emulator stuff, just a tool to help development)

-- A tool to convert a commodore 64 (or other PETSCII machine) character rom dump into a font for oc-c64basic

--Usage: romdumptofont.py <character rom>
--  Outputs to stdout

-- english character rom can be found at http://www.zimmers.net/anonftp/pub/cbm/firmware/computers/c64/characters.901225-01.bin

-- (yes this is a modified version of my subpixel library)

local args = {...}

local brailleindex = {{0x1,0x8},{0x2,0x10},{0x4,0x20},{0x40,0x80}}

local bmpToBraille = function(bmp,w,h) -- Converts a bitmap (string of bytes) into unicode braille subpixels
  local outputstr = ""
  local c, i, tx, ty, ti, b, s, p
  for y=0, h-1 do
    for x=0, w-1 do
      local c = 0
      for sy=0, 3 do
        for sx=0, 1 do
          i = brailleindex[sy+1][sx+1]
          tx, ty = x * 2 + sx, y * 4 + sy
          ti = tx+ty*w*2
          b, s = ti//8,ti%8
          --print(i,tx,ty,ti,b,s)
          p = ((bmp:byte(b+1) or 0)>>(7-s)) % 2
          c = c + p * i
        end
      end
      outputstr = outputstr .. utf8.char(0x2800+c)
    end
  end
  return outputstr
end

if not args[1] then
  error("Usage: romdumptofont.py <character rom>\n  Outputs to stdout")
  return
end

local file = io.open(args[1])
if not file then
  error("Invalid file")
  return
end
print("-- font --\n\nsys.font = {\n[0]=")
for i = 1, 256 do
  local charh, charl = file:read(4) or string.char(0):rep(4), file:read(4) or string.char(0):rep(4)
  print("[[\n"..bmpToBraille(charh,4,1).."\n"..bmpToBraille(charl,4,1).."]],")
end
print("}")
file:close()