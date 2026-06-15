class ValueException extends \Exception {
  public $value;
  public $stack;
  public function __construct($value = null) {
    $this->value = $value;
    $this->stack = __hxhx_stack();
    parent::__construct(__hxhx_to_string_value($value));
  }
  public function get_stack() {
    return $this->stack;
  }
  public static function thrown($value) {
    if ($value instanceof ValueException) return $value;
    return new ValueException($value);
  }
}
class PosException extends ValueException {
  public $posInfos;
  public function __construct($message = null, $previous = null, $pos = null) {
    $this->posInfos = $pos === null ? __hxhx_pos_infos() : $pos;
    parent::__construct($message);
  }
}
class NotImplementedException extends PosException {
}
class ArgumentException extends PosException {
  public $argument;
  public function __construct($argument = null, $message = null, $previous = null, $pos = null) {
    $this->argument = $argument;
    parent::__construct($message === null ? $argument : $message, $previous, $pos);
  }
}
function __hxhx_throw($value) {
  throw ValueException::thrown($value);
}
function __hxhx_pos_infos() {
  $trace = debug_backtrace(DEBUG_BACKTRACE_IGNORE_ARGS);
  foreach ($trace as $frame) {
    $method = array_key_exists("function", $frame) ? $frame["function"] : null;
    $class = array_key_exists("class", $frame) ? $frame["class"] : null;
    if ($method === null || $method === "__construct" || $method === "__hxhx_pos_infos") continue;
    if ($class === "ValueException" || $class === "PosException" || $class === "NotImplementedException") continue;
    return (object)["fileName" => array_key_exists("file", $frame) ? $frame["file"] : null, "lineNumber" => array_key_exists("line", $frame) ? $frame["line"] : 0, "className" => $class === null ? null : __hxhx_class_name($class), "methodName" => $method];
  }
  return (object)["fileName" => null, "lineNumber" => 0, "className" => null, "methodName" => null];
}
function __hxhx_file_pos($file, $line) {
  return (object)["__hx_ctor" => "FilePos", "__hx_index" => 2, "__hx_params" => [null, $file, $line, null]];
}
function __hxhx_stack() {
  return [__hxhx_file_pos("hxhx.php", 1), __hxhx_file_pos("hxhx.php", 1)];
}
class CallStack {
  public static function callStack() {
    return __hxhx_stack();
  }
  public static function exceptionStack($fullStack = false) {
    return __hxhx_stack();
  }
}
function __hxhx_unwrap_thrown_value($value) {
  $unwrapped = $value instanceof ValueException ? $value->value : $value;
  return $unwrapped;
}
function __hxhx_io_error($name) {
  $name = strval($name);
  foreach (["Error_", "haxe\\io\\Error"] as $candidate) {
    if (class_exists($candidate, false) && property_exists($candidate, $name)) return $candidate::${$name};
  }
  return $name;
}
function __hxhx_message_field($value) {
  if ($value instanceof \Throwable) return $value->getMessage();
  if (is_array($value) && array_key_exists("message", $value)) return $value["message"];
  return $value->message;
}
function __hxhx_catch_matches($caught, $type) {
  $type = strval($type);
  if ($type === "" || $type === "Dynamic" || $type === "Any" || $type === "Exception" || $type === "haxe.Exception") return true;
  if ($type === "ValueException" || $type === "haxe.ValueException") return $caught instanceof ValueException && !($caught->value instanceof \Throwable);
  $class = str_replace(".", "\\", $type);
  $parts = explode(".", $type);
  $short = end($parts);
  if (class_exists($class) && $caught instanceof $class) return true;
  if (class_exists($short) && $caught instanceof $short) return true;
  $value = __hxhx_unwrap_thrown_value($caught);
  if ($type === "Int") return is_int($value);
  if ($type === "Float") return is_float($value) || is_int($value);
  if ($type === "String") return is_string($value);
  if ($type === "Bool") return is_bool($value);
  if (class_exists($class) && $value instanceof $class) return true;
  if (substr($short, -6) === "String") return is_string($value);
  if (substr($short, -3) === "Int") return is_int($value);
  if (substr($short, -5) === "Float") return is_float($value) || is_int($value);
  if (substr($short, -4) === "Bool") return is_bool($value);
  if (substr($short, -9) === "Exception") return $value instanceof \Exception;
  if (substr($short, 0, 4) === "Enum") return is_string($value) || (is_object($value) && property_exists($value, "__hx_ctor"));
  return false;
}
function __hxhx_downcast($value, $type) {
  return __hxhx_is_of_type($value, $type) ? $value : null;
}
function __hxhx_cast($value, $type) {
  if ($value === null || __hxhx_is_of_type($value, $type)) return $value;
  throw ValueException::thrown("Class cast error");
}
