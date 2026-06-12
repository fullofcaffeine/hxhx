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
	  Lua Full1 frontier.
**/
class LuaERegRuntime {
	public static function lines():Array<String> {
		return SOURCE.split("\n");
	}

	static final SOURCE = '-- hxhx Lua runtime shim: focused EReg surface.
EReg = EReg or {}
EReg.new = EReg.new or function(pattern, options)
  local self = {
    pattern = tostring(pattern or ""),
    options = tostring(options or "")
  }
  self.match = function(value)
    local text = tostring(value or "")
    local haystack = text
    local needle = self.pattern
    if string.find(self.options, "i", 1, true) ~= nil then
      haystack = string.lower(haystack)
      needle = string.lower(needle)
    end
    return string.find(haystack, needle, 1, true) ~= nil
  end
  return self
end
EReg.create = EReg.create or EReg.new';
}
