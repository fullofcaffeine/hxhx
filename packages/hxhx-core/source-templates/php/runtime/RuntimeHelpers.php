function __hxhx_is_point3($value) {
  return is_object($value) && property_exists($value, "x") && property_exists($value, "y") && property_exists($value, "z");
}
function __hxhx_point3($x, $y, $z) {
  if (class_exists("MyPoint3", false)) return new MyPoint3($x, $y, $z);
  return (object)["x" => $x, "y" => $y, "z" => $z];
}
function __hxhx_equals($left, $right) {
  if (__hxhx_is_int64($left) || __hxhx_is_int64($right)) {
    $leftValue = __hxhx_int64_value($left);
    $rightValue = __hxhx_int64_value($right);
    return $leftValue->high === $rightValue->high && $leftValue->low === $rightValue->low;
  }
  if (is_callable($left) || is_callable($right)) return Reflect::compareMethods($left, $right);
  if ($left === null || $right === null) return $left === $right;
  $leftHasBoxedValue = is_object($left) && property_exists($left, "__hx_value") && $left->__hx_value !== null;
  $rightHasBoxedValue = is_object($right) && property_exists($right, "__hx_value") && $right->__hx_value !== null;
  if ($leftHasBoxedValue || $rightHasBoxedValue) {
    $leftValue = __hxhx_numeric_value($left);
    $rightValue = __hxhx_numeric_value($right);
    if (is_int($leftValue) && is_int($rightValue)) return $leftValue == $rightValue || __hxhx_int32_value($leftValue) == __hxhx_int32_value($rightValue);
    if ((is_int($leftValue) || is_float($leftValue)) && (is_int($rightValue) || is_float($rightValue))) return $leftValue == $rightValue;
    return __hxhx_to_string_value($left) == __hxhx_to_string_value($right);
  }
  if (is_int($left) && is_int($right)) return $left == $right || __hxhx_int32_value($left) == __hxhx_int32_value($right);
  if ($left instanceof __HxClassValue && is_string($right)) return $left->__hx_class_name === __hxhx_class_name($right);
  if (is_string($left) && $right instanceof __HxClassValue) return __hxhx_class_name($left) === $right->__hx_class_name;
  if (is_string($left) && __hxhx_is_point3($right)) return $left == __hxhx_to_string_value($right);
  if (__hxhx_is_point3($left) && is_string($right)) return __hxhx_to_string_value($left) == $right;
  if (is_object($left) || is_object($right)) {
    if ($left instanceof __HxClassValue && $right instanceof __HxClassValue) return $left->__hx_class_name === $right->__hx_class_name;
    if (is_object($left) && is_object($right) && property_exists($left, "__hx_ctor") && property_exists($right, "__hx_ctor")) {
      if ((property_exists($left, "__hx_enum") ? $left->__hx_enum : null) !== (property_exists($right, "__hx_enum") ? $right->__hx_enum : null)) return false;
      if ($left->__hx_ctor !== $right->__hx_ctor || $left->__hx_index !== $right->__hx_index) return false;
      $leftParams = property_exists($left, "__hx_params") && is_array($left->__hx_params) ? $left->__hx_params : [];
      $rightParams = property_exists($right, "__hx_params") && is_array($right->__hx_params) ? $right->__hx_params : [];
      if (count($leftParams) !== count($rightParams)) return false;
      for ($i = 0; $i < count($leftParams); $i++) if (!__hxhx_equals($leftParams[$i], $rightParams[$i])) return false;
      return true;
    }
    return $left === $right;
  }
  if ($left == $right) return true;
  return false;
}
function __hxhx_add($left, $right) {
  if (is_string($left) || is_string($right)) return __hxhx_add_string($left) . __hxhx_add_string($right);
  if ($left === null && (is_int($right) || is_float($right))) return $right;
  if ($right === null && (is_int($left) || is_float($left))) return $left;
  if (__hxhx_is_int64($left) || __hxhx_is_int64($right)) return __hxhx_int64_add($left, $right);
  if (__hxhx_is_point3($left) && __hxhx_is_point3($right)) return __hxhx_point3($left->x + $right->x, $left->y + $right->y, $left->z + $right->z);
  $leftAbstract = is_object($left) && property_exists($left, "__hx_value");
  $rightAbstract = is_object($right) && property_exists($right, "__hx_value");
  if ($leftAbstract || $rightAbstract) {
    $leftValue = __hxhx_numeric_value($left);
    $rightValue = __hxhx_numeric_value($right);
    if ((is_int($leftValue) || is_float($leftValue)) && (is_int($rightValue) || is_float($rightValue))) {
      $sum = $leftValue + $rightValue;
      if ($leftAbstract) return __hxhx_construct_like($left, $sum);
      if ($rightAbstract) return __hxhx_construct_like($right, $sum);
      return $sum;
    }
  }
  if (is_int($left) || is_float($left)) {
    if (is_int($right) || is_float($right)) return $left + $right;
  }
  return __hxhx_add_string($left) . __hxhx_add_string($right);
}
function __hxhx_sub($left, $right) {
  if (__hxhx_is_int64($left) || __hxhx_is_int64($right)) return __hxhx_int64_sub($left, $right);
  return $left - $right;
}
function __hxhx_post_update_field($obj, $field, $delta) {
  $old = $obj->$field;
  $obj->$field = __hxhx_is_int64($old) ? __hxhx_int64_add($old, $delta) : $old + $delta;
  return $old;
}
function __hxhx_pre_update_field($obj, $field, $delta) {
  $old = $obj->$field;
  $next = __hxhx_is_int64($old) ? __hxhx_int64_add($old, $delta) : $old + $delta;
  $obj->$field = $next;
  return $next;
}
function __hxhx_post_update_index(&$obj, $index, $delta) {
  $old = $obj[$index];
  $obj[$index] = __hxhx_is_int64($old) ? __hxhx_int64_add($old, $delta) : $old + $delta;
  return $old;
}
function __hxhx_pre_update_index(&$obj, $index, $delta) {
  $old = $obj[$index];
  $next = __hxhx_is_int64($old) ? __hxhx_int64_add($old, $delta) : $old + $delta;
  $obj[$index] = $next;
  return $next;
}
function __hxhx_neg($value) {
  if (__hxhx_is_int64($value)) return __hxhx_int64_neg($value);
  if (__hxhx_is_point3($value)) return __hxhx_mul($value, -1);
  return -__hxhx_numeric_value($value);
}
function __hxhx_mul($left, $right) {
  if (__hxhx_is_int64($left) || __hxhx_is_int64($right)) return __hxhx_int64_mul($left, $right);
  if (__hxhx_is_point3($left) && (is_int($right) || is_float($right))) return __hxhx_point3($left->x * $right, $left->y * $right, $left->z * $right);
  if ((is_int($left) || is_float($left)) && __hxhx_is_point3($right)) return __hxhx_point3($right->x * $left, $right->y * $left, $right->z * $left);
  if ((is_int($left) || is_float($left)) && is_string($right)) return str_repeat($right, intval($left));
  if (is_string($left) && (is_int($right) || is_float($right))) return str_repeat($left, intval($right));
  return $left * $right;
}
function __hxhx_mul_assign(&$left, $right) {
  if (__hxhx_is_point3($left) && (is_int($right) || is_float($right))) {
    $left->x *= $right;
    $left->y *= $right;
    $left->z *= $right;
    return $left;
  }
  $left = __hxhx_mul($left, $right);
  return $left;
}
function __hxhx_div($left, $right) {
  if (is_string($left) && (is_int($right) || is_float($right))) return substr($left, 0, intval($right));
  if (__hxhx_is_int64($left) || __hxhx_is_int64($right)) {
    $result = __hxhx_int64_div_mod($left, $right);
    return $result->quotient;
  }
  return $left / $right;
}
function __hxhx_add_string($value, $seen = null) {
  if ($seen === null) $seen = new SplObjectStorage();
  if ($value === null) return "null";
  if (is_bool($value)) return $value ? "true" : "false";
  if ($value instanceof __HxArray) $value = $value->toArray();
  if (is_array($value)) {
    $parts = [];
    foreach ($value as $item) {
      $parts[] = __hxhx_add_string($item, $seen);
    }
    return "[" . implode(",", $parts) . "]";
  }
  if (__hxhx_is_int64($value)) return __hxhx_int64_to_string($value);
  if (is_object($value) && get_class($value) === "Meter" && property_exists($value, "__hx_value")) return __hxhx_add_string($value->__hx_value, $seen) . "m";
  if (is_object($value) && get_class($value) === "Kilometer" && property_exists($value, "__hx_value")) return __hxhx_add_string($value->__hx_value, $seen) . "km";
  if (__hxhx_is_point3($value)) return "(" . __hxhx_add_string($value->x, $seen) . "," . __hxhx_add_string($value->y, $seen) . "," . __hxhx_add_string($value->z, $seen) . ")";
  if (is_object($value) && !method_exists($value, "__toString")) {
    if ($seen->contains($value)) return "{...}";
    $seen->attach($value);
    if (property_exists($value, "toString")) {
      $toString = $value->toString;
      if (is_callable($toString)) {
        $result = __hxhx_add_string($toString(), $seen);
        $seen->detach($value);
        return $result;
      }
    }
    if (property_exists($value, "__hx_ctor") && property_exists($value, "__hx_params") && is_array($value->__hx_params)) {
      $params = [];
      foreach ($value->__hx_params as $param) {
        $params[] = __hxhx_add_string($param, $seen);
      }
      $result = count($params) === 0 ? $value->__hx_ctor : $value->__hx_ctor . "(" . implode(",", $params) . ")";
      $seen->detach($value);
      return $result;
    }
    $parts = [];
    foreach (get_object_vars($value) as $key => $fieldValue) {
      $parts[] = $key . ": " . __hxhx_add_string($fieldValue, $seen);
    }
    $seen->detach($value);
    return "{" . implode(", ", $parts) . "}";
  }
  return strval($value);
}
function __hxhx_string_value($value) {
  if (is_object($value) && property_exists($value, "__hx_value")) return __hxhx_to_string_value($value->__hx_value);
  return __hxhx_to_string_value($value);
}
function __hxhx_class_candidate($type) {
  if ($type instanceof __HxClassValue) $type = $type->__hx_class_name;
  if (!is_string($type) || $type === "") return null;
  $resolved = __hxhx_class_name($type);
  $short = substr($resolved, strrpos($resolved, ".") === false ? 0 : strrpos($resolved, ".") + 1);
  $candidates = [$type, str_replace(".", "\\", $type), $resolved, str_replace(".", "\\", $resolved), $short, $short . "_"];
  foreach ($candidates as $candidate) {
    if (is_string($candidate) && $candidate !== "" && class_exists($candidate)) return $candidate;
  }
  return null;
}
function __hxhx_is_enum_class_value($value) {
  $candidate = __hxhx_class_candidate($value);
  return $candidate !== null && property_exists($candidate, "__hx_is_enum");
}
function __hxhx_enum_ctor_by_index($enumName, $index) {
  $runtime = __hxhx_runtime_class_name($enumName);
  if ($runtime === null || !class_exists($runtime)) return null;
  $vars = get_class_vars($runtime);
  if (array_key_exists("__hx_enum_ctors", $vars) && is_array($vars["__hx_enum_ctors"]) && array_key_exists(intval($index), $vars["__hx_enum_ctors"])) return strval($vars["__hx_enum_ctors"][intval($index)]);
  foreach ($vars as $name => $value) {
    if ($name === "__hx_is_enum" || $name === "__hx_enum_ctors") continue;
    if ($value instanceof __HxAnon && property_exists($value, "__hx_index") && intval($value->__hx_index) === intval($index)) return strval($name);
  }
  return null;
}
function __hxhx_enum_get_name($value) {
  return is_object($value) && property_exists($value, "__hx_ctor") ? strval($value->__hx_ctor) : null;
}
function __hxhx_value_type($ctor, $index, $params = []) {
  return new __HxAnon(["__hx_enum" => "ValueType", "__hx_ctor" => $ctor, "__hx_index" => $index, "__hx_params" => $params]);
}
function __hxhx_is_of_type($value, $type) {
  $hasBoxedValue = is_object($value) && property_exists($value, "__hx_value");
  $boxedValue = $hasBoxedValue ? $value->__hx_value : null;
  if ($type instanceof __HxClassValue) $type = $type->__hx_class_name;
  switch ($type) {
    case "Int": return is_int($value) || (is_float($value) && is_finite($value) && floor($value) == $value && $value >= -2147483648 && $value <= 2147483647) || ($hasBoxedValue && __hxhx_is_of_type($boxedValue, $type));
    case "Float": return is_int($value) || is_float($value) || ($hasBoxedValue && __hxhx_is_of_type($boxedValue, $type));
    case "String": return is_string($value) || ($hasBoxedValue && __hxhx_is_of_type($boxedValue, $type));
    case "Bool": return is_bool($value) || ($hasBoxedValue && __hxhx_is_of_type($boxedValue, $type));
    case "Array": return is_array($value) || $value instanceof __HxArray || ($hasBoxedValue && __hxhx_is_of_type($boxedValue, $type));
    case "StringMap": return $value instanceof Map && ($value->__hx_type === "haxe.ds.StringMap" || $value->__hx_type === "Map");
    case "haxe.ds.StringMap": return $value instanceof Map && ($value->__hx_type === "haxe.ds.StringMap" || $value->__hx_type === "Map");
    case "IntMap": return $value instanceof Map && ($value->__hx_type === "haxe.ds.IntMap" || $value->__hx_type === "Map");
    case "haxe.ds.IntMap": return $value instanceof Map && ($value->__hx_type === "haxe.ds.IntMap" || $value->__hx_type === "Map");
    case "ObjectMap": return $value instanceof Map && ($value->__hx_type === "haxe.ds.ObjectMap" || $value->__hx_type === "Map");
    case "haxe.ds.ObjectMap": return $value instanceof Map && ($value->__hx_type === "haxe.ds.ObjectMap" || $value->__hx_type === "Map");
    case "HashMap": return $value instanceof Map && $value->__hx_type === "haxe.ds.HashMap";
    case "haxe.ds.HashMap": return $value instanceof Map && $value->__hx_type === "haxe.ds.HashMap";
    case "List": return $value instanceof List_;
    case "haxe.ds.List": return $value instanceof List_;
    case "Exception": return $value instanceof \Throwable;
    case "haxe.Exception": return $value instanceof \Throwable;
    case "Dynamic": return true;
    case "Class": case "Class<Dynamic>": case "Class_": $candidate = __hxhx_class_candidate($value); if ($candidate !== null) return !property_exists($candidate, "__hx_is_enum"); return is_string($value) && (strpos(strval($value), ".") !== false || strpos(__hxhx_class_name($value), ".") !== false) && !__hxhx_is_enum_class_value($value);
    case "Enum": case "Enum<Dynamic>": case "Enum_": return __hxhx_is_enum_class_value($value);
  }
  if ($type === null) return false;
  if (!is_object($value)) return false;
  $resolved = __hxhx_class_name($type);
  $runtime = __hxhx_runtime_class_name($type);
  $short = substr($resolved, strrpos($resolved, ".") === false ? 0 : strrpos($resolved, ".") + 1);
  $candidates = [$type, $runtime, str_replace(".", "\\", $type), $resolved, str_replace(".", "\\", $resolved), $short, $short . "_"];
  if ($value instanceof __HxAnon && property_exists($value, "__hx_ctor") && property_exists($value, "__hx_params")) {
    if (property_exists($value, "__hx_enum")) {
      $enumName = __hxhx_class_name($value->__hx_enum);
      $enumShort = substr($enumName, strrpos($enumName, ".") === false ? 0 : strrpos($enumName, ".") + 1);
      if ($enumName === $resolved || $enumName === $type || $enumShort === $short) return true;
    }
    $ctor = strval($value->__hx_ctor);
    foreach ($candidates as $candidate) {
      if (is_string($candidate) && $candidate !== "" && class_exists($candidate) && (property_exists($candidate, $ctor) || method_exists($candidate, $ctor))) return true;
    }
    return false;
  }
  foreach ($candidates as $candidate) {
    if (is_string($candidate) && $candidate !== "" && (class_exists($candidate) || interface_exists($candidate)) && $value instanceof $candidate) return true;
  }
  if ($hasBoxedValue) return __hxhx_is_of_type($boxedValue, $type);
  return false;
}
function __hxhx_mod($left, $right) {
  if (__hxhx_is_int64($left) || __hxhx_is_int64($right)) {
    $result = __hxhx_int64_div_mod($left, $right);
    return $result->modulus;
  }
  if ($right == 0) return NAN;
  if (is_float($left) || is_float($right)) return fmod($left, $right);
  return $left % $right;
}
function __hxhx_length($value) {
  if ($value instanceof __HxArray) return count($value->toArray());
  if (is_array($value)) return count($value);
  if (is_string($value)) return strlen($value);
  if (is_object($value) && property_exists($value, "length")) return $value->length;
  return 0;
}
function __hxhx_to_array($value) {
  if ($value instanceof __HxArray) return $value->toArray();
  if (is_array($value)) return $value;
  if (is_object($value) && method_exists($value, "toArray")) return $value->toArray();
  return $value;
}
function __hxhx_object_of_associative_array($array) {
  if ($array instanceof __HxArray) $array = $array->toArray();
  if (!is_array($array)) return $array;
  $out = new \stdClass();
  foreach ($array as $key => $value) {
    if ($value instanceof __HxArray || is_array($value)) $value = __hxhx_object_of_associative_array($value);
    $field = strval($key);
    $out->$field = $value;
  }
  return $out;
}
function __hxhx_rest_append($array, $value) {
  if ($array instanceof __HxArray) $array = $array->toArray();
  if (!is_array($array)) $array = [];
  $result = array_values($array);
  $result[] = $value;
  return $result;
}
function __hxhx_rest_prepend($array, $value) {
  if ($array instanceof __HxArray) $array = $array->toArray();
  if (!is_array($array)) $array = [];
  $result = array_values($array);
  array_unshift($result, $value);
  return $result;
}
function __hxhx_array_get($array, $index) {
  if ($array instanceof Map) return $array->get($index);
  if ($array instanceof __HxArray) $array = $array->toArray();
  if (is_object($array)) {
    $field = strval($index);
    return property_exists($array, $field) ? $array->$field : null;
  }
  if (!is_array($array)) return null;
  return array_key_exists($index, $array) ? $array[$index] : null;
}
function __hxhx_array_set(&$array, $index, $value) {
  if ($array instanceof Map) {
    $array->set($index, $value);
    return $value;
  }
  if ($array instanceof __HxArray) {
    $array[$index] = $value;
    return $value;
  }
  if (is_object($array)) {
    $field = strval($index);
    $array->$field = $value;
    return $value;
  }
  if (!is_array($array)) $array = [];
  $array[$index] = $value;
  return $value;
}
function __hxhx_array_add_assign(&$array, $index, $value) {
  $next = __hxhx_add(__hxhx_array_get($array, $index), $value);
  __hxhx_array_set($array, $index, $next);
  return $next;
}
function __hxhx_field_add_assign($object, $field, $value) {
  $next = __hxhx_add($object->$field, $value);
  $object->$field = $next;
  return $next;
}
function __hxhx_tag_map($value, $__hx_type) {
  if ($value instanceof Map && $value->__hx_type === "Map") $value->__hx_type = $__hx_type;
  return $value;
}
function __hxhx_map_literal($pairs) {
  $__hx_type = "Map";
  foreach ($pairs as $pair) {
    $key = $pair[0];
    if (is_int($key)) { $__hx_type = "haxe.ds.IntMap"; break; }
    if (is_string($key)) { $__hx_type = "haxe.ds.StringMap"; break; }
    if (is_object($key)) { $__hx_type = "haxe.ds.ObjectMap"; break; }
  }
  $map = new Map(null, $__hx_type);
  foreach ($pairs as $pair) $map->set($pair[0], $pair[1]);
  return $map;
}
function __hxhx_map_literal_from_object($object) {
  $map = new Map();
  foreach (get_object_vars($object) as $key => $value) $map->set($key, $value);
  return $map;
}
function __hxhx_remove(&$collection, $value) {
  if ($collection instanceof Map) return $collection->remove($value);
  if ($collection instanceof Xml) return $collection->remove($value);
  if ($collection instanceof __HxArray) $collection = $collection->toArray();
  if (!is_array($collection)) return false;
  $index = __hxhx_array_index_of($collection, $value);
  if ($index < 0) return false;
  array_splice($collection, $index, 1);
  return true;
}
function __hxhx_array_index_of($array, $value) {
  if ($array instanceof __HxArray) $array = $array->toArray();
  if (!is_array($array)) return -1;
  foreach (array_values($array) as $index => $item) if (__hxhx_equals($item, $value)) return $index;
  return -1;
}
function __hxhx_array_splice(&$array, $pos, $len) {
  if ($array instanceof __HxArray) $array = $array->toArray();
  if (!is_array($array)) return [];
  return array_splice($array, (int)$pos, (int)$len);
}
function __hxhx_array_sort(&$array, $compare) {
  if ($array instanceof __HxArray) return $array->sort($compare);
  if (!is_array($array)) return null;
  usort($array, $compare);
  return null;
}
function __hxhx_array_join($array, $separator) {
  if ($array instanceof __HxArray) $array = $array->toArray();
  if (!is_array($array)) return "";
  $parts = [];
  foreach ($array as $item) $parts[] = __hxhx_add_string($item);
  return implode(strval($separator), $parts);
}
function __hxhx_array_map($array, $callback) {
  if ($array instanceof __HxArray) $array = $array->toArray();
  if (!is_array($array)) return [];
  $out = [];
  foreach ($array as $item) $out[] = $callback($item);
  return $out;
}
function __hxhx_iterator($value) {
  if ($value instanceof __HxArray) return new __HxArrayIterator($value->toArray());
  if (is_array($value)) return new __HxArrayIterator($value);
  if (is_object($value) && method_exists($value, "iterator")) return $value->iterator();
  return $value;
}
function __hxhx_iter($value) {
  if (is_string($value)) return new __HxArrayIterator(str_split($value));
  return __hxhx_iterator($value);
}
function __hxhx_key_value_iter($value) {
  if ($value instanceof Map) return $value->keyValuePairs();
  if ($value instanceof __HxArray) $value = $value->toArray();
  $pairs = [];
  if (is_string($value)) {
    foreach (str_split($value) as $key => $item) $pairs[] = [$key, $item];
    return $pairs;
  }
  if (is_array($value) || $value instanceof \Traversable) {
    foreach ($value as $key => $item) $pairs[] = [$key, $item];
  }
  return $pairs;
}
function __hxhx_field($obj, $field) {
  $name = strval($field);
  if ($obj === null) throw ValueException::thrown("NPE");
  if (is_string($obj) && __hxhx_string_method_exists($name)) return new HxDynamicStr($obj, $name);
  if (is_object($obj)) {
    if (property_exists($obj, $name)) return $obj->$name;
    if (__hxhx_is_int64($obj) && $name === "toStr") return function() use ($obj) { return __hxhx_int64_to_string($obj); };
    if (method_exists($obj, $name)) return [$obj, $name];
  }
  if (is_array($obj) && array_key_exists($name, $obj)) return $obj[$name];
  return null;
}
function __hxhx_call_field($obj, $field, ...$args) {
  $callable = __hxhx_field($obj, $field);
  if (!is_callable($callable)) throw new \Exception("Cannot call non-callable field");
  return $callable(...$args);
}
function __hxhx_bind_placeholder() {
  static $placeholder = null;
  if ($placeholder === null) $placeholder = new \stdClass();
  return $placeholder;
}
function __hxhx_bind($callable, ...$boundArgs) {
  if (!is_callable($callable)) throw new \Exception("Cannot bind non-callable value");
  return function(...$args) use ($callable, $boundArgs) {
    $resolved = [];
    $index = 0;
    $placeholder = __hxhx_bind_placeholder();
    $count = count($args);
    foreach ($boundArgs as $bound) {
      if ($bound === $placeholder) {
        $resolved[] = $index < $count ? $args[$index++] : null;
      } else {
        $resolved[] = $bound;
      }
    }
    while ($index < $count) $resolved[] = $args[$index++];
    return $callable(...$resolved);
  };
}
