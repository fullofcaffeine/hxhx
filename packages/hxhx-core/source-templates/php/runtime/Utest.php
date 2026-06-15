class __HxDispatcher {
  public function add($listener) {
    return $listener;
  }
  public function dispatch($event) {
    return null;
  }
}
class __HxUtestAsync {
  public $resolved = false;
  public $timedOut = false;
  public function done($pos = null) {
    $this->resolved = true;
    return null;
  }
  public function setTimeout($timeoutMs, $pos = null) {
    return null;
  }
  public function branch($fn = null, $pos = null) {
    $branch = new __HxUtestAsync();
    if ($fn !== null) $fn($branch);
    return $branch;
  }
}
class Runner {
  private $cases;
  public $onProgress;
  public $onTestStart;
  public function __construct() {
    $this->cases = [];
    $this->onProgress = new __HxDispatcher();
    $this->onTestStart = new __HxDispatcher();
  }
  public function addCase($case) {
    $this->cases[] = $case;
    return null;
  }
  public function run() {
    $total = 0;
    foreach ($this->cases as $case) {
      foreach (get_class_methods($case) as $method) {
        if (strpos($method, "test") !== 0 && strpos($method, "spec") !== 0) continue;
        $total++;
        $this->onTestStart->dispatch($case);
        $reflection = new \ReflectionMethod($case, $method);
        if ($reflection->getNumberOfParameters() > 0) $case->$method(new __HxUtestAsync()); else $case->$method();
        $this->onProgress->dispatch((object)["result" => (object)["assertations" => []], "done" => $total, "totals" => $total]);
      }
    }
    return null;
  }
}
class Report {
  public $displayHeader;
  public $displaySuccessResults;
  public static function create($runner) {
    return new Report();
  }
}
class Assert {
  private static function failMessage($message) {
    throw new \Exception($message === null ? "assertion failed" : strval($message));
  }
  private static function ok($condition, $message = null) {
    if (!$condition) self::failMessage($message);
    return true;
  }
  private static function toArray($value) {
    if ($value instanceof __HxArray) return $value->toArray();
    return is_array($value) ? $value : [];
  }
  public static function isTrue($condition, $message = null, $pos = null) {
    return self::ok($condition === true, $message === null ? "expected true" : $message);
  }
  public static function isFalse($value, $message = null, $pos = null) {
    return self::ok($value === false, $message === null ? "expected false" : $message);
  }
  public static function isNull($value, $message = null, $pos = null) {
    return self::ok($value === null, $message === null ? "expected null" : $message);
  }
  public static function notNull($value, $message = null, $pos = null) {
    return self::ok($value !== null, $message === null ? "expected not null" : $message);
  }
  public static function equals($expected, $value, $message = null, $pos = null) {
    return self::ok(__hxhx_equals($expected, $value), $message === null ? "expected " . __hxhx_add_string($expected) . " but it is " . __hxhx_add_string($value) : $message);
  }
  public static function notEquals($expected, $value, $message = null, $pos = null) {
    return self::ok($expected != $value, $message === null ? "expected values to differ" : $message);
  }
  public static function floatEquals($expected, $value, $approx = null, $message = null, $pos = null) {
    $epsilon = $approx === null ? 1e-5 : $approx;
    $actual = __hxhx_numeric_value($value);
    $want = __hxhx_numeric_value($expected);
    return self::ok(abs($actual - $want) <= $epsilon, $message === null ? "expected " . __hxhx_add_string($expected) . " but it is " . __hxhx_add_string($value) : $message);
  }
  public static function same($expected, $value, $recursive = null, $message = null, $approx = null, $pos = null) {
    return self::ok($expected == $value, $message === null ? "expected same value" : $message);
  }
  public static function raises($method, $type = null, $msgNotThrown = null, $msgWrongType = null, $pos = null) {
    try { $method(); } catch (\Throwable $ex) { return true; }
    self::failMessage($msgNotThrown === null ? "exception not raised" : $msgNotThrown);
  }
  public static function allows($possibilities, $value, $message = null, $pos = null) {
    return self::ok(in_array($value, self::toArray($possibilities), true), $message === null ? "value not allowed" : $message);
  }
  public static function contains($match, $values, $message = null, $pos = null) {
    return self::ok(in_array($match, self::toArray($values), true), $message === null ? "values do not contain match" : $message);
  }
  public static function notContains($match, $values, $message = null, $pos = null) {
    return self::ok(!in_array($match, self::toArray($values), true), $message === null ? "values contain match" : $message);
  }
  public static function stringContains($match, $value, $message = null, $pos = null) {
    return self::ok($value !== null && strpos(strval($value), strval($match)) !== false, $message === null ? "value does not contain match" : $message);
  }
  public static function pass($message = "pass expected", $pos = null) {
    return true;
  }
  public static function fail($message = "failure expected", $pos = null) {
    self::failMessage($message);
  }
  public static function warn($message) {
    return null;
  }
}
