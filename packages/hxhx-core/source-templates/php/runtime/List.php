class List_ implements \IteratorAggregate {
  private $items;
  public $length;
  public function __construct() {
    $this->items = [];
    $this->length = 0;
  }
  private function syncLength() {
    $this->length = count($this->items);
  }
  public function add($value) {
    $this->items[] = $value;
    $this->syncLength();
  }
  public function push($value) {
    array_unshift($this->items, $value);
    $this->syncLength();
  }
  public function pop() {
    $value = array_shift($this->items);
    $this->syncLength();
    return $value;
  }
  public function first() {
    return $this->length === 0 ? null : $this->items[0];
  }
  public function last() {
    return $this->length === 0 ? null : $this->items[$this->length - 1];
  }
  public function clear() {
    $this->items = [];
    $this->length = 0;
  }
  public function isEmpty() {
    return $this->length === 0;
  }
  public function remove($value) {
    $index = __hxhx_array_index_of($this->items, $value);
    if ($index < 0) return false;
    array_splice($this->items, $index, 1);
    $this->syncLength();
    return true;
  }
  public function iterator() {
    return new __HxArrayIterator($this->items);
  }
  public function getIterator(): \Traversable {
    return new \ArrayIterator($this->items);
  }
  public function join($separator) {
    $parts = [];
    foreach ($this->items as $item) $parts[] = __hxhx_add_string($item);
    return implode(strval($separator), $parts);
  }
  public function toString() {
    return "{" . $this->join(", ") . "}";
  }
  public function __toString() {
    return $this->toString();
  }
}
