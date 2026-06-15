class Reflect {
  public static function compare($a, $b) {
    if ($a == $b) return 0;
    return $a < $b ? -1 : 1;
  }
  public static function compareMethods($a, $b) {
    if ($a === null || $b === null) return $a === $b;
    if ($a === $b) return true;
    if (is_array($a) && is_array($b) && count($a) >= 2 && count($b) >= 2) return $a[0] === $b[0] && $a[1] === $b[1];
    if (!($a instanceof \Closure) || !($b instanceof \Closure)) return false;
    $left = new \ReflectionFunction($a);
    $right = new \ReflectionFunction($b);
    if ($left->getFileName() !== $right->getFileName() || $left->getStartLine() !== $right->getStartLine() || $left->getEndLine() !== $right->getEndLine()) return false;
    $leftVars = $left->getStaticVariables();
    $rightVars = $right->getStaticVariables();
    if (count($leftVars) !== count($rightVars)) return false;
    foreach ($leftVars as $key => $value) if (!array_key_exists($key, $rightVars) || $rightVars[$key] !== $value) return false;
    return true;
  }
  public static function field($object, $field) {
    if (is_string($object) && __hxhx_string_method_exists($field)) return new HxDynamicStr($object, $field);
    if (is_object($object) && property_exists($object, $field)) return $object->$field;
    if (is_object($object) && method_exists($object, $field)) return [$object, $field];
    if (is_array($object) && array_key_exists($field, $object)) return $object[$field];
    $runtime = __hxhx_class_candidate($object);
    if ($runtime !== null) {
      if (property_exists($runtime, $field)) return $runtime::${$field};
      if (method_exists($runtime, $field)) return [$runtime, $field];
    }
    return null;
  }
  public static function fields($object) {
    if ($object === null || $object instanceof __HxClassValue || $object instanceof __HxArray) return [];
    $out = [];
    if (is_array($object)) {
      foreach (array_keys($object) as $key) if (is_string($key)) $out[] = $key;
      return $out;
    }
    if (is_object($object)) {
      foreach (get_object_vars($object) as $key => $_) {
        if (strpos($key, "__hx_") === 0) continue;
        $out[] = $key;
      }
    }
    return $out;
  }
  public static function callMethod($object, $method, $args) {
    if ($args instanceof __HxArray) $args = $args->toArray();
    if (!is_array($args)) $args = [];
    if (!is_callable($method)) return null;
    return $method(...array_values($args));
  }
  public static function getProperty($object, $field) {
    if ($object === null || $field === null) return null;
    $field = strval($field);
    $getter = "get_" . $field;
    $runtime = __hxhx_class_candidate($object);
    if ($runtime !== null && method_exists($runtime, $getter)) return $runtime::$getter();
    if (is_object($object) && !($object instanceof __HxClassValue) && method_exists($object, $getter)) return $object->$getter();
    return self::field($object, $field);
  }
  public static function setProperty($object, $field, $value) {
    if ($object === null || $field === null) return null;
    $field = strval($field);
    $setter = "set_" . $field;
    $runtime = __hxhx_class_candidate($object);
    if ($runtime !== null) {
      if (method_exists($runtime, $setter)) return $runtime::$setter($value);
      if (property_exists($runtime, $field)) { $runtime::${$field} = $value; return null; }
      return null;
    }
    if (is_object($object)) {
      if (method_exists($object, $setter)) return $object->$setter($value);
      $object->$field = $value;
    }
    return null;
  }
  public static function makeVarArgs($f) {
    return function(...$args) use ($f) { return $f($args); };
  }
}
