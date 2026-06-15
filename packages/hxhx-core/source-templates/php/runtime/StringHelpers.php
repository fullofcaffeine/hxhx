function __hxhx_string_index_of($value, $needle, $start = 0) {
  if (is_array($value) || $value instanceof __HxArray) return __hxhx_array_index_of($value, $needle);
  $s = __hxhx_string_value($value);
  $n = __hxhx_string_value($needle);
  $len = strlen($s);
  $offset = $start === null ? 0 : (int)$start;
  if ($offset < 0) $offset = max(0, $len + $offset);
  if ($offset > $len) return $n === "" ? $len : -1;
  $pos = strpos($s, $n, $offset);
  return $pos === false ? -1 : $pos;
}
function __hxhx_string_last_index_of($value, $needle, $start = null) {
  $s = __hxhx_string_value($value);
  $n = __hxhx_string_value($needle);
  $len = strlen($s);
  if ($start === null) {
    $haystack = $s;
  } else {
    $offset = (int)$start;
    if ($offset < 0) $offset = $len + $offset;
    if ($offset < 0) return -1;
    $haystack = substr($s, 0, min($len, $offset + strlen($n)));
  }
  $pos = strrpos($haystack, $n);
  return $pos === false ? -1 : $pos;
}
function __hxhx_string_from_char_code($code) {
  $value = (int)$code;
  $value = (($value % 256) + 256) % 256;
  return chr($value);
}
function __hxhx_string_split($value, $delimiter) {
  $s = __hxhx_string_value($value);
  $d = __hxhx_string_value($delimiter);
  if ($d === "") return str_split($s);
  return explode($d, $s);
}
function __hxhx_string_char_at($value, $index) {
  $s = __hxhx_string_value($value);
  $i = (int)$index;
  return ($i < 0 || $i >= strlen($s)) ? "" : $s[$i];
}
function __hxhx_string_char_code_at($value, $index) {
  $s = __hxhx_string_value($value);
  $i = (int)$index;
  if ($i < 0 || $i >= strlen($s)) return null;
  return ord($s[$i]);
}
function __hxhx_string_substr($value, $pos, $len = null) {
  $s = __hxhx_string_value($value);
  $p = (int)$pos;
  $result = $len === null ? substr($s, $p) : substr($s, $p, (int)$len);
  return $result === false ? "" : $result;
}
function __hxhx_string_substring($value, $start, $end = null) {
  $s = __hxhx_string_value($value);
  $len = strlen($s);
  $a = max(0, min($len, (int)$start));
  $b = $end === null ? $len : max(0, min($len, (int)$end));
  if ($a > $b) { $tmp = $a; $a = $b; $b = $tmp; }
  return substr($s, $a, $b - $a);
}
function __hxhx_string_method_exists($name) {
  switch (strval($name)) {
    case "charAt": case "indexOf": case "lastIndexOf": case "split": case "charCodeAt": case "substr": case "substring": case "toString": case "toUpperCase": case "toLowerCase": return true;
  }
  return false;
}
