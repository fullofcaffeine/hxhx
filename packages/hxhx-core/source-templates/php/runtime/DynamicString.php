class HxDynamicStr {
  public $__hx_string_value;
  public $__hx_field;
  public function __construct($value, $field = null) {
    $this->__hx_string_value = __hxhx_string_value($value);
    $this->__hx_field = $field;
  }
  private function __hx_call($name, $args) {
    switch ($name) {
      case "charAt": return __hxhx_string_char_at($this->__hx_string_value, $args[0] ?? 0);
      case "indexOf": return __hxhx_string_index_of($this->__hx_string_value, $args[0] ?? "", $args[1] ?? 0);
      case "lastIndexOf": return __hxhx_string_last_index_of($this->__hx_string_value, $args[0] ?? "", $args[1] ?? null);
      case "split": return __hxhx_string_split($this->__hx_string_value, $args[0] ?? "");
      case "charCodeAt": return __hxhx_string_char_code_at($this->__hx_string_value, $args[0] ?? 0);
      case "substr": return __hxhx_string_substr($this->__hx_string_value, $args[0] ?? 0, $args[1] ?? null);
      case "substring": return __hxhx_string_substring($this->__hx_string_value, $args[0] ?? 0, $args[1] ?? null);
      case "toString": return $this->__hx_string_value;
      case "toUpperCase": return strtoupper($this->__hx_string_value);
      case "toLowerCase": return strtolower($this->__hx_string_value);
    }
    return null;
  }
  public function __invoke(...$args) { return $this->__hx_call($this->__hx_field, $args); }
  public function __call($name, $args) { return $this->__hx_call($name, $args); }
  public function charAt($index) { return $this->__hx_call("charAt", [$index]); }
  public function indexOf($needle, $start = 0) { return $this->__hx_call("indexOf", [$needle, $start]); }
  public function lastIndexOf($needle, $start = null) { return $this->__hx_call("lastIndexOf", [$needle, $start]); }
  public function split($delimiter) { return $this->__hx_call("split", [$delimiter]); }
  public function charCodeAt($index) { return $this->__hx_call("charCodeAt", [$index]); }
  public function substr($pos, $len = null) { return $this->__hx_call("substr", [$pos, $len]); }
  public function substring($start, $end = null) { return $this->__hx_call("substring", [$start, $end]); }
  public function toString() { return $this->__hx_string_value; }
  public function toUpperCase() { return $this->__hx_call("toUpperCase", []); }
  public function toLowerCase() { return $this->__hx_call("toLowerCase", []); }
  public function __toString() { return $this->__hx_string_value; }
}
