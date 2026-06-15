class Date {
  private $timestamp;
  public function __construct($year, $month, $day, $hour, $min, $sec) {
    $this->timestamp = mktime((int)$hour, (int)$min, (int)$sec, (int)$month + 1, (int)$day, (int)$year);
  }
  private static function fromSeconds($seconds) {
    $date = new self(1970, 0, 1, 0, 0, 0);
    $date->timestamp = (float)$seconds;
    return $date;
  }
  public static function now() { return self::fromSeconds(microtime(true)); }
  public static function fromTime($t) { return self::fromSeconds(((float)$t) / 1000.0); }
  public static function fromString($s) {
    $text = strval($s);
    if (preg_match('/^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2}):(\d{2}))?$/', $text, $m)) {
      $hour = isset($m[4]) && $m[4] !== '' ? (int)$m[4] : 0;
      $min = isset($m[5]) && $m[5] !== '' ? (int)$m[5] : 0;
      $sec = isset($m[6]) && $m[6] !== '' ? (int)$m[6] : 0;
      return new self((int)$m[1], (int)$m[2] - 1, (int)$m[3], $hour, $min, $sec);
    }
    if (preg_match('/^(\d{2}):(\d{2}):(\d{2})$/', $text, $m)) {
      return self::fromSeconds(gmmktime((int)$m[1], (int)$m[2], (int)$m[3], 1, 1, 1970));
    }
    throw new \Exception("Invalid date format: " . $text);
  }
  private function local($format) { return (int)date($format, (int)floor($this->timestamp)); }
  private function utc($format) { return (int)gmdate($format, (int)floor($this->timestamp)); }
  public function getTime() { return $this->timestamp * 1000.0; }
  public function getHours() { return $this->local("G"); }
  public function getMinutes() { return $this->local("i"); }
  public function getSeconds() { return $this->local("s"); }
  public function getFullYear() { return $this->local("Y"); }
  public function getMonth() { return $this->local("n") - 1; }
  public function getDate() { return $this->local("j"); }
  public function getDay() { return $this->local("w"); }
  public function getUTCHours() { return $this->utc("G"); }
  public function getUTCMinutes() { return $this->utc("i"); }
  public function getUTCSeconds() { return $this->utc("s"); }
  public function getUTCFullYear() { return $this->utc("Y"); }
  public function getUTCMonth() { return $this->utc("n") - 1; }
  public function getUTCDate() { return $this->utc("j"); }
  public function getUTCDay() { return $this->utc("w"); }
  public function getTimezoneOffset() {
    $dt = (new \DateTimeImmutable("@" . strval((int)floor($this->timestamp))))->setTimezone(new \DateTimeZone(date_default_timezone_get()));
    return (int)(-((int)$dt->format("Z")) / 60);
  }
  public function toString() { return date("Y-m-d H:i:s", (int)floor($this->timestamp)); }
  public function __toString() { return $this->toString(); }
}
