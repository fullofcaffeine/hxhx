-- hxhx Lua sys runtime shim: UtilityProcess is a tiny upstream sys-test helper.
local __hxhx_utility_env = {}
local function __hxhx_utility_arg(args, index)
  if args == nil then return "" end
  local value = args[index]
  if value == nil then return "" end
  return tostring(value)
end
local function __hxhx_codepoints(...)
  local out = {}
  for i = 1, select("#", ...) do
    local cp = select(i, ...)
    if cp <= 0x7f then
      out[#out + 1] = string.char(cp)
    elseif cp <= 0x7ff then
      out[#out + 1] = string.char(0xc0 + math.floor(cp / 0x40), 0x80 + (cp % 0x40))
    elseif cp <= 0xffff then
      out[#out + 1] = string.char(0xe0 + math.floor(cp / 0x1000), 0x80 + (math.floor(cp / 0x40) % 0x40), 0x80 + (cp % 0x40))
    else
      out[#out + 1] = string.char(0xf0 + math.floor(cp / 0x40000), 0x80 + (math.floor(cp / 0x1000) % 0x40), 0x80 + (math.floor(cp / 0x40) % 0x40), 0x80 + (cp % 0x40))
    end
  end
  return table.concat(out)
end
local function __hxhx_unicode_sequence(index, nfc)
  if index == 0 then return __hxhx_codepoints(0x0001) end
  if index == 1 then return __hxhx_codepoints(0x007f) end
  if index == 2 then return __hxhx_codepoints(0x0080) end
  if index == 3 then return __hxhx_codepoints(0x07ff) end
  if index == 4 then return __hxhx_codepoints(0x0800) end
  if index == 5 then return __hxhx_codepoints(0xd7ff) end
  if index == 6 then return __hxhx_codepoints(0xe000) end
  if index == 7 then return __hxhx_codepoints(0xfffd) end
  if index == 8 then return __hxhx_codepoints(0x10000) end
  if index == 9 then return __hxhx_codepoints(0x1ffff) end
  if index == 10 then return __hxhx_codepoints(0xfffff) end
  if index == 11 then return __hxhx_codepoints(0x100000) end
  if index == 12 then return __hxhx_codepoints(0x10ffff) end
  if index == 13 then return __hxhx_codepoints(0x1f602, 0x1f604, 0x1f619) end
  if index == 14 then
    if nfc then return __hxhx_codepoints(0x0227) end
    return __hxhx_codepoints(0x0061, 0x0307)
  end
  if index == 15 then
    if nfc then return __hxhx_codepoints(0x4e2d, 0x6587, 0xff0c, 0x306b, 0x307b, 0x3093, 0x3054) end
    return __hxhx_codepoints(0x4e2d, 0x6587, 0xff0c, 0x306b, 0x307b, 0x3093, 0x3053, 0x3099)
  end
  return ""
end
local function __hxhx_sequence_arg(args, index)
  local token = __hxhx_utility_arg(args, index)
  local mode = __hxhx_utility_arg(args, index + 1)
  local parsed = tonumber(token)
  if parsed ~= nil and string.match(token, "^%-?%d+$") then
    return __hxhx_unicode_sequence(parsed, mode == "nfc")
  end
  return token
end
local function __hxhx_read_chars(len)
  return io.read(tonumber(len) or 0) or ""
end
local function __hxhx_read_until(end_byte)
  local stop = tonumber(end_byte) or 0
  local out = {}
  while true do
    local ch = io.read(1)
    if ch == nil or string.byte(ch) == stop then break end
    out[#out + 1] = ch
  end
  return table.concat(out)
end
local function __hxhx_get_cwd()
  local handle = io.popen("pwd", "r")
  if handle == nil then return "" end
  local value = handle:read("*l") or ""
  handle:close()
  return value
end
local function __hxhx_runUtility(args)
  local command = __hxhx_utility_arg(args, 0)
  if command == "" then return end
  if command == "putEnv" then
    __hxhx_utility_env[__hxhx_utility_arg(args, 1)] = __hxhx_sequence_arg(args, 2)
    local tail = { length = 0 }
    local i = 4
    while args ~= nil and args[i] ~= nil do
      tail[i - 4] = args[i]
      tail.length = tail.length + 1
      i = i + 1
    end
    __hxhx_runUtility(tail)
    return
  end
  if command == "getCwd" then print(__hxhx_get_cwd()); return end
  if command == "getEnv" then print(__hxhx_utility_env[__hxhx_utility_arg(args, 1)] or os.getenv(__hxhx_utility_arg(args, 1)) or ""); return end
  if command == "checkEnv" then os.exit((__hxhx_utility_env[__hxhx_utility_arg(args, 1)] or os.getenv(__hxhx_utility_arg(args, 1)) or "") == __hxhx_utility_arg(args, 2) and 0 or 1) end
  if command == "environment" then print(__hxhx_utility_env[__hxhx_utility_arg(args, 1)] or os.getenv(__hxhx_utility_arg(args, 1)) or ""); return end
  if command == "exitCode" then os.exit(tonumber(__hxhx_utility_arg(args, 1)) or 0) end
  if command == "args" then print(__hxhx_utility_arg(args, 1)); return end
  if command == "println" then print(__hxhx_sequence_arg(args, 1)); return end
  if command == "print" then io.write(__hxhx_sequence_arg(args, 1)); io.flush(); return end
  if command == "trace" then print(__hxhx_sequence_arg(args, 1)); return end
  if command == "stdin.readLine" then print(io.read("*l") or ""); return end
  if command == "stdin.readString" then print(__hxhx_read_chars(__hxhx_utility_arg(args, 1))); return end
  if command == "stdin.readUntil" then print(__hxhx_read_until(__hxhx_utility_arg(args, 1))); return end
  if command == "stderr.writeString" then io.stderr:write(__hxhx_sequence_arg(args, 1)); io.stderr:flush(); return end
  if command == "stdout.writeString" then io.write(__hxhx_sequence_arg(args, 1)); io.flush(); return end
  if command == "programPath" then print(arg and arg[0] or ""); return end
end
local function main()
  __hxhx_runUtility(__hxhx_sys_args())
end
main()
