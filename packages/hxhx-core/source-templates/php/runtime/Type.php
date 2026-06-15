class Type {
  public static function getClass($value) {
    if ($value === null) return null;
    if ($value instanceof __HxClassValue) return null;
    if (is_string($value)) return "String";
    if (is_array($value) || $value instanceof __HxArray) return "Array";
    if ($value instanceof Map) return $value->__hx_type;
    if (is_object($value)) return __hxhx_class_name(get_class($value));
    return null;
  }
  public static function getClassName($cls) {
    if ($cls === null) return null;
    if ($cls instanceof __HxClassValue) return $cls->__hx_class_name;
    if (is_string($cls)) return __hxhx_class_name($cls);
    if (is_object($cls)) return __hxhx_class_name(get_class($cls));
    return null;
  }
  public static function resolveClass($name) {
    if ($name === null) return null;
    return __hxhx_class_value($name);
  }
  private static function reflectionClass($cls) {
    $runtime = __hxhx_runtime_class_name($cls);
    if ($runtime === null || !class_exists($runtime)) return null;
    return new \ReflectionClass($runtime);
  }
  private static function exposeFieldName($name) {
    return $name !== null && $name !== "" && strpos($name, "__hx_") !== 0 && strpos($name, "__") !== 0;
  }
  private static function collectFieldNames($cls, $wantStatic) {
    $reflection = self::reflectionClass($cls);
    if ($reflection === null) return [];
    $hidden = __hxhx_hidden_reflection_fields($cls, $wantStatic);
    $fields = [];
    foreach ($reflection->getProperties() as $prop) {
      if ($prop->isStatic() !== $wantStatic) continue;
      $name = $prop->getName();
      if (array_key_exists($name, $hidden)) continue;
      if (self::exposeFieldName($name) && !in_array($name, $fields, true)) $fields[] = $name;
    }
    foreach ($reflection->getMethods() as $method) {
      if ($method->isConstructor() || $method->isStatic() !== $wantStatic) continue;
      $name = $method->getName();
      if (array_key_exists($name, $hidden)) continue;
      if (self::exposeFieldName($name) && !in_array($name, $fields, true)) $fields[] = $name;
    }
    $accessors = [];
    foreach ($fields as $name) {
      if (preg_match('/^(get|set)_(.+)$/', $name, $matches)) {
        $field = $matches[2];
        if (!array_key_exists($field, $accessors)) $accessors[$field] = [];
        $accessors[$field][$matches[1]] = true;
      }
    }
    foreach ($accessors as $field => $seen) {
      if (!array_key_exists($field, $hidden) && isset($seen["get"]) && isset($seen["set"]) && self::exposeFieldName($field) && !in_array($field, $fields, true)) $fields[] = $field;
    }
    foreach (__hxhx_extra_reflection_fields($cls, $wantStatic) as $name => $_) {
      if (!array_key_exists($name, $hidden) && self::exposeFieldName($name) && !in_array($name, $fields, true)) $fields[] = $name;
    }
    return $fields;
  }
  public static function getInstanceFields($cls) {
    return new __HxArray(self::collectFieldNames($cls, false));
  }
  public static function getClassFields($cls) {
    return new __HxArray(self::collectFieldNames($cls, true));
  }
  public static function getEnumName($enum) {
    return self::getClassName($enum);
  }
  private static function enumConstructorNames($enum) {
    $runtime = __hxhx_runtime_class_name($enum);
    if ($runtime === null || !class_exists($runtime)) return [];
    $vars = get_class_vars($runtime);
    if (array_key_exists("__hx_enum_ctors", $vars) && is_array($vars["__hx_enum_ctors"])) return array_values($vars["__hx_enum_ctors"]);
    $ctors = [];
    foreach ($vars as $name => $value) {
      if ($name === "__hx_is_enum" || $name === "__hx_enum_ctors" || strpos($name, "__") === 0) continue;
      if ($value instanceof __HxAnon && property_exists($value, "__hx_ctor") && property_exists($value, "__hx_index")) $ctors[intval($value->__hx_index)] = strval($value->__hx_ctor);
      else $ctors[] = strval($name);
    }
    $reflection = new \ReflectionClass($runtime);
    foreach ($reflection->getMethods(\ReflectionMethod::IS_STATIC) as $method) {
      $name = $method->getName();
      if ($name !== "__construct" && strpos($name, "__") !== 0 && !in_array($name, $ctors, true)) $ctors[] = $name;
    }
    ksort($ctors);
    return array_values($ctors);
  }
  public static function getEnumConstructs($enum) {
    return new __HxArray(self::enumConstructorNames($enum));
  }
  public static function allEnums($enum) {
    $runtime = __hxhx_runtime_class_name($enum);
    if ($runtime === null || !class_exists($runtime)) return new __HxArray([]);
    $values = [];
    foreach (self::enumConstructorNames($enum) as $name) {
      if (!property_exists($runtime, $name)) continue;
      $value = $runtime::${$name};
      if ($value !== null) $values[] = $value;
    }
    return new __HxArray($values);
  }
  public static function resolveEnum($name) {
    if ($name === null) return null;
    return __hxhx_class_value($name);
  }
  public static function createInstance($cls, $args) {
    if ($args instanceof __HxArray) $args = $args->toArray();
    if (!is_array($args)) $args = [];
    $runtime = __hxhx_runtime_class_name($cls);
    if ($runtime === null || !class_exists($runtime)) throw new \Exception("Class not found: " . strval($cls));
    return new $runtime(...array_values($args));
  }
  public static function createEmptyInstance($cls) {
    $runtime = __hxhx_runtime_class_name($cls);
    if ($runtime === null || !class_exists($runtime)) throw new \Exception("Class not found: " . strval($cls));
    $reflection = new \ReflectionClass($runtime);
    return $reflection->newInstanceWithoutConstructor();
  }
  public static function createEnum($enum, $ctor, $args = null) {
    if ($args instanceof __HxArray) $args = $args->toArray();
    if ($args === null) $args = [];
    if (!is_array($args)) $args = [];
    $runtime = __hxhx_runtime_class_name($enum);
    if ($runtime === null || !class_exists($runtime)) throw new \Exception("Enum not found: " . strval($enum));
    $name = strval($ctor);
    if (property_exists($runtime, $name)) {
      if (count($args) !== 0) throw new \Exception("Enum constructor does not take arguments: " . $name);
      return $runtime::${$name};
    }
    if (method_exists($runtime, $name)) {
      $reflection = new \ReflectionMethod($runtime, $name);
      $count = count($args);
      if ($count < $reflection->getNumberOfRequiredParameters() || $count > $reflection->getNumberOfParameters()) throw new \Exception("Enum constructor argument count mismatch: " . $name);
      return $runtime::$name(...array_values($args));
    }
    throw new \Exception("Enum constructor not found: " . $name);
  }
  public static function typeof($value) {
    if ($value === null) return __hxhx_value_type("TNull", 0);
    if (is_int($value)) return __hxhx_value_type("TInt", 1);
    if (is_float($value)) return __hxhx_value_type("TFloat", 2);
    if (is_bool($value)) return __hxhx_value_type("TBool", 3);
    if (is_callable($value)) return __hxhx_value_type("TFunction", 5);
    if ($value instanceof __HxClassValue) return __hxhx_value_type("TObject", 4);
    if (is_string($value)) return __hxhx_value_type("TClass", 6, [__hxhx_class_value("String")]);
    if (is_array($value) || $value instanceof __HxArray) return __hxhx_value_type("TClass", 6, [__hxhx_class_value("Array")]);
    if ($value instanceof Map) return __hxhx_value_type("TClass", 6, [__hxhx_class_value($value->__hx_type)]);
    if ($value instanceof __HxAnon && property_exists($value, "__hx_enum")) return __hxhx_value_type("TEnum", 7, [__hxhx_class_value($value->__hx_enum)]);
    if ($value instanceof __HxAnon) return __hxhx_value_type("TObject", 4);
    if (is_object($value)) return __hxhx_value_type("TClass", 6, [__hxhx_class_value(__hxhx_class_name(get_class($value)))]);
    return __hxhx_value_type("TUnknown", 8);
  }
  public static function enumEq($left, $right) {
    return __hxhx_equals($left, $right);
  }
}
