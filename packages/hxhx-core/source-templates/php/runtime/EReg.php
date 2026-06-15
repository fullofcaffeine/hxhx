class EReg {
  private $pattern;
  private $modifiers;
  private $global;
  private $last = null;
  private $matches = [];
  public function __construct($pattern, $options) {
    $this->pattern = strval($pattern);
    $raw = strval($options);
    $this->global = strpos($raw, "g") !== false;
    $this->modifiers = str_replace("g", "", $raw);
  }
  private function delimiterPattern() {
    return str_replace("~", "\\~", $this->pattern);
  }
  private function regex($unicode) {
    $mods = $this->modifiers;
    if ($unicode && strpos($mods, "u") === false) $mods .= "u";
    return "~" . $this->delimiterPattern() . "~" . $mods;
  }
  private function stringLength($value) {
    $text = strval($value);
    return function_exists("mb_strlen") ? mb_strlen($text) : strlen($text);
  }
  private function runMatch($source, $offset) {
    $subject = strval($source);
    $flags = PREG_OFFSET_CAPTURE;
    if (defined("PREG_UNMATCHED_AS_NULL")) $flags |= PREG_UNMATCHED_AS_NULL;
    $matches = [];
    $result = @preg_match($this->regex(true), $subject, $matches, $flags, max(0, intval($offset)));
    if ($result === false) {
      $matches = [];
      $result = @preg_match($this->regex(false), $subject, $matches, $flags, max(0, intval($offset)));
    }
    if ($result === false) throw new \Exception("EReg: preg_match failed");
    $this->matches = $matches;
    $this->last = $result > 0 ? $source : null;
    return $result > 0;
  }
  private function requireMatch() {
    if ($this->last === null || !array_key_exists(0, $this->matches)) throw new \Exception("No string matched");
    return $this->matches[0];
  }
  public function match($source) {
    return $this->runMatch($source, 0);
  }
  public function matched($index) {
    $n = intval($index);
    if ($this->last === null || !array_key_exists(0, $this->matches) || $n < 0) throw new \Exception("EReg::matched");
    if (!array_key_exists($n, $this->matches)) return null;
    $entry = $this->matches[$n];
    if (!is_array($entry) || count($entry) < 2) return null;
    if ($entry[1] === -1 || $entry[0] === null) return null;
    return $entry[0];
  }
  public function matchedLeft() {
    $match = $this->requireMatch();
    return substr(strval($this->last), 0, $match[1]);
  }
  public function matchedRight() {
    $match = $this->requireMatch();
    $offset = $match[1] + strlen(strval($match[0]));
    return substr(strval($this->last), $offset);
  }
  public function matchedPos() {
    $match = $this->requireMatch();
    return (object)["pos" => $this->stringLength(substr(strval($this->last), 0, $match[1])), "len" => $this->stringLength($match[0])];
  }
  public function matchSub($source, $pos, $len = -1) {
    $text = strval($source);
    $start = max(0, intval($pos));
    $subject = intval($len) < 0 ? $text : substr($text, 0, $start + max(0, intval($len)));
    return $this->runMatch($subject, $start) ? ($this->last = $text) || true : false;
  }
  public function split($source) {
    $subject = strval($source);
    $limit = $this->global ? -1 : 2;
    $parts = @preg_split($this->regex(true), $subject, $limit);
    if ($parts === false) $parts = @preg_split($this->regex(false), $subject, $limit);
    if ($parts === false) throw new \Exception("EReg: preg_split failed");
    return array_values($parts);
  }
  public function replace($source, $replacement) {
    $subject = strval($source);
    $limit = $this->global ? -1 : 1;
    $result = @preg_replace($this->regex(true), strval($replacement), $subject, $limit);
    if ($result === null) $result = @preg_replace($this->regex(false), strval($replacement), $subject, $limit);
    if ($result === null) throw new \Exception("EReg: preg_replace failed");
    return $result;
  }
  public function map($source, $callback) {
    $text = strval($source);
    if (!$this->runMatch($text, 0)) return $text;
    $result = "";
    $offset = 0;
    $total = strlen($text);
    do {
      $match = $this->matches[0];
      $matchText = strval($match[0]);
      $matchOffset = $match[1];
      $result .= substr($text, $offset, $matchOffset - $offset);
      $result .= $callback($this);
      $offset = $matchOffset;
      if ($matchText === "") {
        if ($offset >= $total) break;
        $result .= substr($text, $offset, 1);
        $offset += 1;
      } else {
        $offset += strlen($matchText);
      }
    } while ($this->global && $offset < $total && $this->runMatch($text, $offset));
    $result .= substr($text, $offset);
    return $result;
  }
  public static function escape($value) {
    return preg_quote(strval($value));
  }
}
