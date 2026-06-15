class StringBuf {
  private $parts = [];
  public $length = 0;
  private function appendText($text) {
    $value = strval($text);
    $this->parts[] = $value;
    $this->length += function_exists("mb_strlen") ? mb_strlen($value, "UTF-8") : strlen($value);
  }
  public function add($value) {
    $this->appendText(__hxhx_add_string($value));
    return null;
  }
  public function addSub($value, $pos, $len = null) {
    $text = strval($value);
    $start = (int)$pos;
    if (function_exists("mb_substr")) {
      $part = $len === null ? mb_substr($text, $start, null, "UTF-8") : mb_substr($text, $start, (int)$len, "UTF-8");
    } else {
      $part = $len === null ? substr($text, $start) : substr($text, $start, (int)$len);
    }
    $this->appendText($part === false ? "" : $part);
    return null;
  }
  public function addChar($code) {
    $value = (int)$code;
    if (function_exists("mb_chr")) {
      $this->appendText(mb_chr($value, "UTF-8"));
    } else {
      $this->appendText(html_entity_decode("&#" . $value . ";", ENT_NOQUOTES, "UTF-8"));
    }
    return null;
  }
  public function toString() { return implode("", $this->parts); }
  public function __toString() { return $this->toString(); }
}
