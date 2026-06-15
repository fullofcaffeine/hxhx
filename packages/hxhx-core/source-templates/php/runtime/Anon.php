#[\AllowDynamicProperties]
class __HxAnon {
  public function __construct($fields = []) {
    foreach ($fields as $name => $value) $this->$name = $value;
  }
  public function __call($name, $args) {
    $value = $this->$name ?? null;
    if (is_callable($value)) return $value(...$args);
    throw new \Error("Call to undefined method __HxAnon::" . $name . "()");
  }
}
