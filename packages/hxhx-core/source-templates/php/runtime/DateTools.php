class DateTools {
  private static function pad($value, $pad, $len) { return str_pad(strval($value), $len, strval($pad), STR_PAD_LEFT); }
  private static function formatGet($d, $e) {
    static $dayShort = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
    static $dayLong = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
    static $monthShort = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    static $monthLong = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
    switch (strval($e)) {
      case "%": return "%";
      case "a": return $dayShort[$d->getDay()];
      case "A": return $dayLong[$d->getDay()];
      case "b": case "h": return $monthShort[$d->getMonth()];
      case "B": return $monthLong[$d->getMonth()];
      case "C": return self::pad(intdiv($d->getFullYear(), 100), "0", 2);
      case "d": return self::pad($d->getDate(), "0", 2);
      case "D": return self::format($d, "%m/%d/%y");
      case "e": return strval($d->getDate());
      case "F": return self::format($d, "%Y-%m-%d");
      case "H": return self::pad($d->getHours(), "0", 2);
      case "k": return self::pad($d->getHours(), " ", 2);
      case "I": $hour = $d->getHours() % 12; return self::pad($hour == 0 ? 12 : $hour, "0", 2);
      case "l": $hour = $d->getHours() % 12; return self::pad($hour == 0 ? 12 : $hour, " ", 2);
      case "m": return self::pad($d->getMonth() + 1, "0", 2);
      case "M": return self::pad($d->getMinutes(), "0", 2);
      case "n": return "\n";
      case "p": return $d->getHours() > 11 ? "PM" : "AM";
      case "r": return self::format($d, "%I:%M:%S %p");
      case "R": return self::format($d, "%H:%M");
      case "s": return strval((int)floor($d->getTime() / 1000.0));
      case "S": return self::pad($d->getSeconds(), "0", 2);
      case "t": return "\t";
      case "T": return self::format($d, "%H:%M:%S");
      case "u": $day = $d->getDay(); return $day == 0 ? "7" : strval($day);
      case "w": return strval($d->getDay());
      case "y": return self::pad($d->getFullYear() % 100, "0", 2);
      case "Y": return strval($d->getFullYear());
      default: throw new \Exception("Date.format %" . strval($e) . " not implemented yet.");
    }
  }
  public static function format($d, $f) {
    $format = strval($f);
    $out = "";
    $offset = 0;
    while (($pos = strpos($format, "%", $offset)) !== false) {
      $out .= substr($format, $offset, $pos - $offset);
      $out .= self::formatGet($d, substr($format, $pos + 1, 1));
      $offset = $pos + 2;
    }
    return $out . substr($format, $offset);
  }
  public static function delta($d, $t) { return Date::fromTime($d->getTime() + (float)$t); }
  public static function getMonthDays($d) {
    $month = $d->getMonth();
    if ($month != 1) return [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][$month];
    $year = $d->getFullYear();
    return (($year % 4 == 0 && $year % 100 != 0) || $year % 400 == 0) ? 29 : 28;
  }
  public static function seconds($n) { return (float)$n * 1000.0; }
  public static function minutes($n) { return (float)$n * 60.0 * 1000.0; }
  public static function hours($n) { return (float)$n * 60.0 * 60.0 * 1000.0; }
  public static function days($n) { return (float)$n * 24.0 * 60.0 * 60.0 * 1000.0; }
  public static function parse($t) {
    $s = (float)$t / 1000.0;
    $m = $s / 60.0;
    $h = $m / 60.0;
    return new __HxAnon(["ms" => fmod((float)$t, 1000.0), "seconds" => (int)floor(fmod($s, 60.0)), "minutes" => (int)floor(fmod($m, 60.0)), "hours" => (int)floor(fmod($h, 24.0)), "days" => (int)floor($h / 24.0)]);
  }
  public static function make($o) { return $o->ms + 1000.0 * ($o->seconds + 60.0 * ($o->minutes + 60.0 * ($o->hours + 24.0 * $o->days))); }
  public static function makeUtc($year, $month, $day, $hour, $min, $sec) { return gmmktime((int)$hour, (int)$min, (int)$sec, (int)$month + 1, (int)$day, (int)$year) * 1000.0; }
}
