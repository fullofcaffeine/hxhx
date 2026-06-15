class Sys {
  public static function args() {
    $argv = $GLOBALS["argv"] ?? [];
    return new __HxArray(array_slice($argv, 1));
  }
}
