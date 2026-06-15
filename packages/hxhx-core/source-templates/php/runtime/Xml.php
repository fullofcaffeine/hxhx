class Xml implements \IteratorAggregate {
  public static $Element = 0;
  public static $PCData = 1;
  public static $CData = 2;
  public static $Comment = 3;
  public static $DocType = 4;
  public static $ProcessingInstruction = 5;
  public static $Document = 6;
  public $attributes;
  public $elements;
  public $elementsNamed;
  private $type;
  private $name;
  private $value;
  private $attrMap;
  private $children;
  private $selfClosing;
  private $parent;
  private function __construct($type, $name = null, $value = null, $attrs = [], $children = [], $selfClosing = false) {
    $this->type = $type;
    $this->name = $name;
    $this->value = $value;
    $this->attrMap = $attrs;
    $this->children = [];
    $this->selfClosing = $selfClosing;
    $this->parent = null;
    $this->setChildren($children);
    $this->attributes = function() { return $this->attributes(); };
    $this->elements = function() { return $this->elements(); };
    $this->elementsNamed = function($name) { return $this->elementsNamed($name); };
  }
  public static function createDocument() { return new Xml(self::$Document, null, null, [], []); }
  public static function createElement($name) { return new Xml(self::$Element, strval($name), null, [], [], true); }
  public static function createPCData($value) { return new Xml(self::$PCData, null, strval($value), [], []); }
  public static function createCData($value) { return new Xml(self::$CData, null, strval($value), [], []); }
  public static function createComment($value) { return new Xml(self::$Comment, null, strval($value), [], []); }
  public static function createDocType($value) { return new Xml(self::$DocType, null, strval($value), [], []); }
  public static function createProcessingInstruction($value) { return new Xml(self::$ProcessingInstruction, null, strval($value), [], []); }
  public static function parse($source) {
    $text = strval($source);
    $i = 0;
    $doc = self::createDocument();
    $doc->setChildren(self::parseNodes($text, $i, null));
    if ($i !== strlen($text)) self::parseError();
    return $doc;
  }
  private static function parseNodes($source, &$i, $closing) {
    $children = [];
    $len = strlen($source);
    while ($i < $len) {
      if (substr($source, $i, 2) === "</") {
        $i += 2;
        $name = self::readName($source, $i);
        self::skipWhitespace($source, $i);
        if ($i >= $len || $source[$i] !== ">") self::parseError();
        if ($closing === null || $name !== $closing) self::parseError("Unexpected </" . $name . ">, tag is not open");
        $i++;
        return $children;
      }
      if ($source[$i] === "<") {
        if (substr($source, $i, 9) === "<![CDATA[") {
          $children[] = self::parseDelimited($source, $i, "<![CDATA[", "]]>", self::$CData);
          continue;
        }
        if (substr($source, $i, 4) === "<!--") {
          $children[] = self::parseDelimited($source, $i, "<!--", "-->", self::$Comment);
          continue;
        }
        if (substr($source, $i, 2) === "<?") {
          $children[] = self::parseDelimited($source, $i, "<?", "?>", self::$ProcessingInstruction);
          continue;
        }
        if (strtoupper(substr($source, $i, 9)) === "<!DOCTYPE") {
          $children[] = self::parseDocType($source, $i);
          continue;
        }
        $children[] = self::parseElement($source, $i);
        continue;
      }
      $start = $i;
      while ($i < $len && $source[$i] !== "<") $i++;
      if ($i > $start) $children[] = self::createPCData(substr($source, $start, $i - $start));
    }
    if ($closing !== null) self::parseError("Unclosed node <" . $closing . ">");
    return $children;
  }
  private static function parseElement($source, &$i) {
    $len = strlen($source);
    if ($i >= $len || $source[$i] !== "<") self::parseError();
    $i++;
    $name = self::readName($source, $i);
    $attrs = [];
    while ($i < $len) {
      self::skipWhitespace($source, $i);
      if (substr($source, $i, 2) === "/>" ) {
        $i += 2;
        return new Xml(self::$Element, $name, null, $attrs, [], true);
      }
      if ($source[$i] === ">") {
        $i++;
        $children = self::parseNodes($source, $i, $name);
        if (count($children) === 0) $children[] = self::createPCData("");
        return new Xml(self::$Element, $name, null, $attrs, $children, false);
      }
      $attrName = self::readName($source, $i);
      self::skipWhitespace($source, $i);
      if ($i >= $len || $source[$i] !== "=") self::parseError();
      $i++;
      self::skipWhitespace($source, $i);
      if ($i >= $len || ($source[$i] !== "\"" && $source[$i] !== "'")) self::parseError();
      $quote = $source[$i++];
      $start = $i;
      while ($i < $len && $source[$i] !== $quote) $i++;
      if ($i >= $len) self::parseError();
      $attrs[$attrName] = html_entity_decode(substr($source, $start, $i - $start), ENT_QUOTES | ENT_XML1);
      $i++;
    }
    self::parseError();
  }
  private static function parseDelimited($source, &$i, $open, $close, $type) {
    $i += strlen($open);
    $end = strpos($source, $close, $i);
    if ($end === false) self::parseError();
    $value = substr($source, $i, $end - $i);
    $i = $end + strlen($close);
    return new Xml($type, null, $value, [], []);
  }
  private static function parseDocType($source, &$i) {
    $i += 9;
    $end = strpos($source, ">", $i);
    if ($end === false) self::parseError();
    $value = trim(substr($source, $i, $end - $i));
    $i = $end + 1;
    return self::createDocType($value);
  }
  private static function readName($source, &$i) {
    $len = strlen($source);
    $start = $i;
    while ($i < $len && preg_match('/[A-Za-z0-9_:\\.-]/', $source[$i]) === 1) $i++;
    if ($i === $start) self::parseError();
    return substr($source, $start, $i - $start);
  }
  private static function skipWhitespace($source, &$i) {
    $len = strlen($source);
    while ($i < $len && preg_match('/\\s/', $source[$i]) === 1) $i++;
  }
  private static function parseError($message = "Xml parse error") { throw new \Exception($message); }
  public function __get($field) {
    if ($field === "nodeType") return $this->type;
    if ($field === "nodeName") {
      if ($this->type !== self::$Element) throw new \Exception("Bad node type");
      return $this->name;
    }
    if ($field === "nodeValue") {
      if (!$this->isValueNode()) throw new \Exception("Bad node type");
      return $this->value;
    }
    return null;
  }
  public function __set($field, $value) {
    if ($field === "nodeName") {
      if ($this->type !== self::$Element) throw new \Exception("Bad node type");
      $this->name = strval($value);
      return;
    }
    if ($field === "nodeValue") {
      if (!$this->isValueNode()) throw new \Exception("Bad node type");
      $this->value = strval($value);
      return;
    }
    $this->$field = $value;
  }
  private function isValueNode() {
    return $this->type === self::$PCData || $this->type === self::$CData || $this->type === self::$Comment || $this->type === self::$DocType || $this->type === self::$ProcessingInstruction;
  }
  public function firstChild() { $this->requireParent(); return count($this->children) > 0 ? $this->children[0] : null; }
  public function firstElement() {
    $this->requireParent();
    foreach ($this->children as $child) if ($child instanceof Xml && $child->type === self::$Element) return $child;
    return null;
  }
  private function requireElement() {
    if ($this->type !== self::$Element) throw new \Exception("Bad node type");
  }
  private function requireParent() {
    if ($this->type !== self::$Element && $this->type !== self::$Document) throw new \Exception("Bad node type");
  }
  public function attributes() { $this->requireElement(); return array_keys($this->attrMap); }
  public function get($name) { $this->requireElement(); return array_key_exists(strval($name), $this->attrMap) ? $this->attrMap[strval($name)] : null; }
  public function exists($name) { $this->requireElement(); return array_key_exists(strval($name), $this->attrMap); }
  public function set($name, $value) { $this->requireElement(); $this->attrMap[strval($name)] = strval($value); }
  public function remove($name) {
    $this->requireElement();
    $key = strval($name);
    $exists = array_key_exists($key, $this->attrMap);
    unset($this->attrMap[$key]);
    return $exists;
  }
  private function appendOwnedChild($child) {
    if ($child instanceof Xml) $child->parent = $this;
    $this->children[] = $child;
  }
  private function setChildren($children) {
    $this->children = [];
    foreach ($children as $child) $this->appendOwnedChild($child);
  }
  public function addChild($child) {
    $this->requireParent();
    if ($child instanceof Xml && $child->parent !== null) $child->parent->removeChild($child);
    $this->appendOwnedChild($child);
    return null;
  }
  public function removeChild($child) {
    $this->requireParent();
    $index = array_search($child, $this->children, true);
    if ($index === false) return false;
    array_splice($this->children, $index, 1);
    if ($child instanceof Xml) $child->parent = null;
    return true;
  }
  public function insertChild($child, $pos) {
    $this->requireParent();
    if ($child instanceof Xml && $child->parent !== null) $child->parent->removeChild($child);
    if ($child instanceof Xml) $child->parent = $this;
    array_splice($this->children, max(0, intval($pos)), 0, [$child]);
    return null;
  }
  public function iterator() { $this->requireParent(); return new __HxArrayIterator($this->children); }
  public function getIterator(): \Traversable { return $this->iterator(); }
  public function elements() {
    $this->requireParent();
    $result = [];
    foreach ($this->children as $child) if ($child instanceof Xml && $child->type === self::$Element) $result[] = $child;
    return new __HxArrayIterator($result);
  }
  public function elementsNamed($name) {
    $this->requireParent();
    $result = [];
    foreach ($this->children as $child) if ($child instanceof Xml && $child->type === self::$Element && $child->name === strval($name)) $result[] = $child;
    return new __HxArrayIterator($result);
  }
  public function toString() {
    if ($this->type === self::$Document) {
      $out = "";
      foreach ($this->children as $child) $out .= $child->toString();
      return $out;
    }
    if ($this->type === self::$Element) {
      $attrs = "";
      foreach ($this->attrMap as $key => $value) $attrs .= " " . $key . "=\"" . self::escapeAttr($value) . "\"";
      if (count($this->children) === 0 && $this->selfClosing) return "<" . $this->name . $attrs . "/>";
      $body = "";
      foreach ($this->children as $child) $body .= $child->toString();
      return "<" . $this->name . $attrs . ">" . $body . "</" . $this->name . ">";
    }
    if ($this->type === self::$CData) return "<![CDATA[" . $this->value . "]]>";
    if ($this->type === self::$Comment) return "<!--" . $this->value . "-->";
    if ($this->type === self::$DocType) return "<!DOCTYPE " . $this->value . ">";
    if ($this->type === self::$ProcessingInstruction) return "<?" . $this->value . "?>";
    return strval($this->value);
  }
  public function __toString() { return $this->toString(); }
  private static function escapeAttr($value) {
    return str_replace(["&", "\"", "'", "<", ">"], ["&amp;", "&quot;", "&#039;", "&lt;", "&gt;"], strval($value));
  }
}
