class Sys {
  /** Convert once through Haxe's value representation before writing console bytes. */
  public static function print($value) {
    echo __hxhx_add_string($value);
  }
  /** Share conversion with print so Boolean and null values have the same text. */
  public static function println($value) {
    self::print($value);
    echo PHP_EOL;
  }
  public static function args() {
    $argv = $GLOBALS["argv"] ?? [];
    return new __HxArray(array_slice($argv, 1));
  }
}
