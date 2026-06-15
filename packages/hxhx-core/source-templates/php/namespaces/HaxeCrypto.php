namespace haxe\crypto {
  class Md5 {
    public static function encode($value) {
      return md5(strval($value));
    }
    public static function make($bytes) {
      return \haxe\io\Bytes::ofHex(md5($bytes->toString()));
    }
  }
  class Sha1 {
    public static function encode($value) {
      return sha1(strval($value));
    }
    public static function make($bytes) {
      return \haxe\io\Bytes::ofHex(sha1($bytes->toString()));
    }
  }
  class BaseCode {
    private $base;
    private $nbits;
    private $tbl = null;
    public function __construct($base) {
      $len = $base->length;
      $nbits = 1;
      while ($len > (1 << $nbits)) $nbits++;
      if ($nbits > 8 || $len !== (1 << $nbits)) throw new \Exception("BaseCode : base length must be a power of two.");
      $this->base = $base;
      $this->nbits = $nbits;
    }
    public function encodeBytes($bytes) {
      $nbits = $this->nbits;
      $base = $this->base;
      $size = intdiv($bytes->length * 8, $nbits);
      $out = \haxe\io\Bytes::alloc($size + ((($bytes->length * 8) % $nbits) === 0 ? 0 : 1));
      $buf = 0; $curbits = 0; $mask = (1 << $nbits) - 1; $pin = 0; $pout = 0;
      while ($pout < $size) {
        while ($curbits < $nbits) {
          $curbits += 8;
          $buf <<= 8;
          $buf |= $bytes->get($pin++);
        }
        $curbits -= $nbits;
        $out->set($pout++, $base->get(($buf >> $curbits) & $mask));
      }
      if ($curbits > 0) $out->set($pout++, $base->get(($buf << ($nbits - $curbits)) & $mask));
      return $out;
    }
    private function initTable() {
      $tbl = array_fill(0, 256, -1);
      for ($i = 0; $i < $this->base->length; $i++) $tbl[$this->base->get($i)] = $i;
      $this->tbl = $tbl;
    }
    public function decodeBytes($bytes) {
      $nbits = $this->nbits;
      if ($this->tbl === null) $this->initTable();
      $tbl = $this->tbl;
      $size = intdiv($bytes->length * $nbits, 8);
      $out = \haxe\io\Bytes::alloc($size);
      $buf = 0; $curbits = 0; $pin = 0; $pout = 0;
      while ($pout < $size) {
        while ($curbits < 8) {
          $curbits += $nbits;
          $buf <<= $nbits;
          $idx = $tbl[$bytes->get($pin++)] ?? -1;
          if ($idx === -1) throw new \Exception("BaseCode : invalid encoded char");
          $buf |= $idx;
        }
        $curbits -= 8;
        $out->set($pout++, ($buf >> $curbits) & 0xFF);
      }
      return $out;
    }
    public function encodeString($value) {
      return $this->encodeBytes(\haxe\io\Bytes::ofString(strval($value)))->toString();
    }
    public function decodeString($value) {
      return $this->decodeBytes(\haxe\io\Bytes::ofString(strval($value)))->toString();
    }
    public static function encode($value, $base) {
      $codec = new BaseCode(\haxe\io\Bytes::ofString(strval($base)));
      return $codec->encodeString(strval($value));
    }
    public static function decode($value, $base) {
      $codec = new BaseCode(\haxe\io\Bytes::ofString(strval($base)));
      return $codec->decodeString(strval($value));
    }
  }
  class Base64 {
    public static function encode($bytes, $complement = true) {
      $out = base64_encode($bytes->toString());
      return $complement ? $out : rtrim($out, "=");
    }
    public static function decode($value, $complement = true) {
      $text = strval($value);
      if (!$complement) {
        $pad = strlen($text) % 4;
        if ($pad > 0) $text .= str_repeat("=", 4 - $pad);
      }
      $decoded = base64_decode($text, true);
      if ($decoded === false) throw new \Exception("Base64 decode failed");
      return \haxe\io\Bytes::ofString($decoded);
    }
  }
}
