class Std {
  public static function int($value) {
    return intval($value);
  }
  public static function random($x) {
    $limit = intval($x);
    return $limit <= 0 ? 0 : mt_rand(0, $limit - 1);
  }
  public static function parseInt($value) {
    if ($value === null) return null;
    $text = strval($value);
    if (preg_match('/^([+-]?)0[xX]([0-9a-fA-F]+)/', $text, $matches)) {
      $parsed = intval($matches[2], 16);
      return $matches[1] === '-' ? -$parsed : $parsed;
    }
    if (preg_match('/^[+-]?[0-9]+/', $text, $matches)) return intval($matches[0], 10);
    return null;
  }
  public static function parseFloat($value) {
    return floatval($value);
  }
}
