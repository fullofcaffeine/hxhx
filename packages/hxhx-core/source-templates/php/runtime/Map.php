class Map implements \IteratorAggregate {
  private $items;
  private $keys;
  public $__hx_type;
  public function __construct($initial = null, $__hx_type = "Map") {
    $this->items = [];
    $this->keys = [];
    $this->__hx_type = $__hx_type;
  }
  private static function keyId($key) {
    if (is_object($key)) return "object:" . spl_object_id($key);
    if (is_array($key)) return "array:" . md5(serialize($key));
    if ($key === null) return "null:";
    if (is_bool($key)) return "bool:" . ($key ? "1" : "0");
    return gettype($key) . ":" . strval($key);
  }
  private function keyIdFor($key) {
    if ($this->__hx_type === "haxe.ds.HashMap" && is_object($key) && method_exists($key, "hashCode")) return "hash:" . strval($key->hashCode());
    return self::keyId($key);
  }
  public function set($key, $value) {
    if ($this->__hx_type === "Map") {
      if (is_int($key)) $this->__hx_type = "haxe.ds.IntMap";
      else if (is_string($key)) $this->__hx_type = "haxe.ds.StringMap";
      else if (is_object($key)) $this->__hx_type = "haxe.ds.ObjectMap";
    }
    $id = $this->keyIdFor($key);
    $this->items[$id] = $value;
    $this->keys[$id] = $key;
  }
  public function get($key) {
    $id = $this->keyIdFor($key);
    return array_key_exists($id, $this->items) ? $this->items[$id] : null;
  }
  public function exists($key) {
    return array_key_exists($this->keyIdFor($key), $this->items);
  }
  public function remove($key) {
    $id = $this->keyIdFor($key);
    if (!array_key_exists($id, $this->items)) return false;
    unset($this->items[$id]);
    unset($this->keys[$id]);
    return true;
  }
  public function keys() {
    return new __HxArrayIterator(array_values($this->keys));
  }
  public function iterator() {
    return new __HxArrayIterator(array_values($this->items));
  }
  public function keyValuePairs() {
    $pairs = [];
    foreach ($this->items as $id => $value) $pairs[] = [$this->keys[$id], $value];
    return $pairs;
  }
  public function getIterator(): \Traversable {
    return new \ArrayIterator(array_values($this->items));
  }
  public function toString() {
    if (count($this->items) === 0) return "[]";
    $parts = [];
    foreach ($this->items as $id => $value) {
      $parts[] = __hxhx_add_string($this->keys[$id]) . " => " . __hxhx_add_string($value);
    }
    return "[" . implode(", ", $parts) . "]";
  }
  public function __toString() {
    return $this->toString();
  }
}
