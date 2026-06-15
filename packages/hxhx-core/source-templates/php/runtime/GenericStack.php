namespace haxe\ds {
  class GenericStack implements \IteratorAggregate {
    private $items;
    public function __construct() {
      $this->items = [];
    }
    public function add($value) {
      array_unshift($this->items, $value);
    }
    public function first() {
      return count($this->items) === 0 ? null : $this->items[0];
    }
    public function pop() {
      return count($this->items) === 0 ? null : array_shift($this->items);
    }
    public function isEmpty() {
      return count($this->items) === 0;
    }
    public function remove($value) {
      $index = \__hxhx_array_index_of($this->items, $value);
      if ($index < 0) return false;
      array_splice($this->items, $index, 1);
      return true;
    }
    public function iterator() {
      return new \__HxArrayIterator($this->items);
    }
    public function getIterator(): \Traversable {
      return new \ArrayIterator($this->items);
    }
    public function toString() {
      $parts = [];
      foreach ($this->items as $item) $parts[] = \__hxhx_add_string($item);
      return "{" . implode(",", $parts) . "}";
    }
    public function __toString() {
      return $this->toString();
    }
  }
}
