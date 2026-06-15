namespace haxe\format {
  class JsonParser {
    public static function parse($text) {
      return \haxe\Json::parse($text);
    }
  }
  class JsonPrinter {
    public static function print($value, $replacer = null, $space = null) {
      return \haxe\Json::stringify($value, $replacer, $space);
    }
  }
}
