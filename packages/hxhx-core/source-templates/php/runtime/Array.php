class __HxArray implements \ArrayAccess {
  private $items;
  public function __construct($items) {
    $this->items = $items;
  }
  public function indexOf($value) {
    return __hxhx_array_index_of($this->items, $value);
  }
  public function contains($value) {
    return __hxhx_array_index_of($this->items, $value) >= 0;
  }
  public function pop() {
    return count($this->items) === 0 ? null : array_pop($this->items);
  }
  public function filter($predicate) {
    $out = [];
    foreach ($this->items as $item) if ($predicate === null || $predicate($item)) $out[] = $item;
    return new __HxArray($out);
  }
  public function sort($compare) {
    usort($this->items, $compare);
    return null;
  }
  public function join($separator) {
    return __hxhx_array_join($this->items, $separator);
  }
  public function toArray() {
    return $this->items;
  }
  public function offsetExists($offset): bool {
    return array_key_exists($offset, $this->items);
  }
  public function offsetGet($offset): mixed {
    return $this->items[$offset] ?? null;
  }
  public function offsetSet($offset, $value): void {
    if ($offset === null) $this->items[] = $value; else $this->items[$offset] = $value;
  }
  public function offsetUnset($offset): void {
    unset($this->items[$offset]);
  }
}
class __HxArrayIterator implements \IteratorAggregate {
  private $items;
  private $index = 0;
  public function __construct($items) {
    $this->items = array_values($items);
  }
  public function hasNext() {
    return $this->index < count($this->items);
  }
  public function next() {
    return $this->items[$this->index++];
  }
  public function getIterator(): \Traversable {
    return new \ArrayIterator($this->items);
  }
}
