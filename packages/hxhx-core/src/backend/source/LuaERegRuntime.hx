package backend.source;

/**
	Repo-owned Lua runtime support for the narrow `EReg` surface exercised by
	upstream Lua misc projects.

	Why
	- Stage3 Lua source emission renders `new EReg(pattern, options)` as
	  `EReg.new(pattern, options)`.
	- The upstream Issue10979 runner uses that constructor and then calls
	  `.match(actual)` while validating a child Lua process error message.
	- Keeping this support in a target runtime module avoids adding another
	  backend-emitter inline stub while the broader runtime extraction work continues.

	What
	- Provides `EReg.new(pattern, options)` and `EReg.create` aliases.
	- Provides the focused instance `match(value)` method needed by the current
	  Lua Full1 frontier. The matcher translates the small Haxe-regex subset
	  exercised by this gate to Lua patterns while preserving plain literal cases.
**/
class LuaERegRuntime {
	public static function lines():Array<String> {
		return SOURCE.split("\n");
	}

	static final SOURCE = '-- hxhx Lua runtime shim: focused EReg surface.
EReg = EReg or {}
local function __hxhx_ereg_escape_lua_pattern(ch)
  if string.find("^$()%.[]*+-?", ch, 1, true) ~= nil then return "%" .. ch end
  return ch
end
local function __hxhx_ereg_lua_pattern(pattern)
  local raw = tostring(pattern or "")
  local out = {}
  local i = 1
  while i <= #raw do
    local ch = string.sub(raw, i, i)
    if ch == "\\\\" then
      local next_ch = string.sub(raw, i + 1, i + 1)
      if next_ch == "" then
        out[#out + 1] = "\\\\"
      elseif next_ch == "d" or next_ch == "D" or next_ch == "s" or next_ch == "S" or next_ch == "w" or next_ch == "W" then
        out[#out + 1] = "%" .. next_ch
        i = i + 1
      else
        out[#out + 1] = __hxhx_ereg_escape_lua_pattern(next_ch)
        i = i + 1
      end
    elseif ch == "%" or ch == "-" then
      out[#out + 1] = "%" .. ch
    else
      out[#out + 1] = ch
    end
    i = i + 1
  end
  return table.concat(out)
end
EReg.new = EReg.new or function(pattern, options)
  local self = {
    pattern = tostring(pattern or ""),
    options = tostring(options or "")
  }
  self.match = function(value)
    local text = tostring(value or "")
    local haystack = text
    local needle = __hxhx_ereg_lua_pattern(self.pattern)
    if string.find(self.options, "i", 1, true) ~= nil then
      haystack = string.lower(haystack)
      needle = string.lower(needle)
    end
    return string.find(haystack, needle) ~= nil
  end
  return self
end
EReg.create = EReg.create or EReg.new';
}
