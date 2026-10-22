-- Class metadata is separate from user fields. Only generated typed declarations
-- register members here; this runtime does not resolve Haxe names or types.
local __hxhx_lua_class_data = {}
local __hxhx_lua_instance_classes = setmetatable({}, {__mode = "k"})

local function __hxhx_lua_find_method(class, name)
  while class do
    local data = __hxhx_lua_class_data[class]
    local method = data.methods[name]
    if method then return method end
    class = data.parent
  end
end

local function __hxhx_lua_initialize(class, self, ...)
  local data = __hxhx_lua_class_data[class]
  if data.initializers then data.initializers(self) end
  if data.constructor then
    data.constructor(self, ...)
  elseif data.parent then
    __hxhx_lua_initialize(data.parent, self, ...)
  end
end

local function __hxhx_lua_defaults(class, self)
  local data = __hxhx_lua_class_data[class]
  if data.parent then __hxhx_lua_defaults(data.parent, self) end
  if data.defaults then data.defaults(self) end
end

local function __hxhx_lua_class()
  local class = {}
  local data = {methods = {}}
  __hxhx_lua_class_data[class] = data
  class.new = function(...)
    local bound = {}
    local self = setmetatable({}, {
      __index = function(receiver, name)
        local method = __hxhx_lua_find_method(class, name)
        if not method then return nil end
        local cached = bound[method]
        if not cached then
          cached = function(...) return method(receiver, ...) end
          bound[method] = cached
        end
        return cached
      end
    })
    __hxhx_lua_instance_classes[self] = class
    __hxhx_lua_defaults(class, self)
    __hxhx_lua_initialize(class, self, ...)
    return self
  end
  return class
end

local function __hxhx_lua_parent(class, parent)
  __hxhx_lua_class_data[class].parent = parent
end

local function __hxhx_lua_method(class, name, method)
  __hxhx_lua_class_data[class].methods[name] = method
end

local function __hxhx_lua_constructor(class, constructor)
  __hxhx_lua_class_data[class].constructor = constructor
end

local function __hxhx_lua_field_defaults(class, initialize)
  __hxhx_lua_class_data[class].defaults = initialize
end

local function __hxhx_lua_field_initializers(class, initialize)
  __hxhx_lua_class_data[class].initializers = initialize
end

-- Matching follows the registered class graph and cannot be forged by user fields.
local function __hxhx_lua_is_instance(value, expected)
  local class = __hxhx_lua_instance_classes[value]
  while class do
    if class == expected then return true end
    class = __hxhx_lua_class_data[class].parent
  end
  return false
end
