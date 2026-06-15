local function hxhx_array(values)
  values = values or {}
  if values.push == nil then
    values.push = function(value)
      table.insert(values, value)
      return #values
    end
  end
  return values
end

local function hxhx_throw(value)
  error(value, 0)
end

local function hxhx_try(try_fn, catch_fn)
  local ok, result = pcall(try_fn)
  if ok then return result end
  return catch_fn(result)
end

local function __hxhx_signal()
  return { add = function(_) return nil end }
end

local function __hxhx_stub_instance()
  return {
    addCase = function(_) return nil end,
    run = function() return nil end,
    onProgress = __hxhx_signal(),
    onTestStart = __hxhx_signal()
  }
end

local function __hxhx_stub_class(_name)
  return {
    new = function(...) return __hxhx_stub_instance() end,
    create = function(...) return __hxhx_stub_instance() end,
    generateSpec = function(...) return hxhx_array({}) end,
    addIssueClasses = function(...) return nil end
  }
end

local __hxhx_reflect_method_keys = setmetatable({}, { __mode = "k" })
local function __hxhx_string_index_of(value, needle, start)
  local init = ((start or 0) + 1)
  local found = string.find(tostring(value or ""), tostring(needle or ""), init, true)
  if found == nil then return -1 end
  return found - 1
end
local function __hxhx_string_to_upper_case(value)
  return string.upper(tostring(value or ""))
end
local function __hxhx_string_to_lower_case(value)
  return string.lower(tostring(value or ""))
end
local function __hxhx_string_contains(value, needle)
  return string.find(tostring(value or ""), tostring(needle or ""), 1, true) ~= nil
end
local function __hxhx_reflect_string_method(name)
  if name == "indexOf" then
    local fn = function(self, needle, start)
      return __hxhx_string_index_of(self, needle, start)
    end
    __hxhx_reflect_method_keys[fn] = "String.indexOf"
    return fn
  end
  return nil
end
Reflect = Reflect or {}
Reflect.field = Reflect.field or function(obj, field)
  if obj == nil or field == nil then return nil end
  if type(obj) == "string" then return __hxhx_reflect_string_method(tostring(field)) end
  if type(obj) == "table" then return obj[field] end
  return nil
end
Reflect.callMethod = Reflect.callMethod or function(obj, method, args)
  if type(method) ~= "function" then return nil end
  args = args or {}
  local unpack_fn = table.unpack or unpack
  if __hxhx_reflect_method_keys[method] ~= nil then
    return method(obj, unpack_fn(args))
  end
  return method(unpack_fn(args))
end
Reflect.compareMethods = Reflect.compareMethods or function(a, b)
  if a == b then return true end
  local ka = __hxhx_reflect_method_keys[a]
  local kb = __hxhx_reflect_method_keys[b]
  return ka ~= nil and ka == kb
end
local function __hxhx_string_substr(value, pos, len)
  local s = tostring(value or "")
  local n = #s
  local p = tonumber(pos or 0) or 0
  if p < 0 then p = n + p end
  if p < 0 then p = 0 end
  local start_pos = p + 1
  if len == nil then return string.sub(s, start_pos) end
  local l = tonumber(len) or 0
  if l <= 0 then return "" end
  return string.sub(s, start_pos, start_pos + l - 1)
end
local function __hxhx_string_starts_with(value, prefix)
  local s = tostring(value or "")
  local p = tostring(prefix or "")
  return string.sub(s, 1, #p) == p
end
local __hxhx_string_mt = debug and debug.getmetatable and debug.getmetatable("") or getmetatable("") or {}
local __hxhx_string_old_index = __hxhx_string_mt.__index
__hxhx_string_mt.__index = function(value, key)
  if key == "indexOf" then return function(needle, start) return __hxhx_string_index_of(value, needle, start) end end
  if key == "contains" then return function(needle) return __hxhx_string_contains(value, needle) end end
  if key == "substr" then return function(pos, len) return __hxhx_string_substr(value, pos, len) end end
  if key == "startsWith" then return function(prefix) return __hxhx_string_starts_with(value, prefix) end end
  if key == "toUpperCase" then return function() return __hxhx_string_to_upper_case(value) end end
  if key == "toLowerCase" then return function() return __hxhx_string_to_lower_case(value) end end
  if type(__hxhx_string_old_index) == "table" then return __hxhx_string_old_index[key] end
  if type(__hxhx_string_old_index) == "function" then return __hxhx_string_old_index(value, key) end
  return nil
end
if debug and debug.setmetatable then debug.setmetatable("", __hxhx_string_mt) end
lua = lua or {}
lua.Lua = lua.Lua or {}
lua.Lua.type = lua.Lua.type or type

local __hxhx_stderr = {
  writeString = function(value)
    io.stderr:write(tostring(value or ""))
    return nil
  end,
  flush = function()
    io.stderr:flush()
    return nil
  end
}
local function __hxhx_sys_stderr()
  return __hxhx_stderr
end
local function __hxhx_sys_args()
  local out = {}
  local i = 1
  while arg ~= nil and arg[i] ~= nil do
    out[i - 1] = arg[i]
    i = i + 1
  end
  out.length = i - 1
  out.push = function(value)
    out[out.length] = value
    out.length = out.length + 1
    return out.length
  end
  return out
end
local function __hxhx_shell_quote(value)
  local s = tostring(value or "")
  return "'" .. string.gsub(s, "'", "'\"'\"'") .. "'"
end
local function __hxhx_line_stream(text)
  local source = tostring(text or "")
  local pos = 1
  return {
    readLine = function()
      if pos > #source then error("Eof", 0) end
      local next_pos = string.find(source, "\n", pos, true)
      local line
      if next_pos == nil then
        line = string.sub(source, pos)
        pos = #source + 1
      else
        line = string.sub(source, pos, next_pos - 1)
        pos = next_pos + 1
      end
      if string.sub(line, -1) == "\r" then line = string.sub(line, 1, -2) end
      return line
    end
  }
end
local function __hxhx_process_new(command, args)
  local cmd = tostring(command)
  for _, value in ipairs(args or {}) do
    cmd = cmd .. " " .. __hxhx_shell_quote(value)
  end
  local handle = io.popen(cmd .. " 2>&1; printf '\n__HXHX_EXIT_CODE__:%s\n' $?", "r")
  local output = ""
  local exit_code = 1
  if handle ~= nil then
    output = handle:read("*a") or ""
    local ok, _, code = handle:close()
    if type(ok) == "number" then exit_code = ok
    elseif ok == true then exit_code = 0
    elseif type(code) == "number" then exit_code = code end
    local marker_start, _, parsed = string.find(output, "\n__HXHX_EXIT_CODE__:(%d+)\n$")
    if parsed == nil then marker_start, _, parsed = string.find(output, "\n__HXHX_EXIT_CODE__:(%d+)$") end
    if parsed ~= nil then
      exit_code = tonumber(parsed) or exit_code
      output = string.sub(output, 1, marker_start - 1)
    end
  end
  return {
    stderr = __hxhx_line_stream(output),
    stdout = __hxhx_line_stream(output),
    exitCode = function() return exit_code end,
    close = function() return nil end
  }
end
Sys = Sys or {}
Sys.args = Sys.args or __hxhx_sys_args
Sys.stderr = Sys.stderr or __hxhx_sys_stderr
sys = sys or {}
sys.io = sys.io or {}
sys.io.Process = sys.io.Process or {}
sys.io.Process.new = sys.io.Process.new or __hxhx_process_new
