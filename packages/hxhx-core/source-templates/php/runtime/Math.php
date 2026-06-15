class Math {
  public static function abs($value) {
    return abs($value);
  }
  public static function acos($value) {
    return acos($value);
  }
  public static function asin($value) {
    return asin($value);
  }
  public static function atan($value) {
    return atan($value);
  }
  public static function atan2($y, $x) {
    return atan2($y, $x);
  }
  public static function cos($value) {
    return cos($value);
  }
  public static function exp($value) {
    return exp($value);
  }
  public static function isNaN($value) {
    return is_nan($value);
  }
  public static function isFinite($value) {
    return is_finite($value);
  }
  public static function log($value) {
    return log($value);
  }
  public static function max($a, $b) {
    return max($a, $b);
  }
  public static function min($a, $b) {
    return min($a, $b);
  }
  public static function pow($a, $b) {
    return pow($a, $b);
  }
  public static function random() {
    return mt_rand() / (mt_getrandmax() + 1.0);
  }
  public static function sin($value) {
    return sin($value);
  }
  public static function sqrt($value) {
    return sqrt($value);
  }
  public static function tan($value) {
    return tan($value);
  }
  public static function floor($value) {
    return floor($value);
  }
  public static function ceil($value) {
    return ceil($value);
  }
  public static function round($value) {
    return floor($value + 0.5);
  }
  public static function ffloor($value) {
    return floor($value);
  }
  public static function fceil($value) {
    return ceil($value);
  }
  public static function fround($value) {
    return floor($value + 0.5);
  }
}
