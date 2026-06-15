namespace haxe {
  class Template {
    private $template;
    public function __construct($template) {
      $this->template = strval($template);
    }
    public function execute($context) {
      $result = $this->template;
      foreach (get_object_vars($context) as $key => $value) {
        $result = str_replace("::" . $key . "::", strval($value), $result);
      }
      return $result;
    }
  }
  class Json {
    public static function parse($text) {
      $decoded = json_decode(strval($text));
      if (json_last_error() !== JSON_ERROR_NONE) throw new \Exception(json_last_error_msg());
      return $decoded;
    }
    private static function encodeValue($value, $replacer = null, $key = "") {
      if (is_callable($replacer)) $value = $replacer(strval($key), $value);
      if ($value instanceof \__HxArray) $value = $value->toArray();
      if (is_callable($value)) return "<fun>";
      if (is_array($value)) {
        $out = [];
        foreach ($value as $itemKey => $item) $out[$itemKey] = self::encodeValue($item, $replacer, $itemKey);
        return $out;
      }
      if (is_object($value)) {
        if (property_exists($value, "__hx_value")) return self::encodeValue($value->__hx_value, $replacer, $key);
        $out = new \stdClass();
        foreach (get_object_vars($value) as $key => $item) {
          if (strpos($key, "__hx_") === 0) continue;
          if (is_callable($item)) continue;
          $out->$key = self::encodeValue($item, $replacer, $key);
        }
        return $out;
      }
      if (is_float($value) && (is_nan($value) || is_infinite($value))) return null;
      return $value;
    }
    public static function stringify($value, $replacer = null, $space = null) {
      return json_encode(self::encodeValue($value, $replacer, ""), JSON_UNESCAPED_SLASHES);
    }
  }
  class Http {
    public static $PROXY = null;
    public $url;
    public $onData;
    public $onBytes;
    public $onError;
    public $onStatus;
    public $responseBytes = null;
    private $responseAsString = null;
    private $postData = null;
    private $postBytes = null;
    private $headers = [];
    private $params = [];
    public function __construct($url) {
      $this->url = $url;
      $this->onData = function($data) {};
      $this->onBytes = function($data) {};
      $this->onError = function($msg) {};
      $this->onStatus = function($status) {};
    }
    public function __get($name) {
      if ($name === "responseData") return $this->responseData();
      return null;
    }
    public function setHeader($name, $value) { $this->headers[strval($name)] = strval($value); return $this; }
    public function addHeader($name, $value) { $this->headers[strval($name)] = strval($value); return $this; }
    public function setParameter($name, $value) { $this->params[strval($name)] = strval($value); return $this; }
    public function addParameter($name, $value) { $this->params[strval($name)] = strval($value); return $this; }
    public function setPostData($data) { $this->postData = $data; $this->postBytes = null; return $this; }
    public function setPostBytes($data) { $this->postBytes = $data; $this->postData = null; return $this; }
    private function responseData() {
      if ($this->responseAsString === null && $this->responseBytes !== null) $this->responseAsString = $this->responseBytes->toString();
      return $this->responseAsString;
    }
    private function bytesPayload($value) {
      if ($value instanceof \haxe\io\Bytes) return $value->toString();
      if (is_object($value) && method_exists($value, "toString")) return $value->toString();
      return $value === null ? null : strval($value);
    }
    public function request($post = null) {
      $payload = $this->postBytes !== null ? $this->bytesPayload($this->postBytes) : ($this->postData === null ? null : strval($this->postData));
      $usePost = $post === null ? $payload !== null : (bool)$post;
      $url = strval($this->url);
      if (strpos($url, "http://localhost:") === 0) $url = "http://127.0.0.1:" . substr($url, strlen("http://localhost:"));
      if (!$usePost && count($this->params) > 0) $url .= (strpos($url, "?") === false ? "?" : "&") . http_build_query($this->params);
      $headerLines = [];
      foreach ($this->headers as $name => $value) $headerLines[] = $name . ": " . $value;
      $options = ["http" => ["method" => $usePost ? "POST" : "GET", "ignore_errors" => true]];
      if ($payload !== null) $options["http"]["content"] = $payload;
      if (count($headerLines) > 0) $options["http"]["header"] = implode("\r\n", $headerLines);
      $context = stream_context_create($options);
      $body = @file_get_contents($url, false, $context);
      if (isset($http_response_header) && is_array($http_response_header)) {
        foreach ($http_response_header as $line) if (preg_match('/^HTTP\/\S+\s+(\d+)/', $line, $m)) { $status = intval($m[1]); $cb = $this->onStatus; $cb($status); break; }
      }
      if ($body === false) { $err = error_get_last(); $cb = $this->onError; $cb($err === null ? "Http request failed" : $err["message"]); return null; }
      $this->responseAsString = strval($body);
      $this->responseBytes = \haxe\io\Bytes::ofString($this->responseAsString);
      $dataCb = $this->onData; $dataCb($this->responseAsString);
      $bytesCb = $this->onBytes; $bytesCb($this->responseBytes);
      return null;
    }
  }
  class Serializer {
    public static $USE_CACHE = false;
    public static $USE_ENUM_INDEX = false;
    private $buf = "";
    private $cache = [];
    private function write($value) { $this->buf .= $value; }
    private function cacheRef($value) {
      if (!self::$USE_CACHE || !is_object($value)) return false;
      $id = spl_object_id($value);
      if (array_key_exists($id, $this->cache)) { $this->write("r" . $this->cache[$id]); return true; }
      $this->cache[$id] = count($this->cache);
      return false;
    }
    private function encodeString($value) {
      $encoded = rawurlencode(strval($value));
      $this->write("y" . strlen($encoded) . ":" . $encoded);
    }
    private function encodeFloat($value) {
      $text = sprintf("%.15G", $value);
      if (strpos($text, ".") !== false) $text = rtrim(rtrim($text, "0"), ".");
      return $text;
    }
    private function encodeFields($value) {
      foreach (get_object_vars($value) as $key => $fieldValue) {
        if (strpos($key, "__hx_") === 0) continue;
        if (is_callable($fieldValue)) continue;
        $this->encodeString($key);
        $this->serializeValue($fieldValue);
      }
      $this->write("g");
    }
    private function encodeMap($map) {
      $kind = $map->__hx_type === "haxe.ds.IntMap" ? "q" : ($map->__hx_type === "haxe.ds.ObjectMap" ? "M" : "b");
      $this->write($kind);
      foreach ($map->keys() as $key) {
        if ($kind === "b") $this->encodeString($key);
        else if ($kind === "q") $this->write(":" . intval($key));
        else $this->serializeValue($key);
        $this->serializeValue($map->get($key));
      }
      $this->write("h");
    }
    private function encodeArrayItems($items) {
      $this->write("a");
      $nulls = 0;
      foreach ($items as $item) {
        if ($item === null) { $nulls++; continue; }
        if ($nulls > 0) { $this->write($nulls === 1 ? "n" : "u" . $nulls); $nulls = 0; }
        $this->serializeValue($item);
      }
      if ($nulls > 0) $this->write($nulls === 1 ? "n" : "u" . $nulls);
      $this->write("h");
    }
    public function serializeValue($value) {
      if ($value === null) { $this->write("n"); return; }
      if ($value === true) { $this->write("t"); return; }
      if ($value === false) { $this->write("f"); return; }
      if (is_int($value)) { $this->write($value === 0 ? "z" : "i" . $value); return; }
      if (is_float($value)) {
        if (is_nan($value)) $this->write("k");
        else if (is_infinite($value)) $this->write($value > 0 ? "p" : "m");
        else $this->write("d" . $this->encodeFloat($value));
        return;
      }
      if (is_string($value)) { $this->encodeString($value); return; }
      if ($value instanceof \__HxClassValue) {
        $name = \__hxhx_class_name($value);
        $candidate = \__hxhx_class_candidate($value);
        $this->write($candidate !== null && property_exists($candidate, "__hx_is_enum") ? "B" : "A");
        $this->encodeString($name);
        return;
      }
      if ($value instanceof \__HxArray) { $this->encodeArrayItems($value->toArray()); return; }
      if (is_array($value)) { $this->encodeArrayItems(array_values($value)); return; }
      if ($value instanceof \Map) { $this->encodeMap($value); return; }
      if ($value instanceof \List_) { $this->write("l"); foreach ($value->getIterator() as $item) $this->serializeValue($item); $this->write("h"); return; }
      if ($value instanceof \Date) { $this->write("v" . $this->encodeFloat($value->getTime())); return; }
      if ($value instanceof \haxe\io\Bytes) {
        $encoded = str_replace(["+", "/", "="], ["%", ":", ""], base64_encode($value->toString()));
        $this->write("s" . strlen($encoded) . ":" . $encoded);
        return;
      }
      if (is_object($value) && property_exists($value, "__hx_enum")) {
        $this->write(self::$USE_ENUM_INDEX ? "j" : "w");
        $this->encodeString($value->__hx_enum);
        if (self::$USE_ENUM_INDEX) $this->write(":" . intval($value->__hx_index)); else $this->encodeString($value->__hx_ctor);
        $params = property_exists($value, "__hx_params") && is_array($value->__hx_params) ? $value->__hx_params : [];
        $this->write(":" . count($params));
        foreach ($params as $param) $this->serializeValue($param);
        return;
      }
      if (is_object($value)) {
        if ($this->cacheRef($value)) return;
        if ($value instanceof \__HxAnon || get_class($value) === "stdClass") { $this->write("o"); $this->encodeFields($value); return; }
        $this->write("c");
        $this->encodeString(\__hxhx_class_name(get_class($value)));
        $this->encodeFields($value);
        return;
      }
      $this->write("n");
    }
    public function toString() { return $this->buf; }
    public static function run($value) { $s = new Serializer(); $s->serializeValue($value); return $s->toString(); }
  }
  class Unserializer {
    private $buf;
    private $pos = 0;
    private $cache = [];
    public function __construct($buf) { if ($buf === null) throw new \Exception("Invalid serialized data"); $this->buf = strval($buf); }
    private function readUntil($chars) {
      $start = $this->pos;
      $len = strlen($this->buf);
      while ($this->pos < $len && strpos($chars, $this->buf[$this->pos]) === false) $this->pos++;
      return substr($this->buf, $start, $this->pos - $start);
    }
    private function readIntUntil($chars) { return intval($this->readUntil($chars)); }
    private function readStringPayload() {
      $len = $this->readIntUntil(":");
      if ($this->pos >= strlen($this->buf) || $this->buf[$this->pos] !== ":") throw new \Exception("Invalid serialized string");
      $this->pos++;
      $raw = substr($this->buf, $this->pos, $len);
      if (strlen($raw) !== $len) throw new \Exception("Invalid serialized string");
      $this->pos += $len;
      return rawurldecode($raw);
    }
    private function readFields($obj) {
      $this->cache[] = $obj;
      while ($this->pos < strlen($this->buf) && $this->buf[$this->pos] !== "g") {
        if ($this->buf[$this->pos++] !== "y") throw new \Exception("Invalid object field");
        $name = $this->readStringPayload();
        $obj->$name = $this->unserializeValue();
      }
      if ($this->pos >= strlen($this->buf)) throw new \Exception("Invalid object terminator");
      $this->pos++;
      return $obj;
    }
    private function readArray() {
      $items = [];
      $this->cache[] = &$items;
      while ($this->pos < strlen($this->buf) && $this->buf[$this->pos] !== "h") {
        if ($this->buf[$this->pos] === "u") { $this->pos++; $count = $this->readIntUntil("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ:"); for ($i = 0; $i < $count; $i++) $items[] = null; continue; }
        $items[] = $this->unserializeValue();
      }
      if ($this->pos >= strlen($this->buf)) throw new \Exception("Invalid array terminator");
      $this->pos++;
      return $items;
    }
    private function readList() {
      $list = new \List_();
      $this->cache[] = $list;
      while ($this->pos < strlen($this->buf) && $this->buf[$this->pos] !== "h") $list->add($this->unserializeValue());
      if ($this->pos >= strlen($this->buf)) throw new \Exception("Invalid list terminator");
      $this->pos++;
      return $list;
    }
    private function readMap($kind) {
      $type = $kind === "q" ? "haxe.ds.IntMap" : ($kind === "M" ? "haxe.ds.ObjectMap" : "haxe.ds.StringMap");
      $map = new \Map(null, $type);
      $this->cache[] = $map;
      while ($this->pos < strlen($this->buf) && $this->buf[$this->pos] !== "h") {
        if ($kind === "b") { if ($this->buf[$this->pos++] !== "y") throw new \Exception("Invalid string map key"); $key = $this->readStringPayload(); }
        else if ($kind === "q") { if ($this->buf[$this->pos++] !== ":") throw new \Exception("Invalid int map key"); $key = $this->readIntUntil("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ:"); }
        else $key = $this->unserializeValue();
        $map->set($key, $this->unserializeValue());
      }
      if ($this->pos >= strlen($this->buf)) throw new \Exception("Invalid map terminator");
      $this->pos++;
      return $map;
    }
    public function unserializeValue() {
      if ($this->pos >= strlen($this->buf)) throw new \Exception("Invalid serialized data");
      $tag = $this->buf[$this->pos++];
      switch ($tag) {
        case "n": return null;
        case "t": return true;
        case "f": return false;
        case "z": return 0;
        case "i": return $this->readIntUntil("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ:");
        case "d": return floatval($this->readUntil("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"));
        case "k": return NAN;
        case "p": return INF;
        case "m": return -INF;
        case "y": return $this->readStringPayload();
        case "a": return $this->readArray();
        case "l": return $this->readList();
        case "b": case "q": case "M": return $this->readMap($tag);
        case "s": $len = $this->readIntUntil(":"); $this->pos++; $raw = substr($this->buf, $this->pos, $len); $this->pos += $len; return \haxe\io\Bytes::ofString(base64_decode(str_replace(["%", ":"], ["+", "/"], $raw), true));
        case "v": return \Date::fromTime(floatval($this->readUntil("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")));
        case "A": if ($this->buf[$this->pos++] !== "y") throw new \Exception("Invalid class value"); return \__hxhx_class_value($this->readStringPayload());
        case "B": if ($this->buf[$this->pos++] !== "y") throw new \Exception("Invalid enum value"); return \__hxhx_class_value($this->readStringPayload());
        case "o": return $this->readFields(new \__HxAnon());
        case "c":
          if ($this->buf[$this->pos++] !== "y") throw new \Exception("Invalid class instance");
          $runtime = \__hxhx_runtime_class_name($this->readStringPayload());
          $obj = class_exists($runtime) ? (new \ReflectionClass($runtime))->newInstanceWithoutConstructor() : new \__HxAnon();
          return $this->readFields($obj);
        case "w": case "j":
          if ($this->buf[$this->pos++] !== "y") throw new \Exception("Invalid enum instance");
          $enumName = $this->readStringPayload();
          if ($tag === "j") { if ($this->buf[$this->pos++] !== ":") throw new \Exception("Invalid enum index"); $index = $this->readIntUntil(":"); if ($this->pos >= strlen($this->buf) || $this->buf[$this->pos++] !== ":") throw new \Exception("Invalid enum arity"); $ctor = null; }
          else { if ($this->buf[$this->pos++] !== "y") throw new \Exception("Invalid enum ctor"); $ctor = $this->readStringPayload(); $index = 0; if ($this->buf[$this->pos++] !== ":") throw new \Exception("Invalid enum arity"); }
          $argc = $this->readIntUntil("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ:");
          $args = [];
          for ($i = 0; $i < $argc; $i++) $args[] = $this->unserializeValue();
          if ($ctor === null) $ctor = \__hxhx_enum_ctor_by_index($enumName, $index);
          if ($ctor !== null) { try { return \Type::createEnum(\__hxhx_class_value($enumName), $ctor, $args); } catch (\Throwable $_) {} }
          return new \__HxAnon(["__hx_enum" => $enumName, "__hx_ctor" => $ctor === null ? strval($index) : $ctor, "__hx_index" => intval($index), "__hx_params" => $args]);
        case "r": $index = $this->readIntUntil("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ:"); if (!array_key_exists($index, $this->cache)) throw new \Exception("Invalid reference"); return $this->cache[$index];
      }
      throw new \Exception("Invalid serialized tag: " . $tag);
    }
    public static function run($value) { $u = new Unserializer($value); return $u->unserializeValue(); }
  }
  class Int64 {
    public $high;
    public $low;
    public function __construct($high, $low) {
      $this->high = \__hxhx_int32_value($high);
      $this->low = \__hxhx_int32_value($low);
    }
    public static function make($high, $low) {
      return new Int64($high, $low);
    }
    public static function ofInt($value) {
      $low = \__hxhx_int32_value($value);
      return new Int64($low < 0 ? -1 : 0, $low);
    }
    public static function add($left, $right) {
      return \__hxhx_int64_add($left, $right);
    }
    public static function sub($left, $right) {
      return \__hxhx_int64_sub($left, $right);
    }
    public static function mul($left, $right) {
      return \__hxhx_int64_mul($left, $right);
    }
    public static function neg($value) {
      return \__hxhx_int64_neg($value);
    }
    public static function divMod($dividend, $divisor) {
      return \__hxhx_int64_div_mod($dividend, $divisor);
    }
    public static function parseString($value) {
      return \__hxhx_int64_parse_string($value);
    }
    public static function fromFloat($value) {
      return \__hxhx_int64_from_float($value);
    }
    public static function toStr($value) {
      return \__hxhx_int64_to_string($value);
    }
    public static function compare($left, $right) {
      return \__hxhx_int64_compare($left, $right);
    }
    public static function ucompare($left, $right) {
      return \__hxhx_int64_ucompare($left, $right);
    }
    public function get_high() {
      return $this->high;
    }
    public function get_low() {
      return $this->low;
    }
    public function toInt() {
      $expectedHigh = $this->low < 0 ? -1 : 0;
      if ($this->high !== $expectedHigh) throw \ValueException::thrown("Overflow");
      return $this->low;
    }
    public function toString() {
      return \__hxhx_int64_to_string($this);
    }
    public function __toString() {
      return $this->toString();
    }
  }
}
