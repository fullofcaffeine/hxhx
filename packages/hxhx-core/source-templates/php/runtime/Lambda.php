class Lambda {
  private static function toArray($value) {
    if ($value instanceof __HxArray) return array_values($value->toArray());
    if (is_array($value)) return array_values($value);
    if ($value instanceof Map) return self::toArray($value->iterator());
    if ($value instanceof __HxArrayIterator) {
      $items = [];
      while ($value->hasNext()) $items[] = $value->next();
      return $items;
    }
    if (is_object($value)) {
      if (method_exists($value, "iterator")) return self::toArray($value->iterator());
      if (property_exists($value, "iterator")) {
        $iterator = $value->iterator;
        return is_callable($iterator) ? self::toArray($iterator()) : self::toArray($iterator);
      }
    }
    return [];
  }
  public static function array($value) {
    return self::toArray($value);
  }
  public static function list($value) {
    $list = new List_();
    foreach (self::toArray($value) as $item) $list->add($item);
    return $list;
  }
  public static function count($value, $predicate = null) {
    $count = 0;
    foreach (self::toArray($value) as $item) {
      if ($predicate === null || $predicate($item)) $count++;
    }
    return $count;
  }
  public static function has($value, $match) {
    return in_array($match, self::toArray($value), true);
  }
  public static function exists($value, $predicate) {
    foreach (self::toArray($value) as $item) if ($predicate($item)) return true;
    return false;
  }
  public static function foreach($value, $predicate) {
    foreach (self::toArray($value) as $item) if (!$predicate($item)) return false;
    return true;
  }
  public static function iter($value, $callback) {
    foreach (self::toArray($value) as $item) $callback($item);
    return null;
  }
  public static function map($value, $callback) {
    $out = [];
    foreach (self::toArray($value) as $item) $out[] = $callback($item);
    return $out;
  }
  public static function filter($value, $predicate) {
    $out = [];
    foreach (self::toArray($value) as $item) if ($predicate === null || $predicate($item)) $out[] = $item;
    return $out;
  }
  public static function fold($value, $callback, $first) {
    $acc = $first;
    foreach (self::toArray($value) as $item) $acc = $callback($item, $acc);
    return $acc;
  }
  public static function concat($a, $b) {
    return array_merge(self::toArray($a), self::toArray($b));
  }
}
