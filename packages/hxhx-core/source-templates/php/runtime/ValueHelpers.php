function __hxhx_post_update_var(&$value, $delta) {
  $old = $value;
  $value = __hxhx_is_int64($old) ? __hxhx_int64_add($old, $delta) : $old + $delta;
  return $old;
}
function __hxhx_copy_value($value) {
  if (__hxhx_is_point3($value)) return $value;
  if (is_object($value) && property_exists($value, "__hx_value")) return clone $value;
  return $value;
}
function __hxhx_abstract_value($value) {
  if (!is_object($value)) return $value;
  if (property_exists($value, "__hx_value")) return __hxhx_abstract_value($value->__hx_value);
  if (property_exists($value, "value")) {
    $class = get_class($value);
    if ($class === "AbstractBase" || substr($class, -13) === "\\AbstractBase") return __hxhx_abstract_value($value->value);
  }
  return $value;
}
function __hxhx_construct_like($sample, ...$args) {
  $first = count($args) > 0 ? $args[0] : null;
  if (is_string($sample)) return $first === null ? "" : strval($first);
  if (is_int($sample)) return $first === null ? 0 : intval($first);
  if (is_float($sample)) return $first === null ? 0.0 : floatval($first);
  if (is_bool($sample)) return $first === null ? false : boolval($first);
  if (is_object($sample)) {
    $class = get_class($sample);
    if (class_exists($class)) return new $class(...$args);
  }
  return $first;
}
function __hxhx_array_push(&$array, $value) {
  if ($array instanceof __HxArray) {
    $array[] = $value;
    return count($array->toArray());
  }
  if (is_object($array) && property_exists($array, "__hx_value")) {
    if ($array->__hx_value instanceof __HxArray) return __hxhx_array_push($array->__hx_value, $value);
    if (!is_array($array->__hx_value)) $array->__hx_value = [];
    $array->__hx_value[] = $value;
    return count($array->__hx_value);
  }
  $array[] = $value;
  return count($array);
}
function __hxhx_array_pop(&$array) {
  if ($array instanceof __HxArray) return $array->pop();
  if (is_object($array) && property_exists($array, "__hx_value")) {
    if ($array->__hx_value instanceof __HxArray) return __hxhx_array_pop($array->__hx_value);
    if (!is_array($array->__hx_value) || count($array->__hx_value) === 0) return null;
    return array_pop($array->__hx_value);
  }
  if (!is_array($array) || count($array) === 0) return null;
  return array_pop($array);
}
function __hxhx_array_pop_value($array) {
  if ($array instanceof __HxArray) $array = $array->toArray();
  if (!is_array($array) || count($array) === 0) return null;
  return array_pop($array);
}
function __hxhx_map_comprehension($iterable, $projector) {
  $map = new Map();
  if ($iterable instanceof __HxArray) $iterable = $iterable->toArray();
  if (!is_array($iterable) && !($iterable instanceof \Traversable)) return $map;
  foreach ($iterable as $item) {
    $projectItem = is_string($item) ? new class($item) {
      public $__hx_string_value;
      public function __construct($value) { $this->__hx_string_value = strval($value); }
      public function toUpperCase() { return strtoupper($this->__hx_string_value); }
      public function toLowerCase() { return strtolower($this->__hx_string_value); }
      public function __toString() { return $this->__hx_string_value; }
    } : $item;
    $pair = $projector($projectItem);
    if ($pair instanceof __HxArray) $pair = $pair->toArray();
    if (!is_array($pair)) continue;
    $values = array_values($pair);
    if (count($values) >= 2) {
      $key = is_object($values[0]) && property_exists($values[0], "__hx_string_value") ? $values[0]->__hx_string_value : $values[0];
      $value = is_object($values[1]) && property_exists($values[1], "__hx_string_value") ? $values[1]->__hx_string_value : $values[1];
      $map->set($key, $value);
    }
  }
  return $map;
}
function __hxhx_to_template_wrap($value) {
  if (is_object($value) && get_class($value) === "TemplateWrap") return __hxhx_copy_value($value);
  return new TemplateWrap($value);
}
function __hxhx_to_meter($value) {
  if (is_object($value) && get_class($value) === "Meter") return __hxhx_copy_value($value);
  return new Meter($value);
}
function __hxhx_to_kilometer($value) {
  if (is_object($value) && get_class($value) === "Kilometer") return __hxhx_copy_value($value);
  if (is_object($value) && get_class($value) === "Meter" && property_exists($value, "__hx_value")) return new Kilometer($value->__hx_value / 1000.0);
  return new Kilometer($value);
}
function __hxhx_to_my_abstract_counter($value) {
  if (is_object($value) && get_class($value) === "MyAbstractCounter") return __hxhx_copy_value($value);
  return new MyAbstractCounter($value);
}
function __hxhx_to_my_hash($values, $stringKeys) {
  if (is_object($values) && get_class($values) === "MyHash") return __hxhx_copy_value($values);
  $hash = new MyHash();
  if ($values instanceof __HxArray) $values = $values->toArray();
  if (!is_array($values)) return $hash;
  $count = count($values);
  for ($i = 0; $i + 1 < $count; $i += 2) {
    $key = $values[$i];
    $value = $values[$i + 1];
    $hash->set($stringKeys ? __hxhx_to_string_value($key) : "_s" . __hxhx_add_string($key), $value);
  }
  return $hash;
}
function __hxhx_to_string_value($value) {
  if (is_string($value)) return $value;
  if (is_object($value) && get_class($value) === "TemplateWrap" && property_exists($value, "__hx_value")) {
    return $value->__hx_value->execute((object)["t" => "really works!"]);
  }
  if (is_object($value) && get_class($value) === "Meter" && property_exists($value, "__hx_value")) {
    return __hxhx_add_string($value->__hx_value) . "m";
  }
  if (is_object($value) && get_class($value) === "Kilometer" && property_exists($value, "__hx_value")) {
    return __hxhx_add_string($value->__hx_value) . "km";
  }
  $abstractValue = __hxhx_abstract_value($value);
  if ($abstractValue !== $value) return __hxhx_to_string_value($abstractValue);
  return __hxhx_add_string($value);
}
function __hxhx_to_str($value) {
  if (__hxhx_is_int64($value)) return __hxhx_int64_to_string($value);
  if (is_object($value) && method_exists($value, "toStr")) return $value->toStr();
  return __hxhx_add_string($value);
}
function __hxhx_numeric_value($value) {
  $abstractValue = __hxhx_abstract_value($value);
  if ($abstractValue !== $value) return __hxhx_numeric_value($abstractValue);
  return $value;
}
function __hxhx_int_value($value) {
  return intval(__hxhx_numeric_value($value));
}
function __hxhx_int32_value($value) {
  $value = intval($value) & 0xFFFFFFFF;
  return $value >= 0x80000000 ? $value - 0x100000000 : $value;
}
