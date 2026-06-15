namespace php {
  class Web {
    public static $isModNeko = false;
    public static function setHeader($name, $value) {
      if (!headers_sent()) {
        header($name . ": " . $value);
      }
    }
  }
}
