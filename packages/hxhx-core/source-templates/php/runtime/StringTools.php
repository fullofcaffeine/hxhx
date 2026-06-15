class StringTools {
  public static function urlEncode($value) {
    return rawurlencode(strval($value));
  }
  public static function urlDecode($value) {
    return rawurldecode(strval($value));
  }
  public static function replace($value, $sub, $by) {
    return str_replace(strval($sub), strval($by), strval($value));
  }
  public static function hex($value, $digits = null) {
    $hex = strtoupper(dechex(intval($value) & 0xFFFFFFFF));
    if ($digits !== null) $hex = str_pad($hex, intval($digits), "0", STR_PAD_LEFT);
    return $hex;
  }
}
