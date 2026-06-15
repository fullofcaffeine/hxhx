namespace haxe\xml {
  class Parser {
    public static function parse($source, $strict = true) {
      $text = strval($source);
      if (!$strict && strpos($text, "<") === false) {
        $doc = \Xml::createDocument();
        $doc->addChild(\Xml::createPCData(self::decodeEntities($text)));
        return $doc;
      }
      if ($strict) self::validateStrictAttributes($text);
      return \Xml::parse($text);
    }
    private static function validateStrictAttributes($text) {
      $len = strlen($text);
      for ($i = 0; $i < $len; $i++) {
        if ($text[$i] !== "<") continue;
        if ($i + 1 < $len && ($text[$i + 1] === "!" || $text[$i + 1] === "?" || $text[$i + 1] === "/")) continue;
        $quote = null;
        for ($j = $i + 1; $j < $len; $j++) {
          $ch = $text[$j];
          if ($quote !== null) {
            if ($ch === $quote) { $quote = null; continue; }
            if ($ch === "<" || $ch === ">") throw new \Exception("Xml parse error");
            continue;
          }
          if ($ch === "\"" || $ch === "'") { $quote = $ch; continue; }
          if ($ch === ">") { $i = $j; break; }
        }
      }
    }
    private static function decodeEntities($text) {
      return preg_replace_callback('/&(#x[0-9A-Fa-f]+|#[0-9]+|[A-Za-z]+);/', function($match) {
        $code = $match[1];
        if ($code === "lt") return "<";
        if ($code === "gt") return ">";
        if ($code === "quot") return "\"";
        if ($code === "amp") return "&";
        if ($code === "apos") return "'";
        if (strlen($code) > 2 && substr($code, 0, 2) === "#x") return html_entity_decode("&#x" . substr($code, 2) . ";", ENT_QUOTES | ENT_XML1, "UTF-8");
        if (strlen($code) > 1 && $code[0] === "#") return html_entity_decode("&#" . substr($code, 1) . ";", ENT_QUOTES | ENT_XML1, "UTF-8");
        return "&" . $code . ";";
      }, strval($text));
    }
  }
}
