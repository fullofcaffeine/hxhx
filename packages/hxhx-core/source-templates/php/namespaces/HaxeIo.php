namespace haxe\io {
  class BytesData {
    public $bytes;
    public function __construct($bytes) {
      $this->bytes = array_values($bytes);
    }
  }
  class Bytes {
    public $length;
    private $data;
    public function __construct($data) {
      $this->data = $data instanceof BytesData ? $data : new BytesData($data);
      $this->length = count($this->data->bytes);
    }
    public static function alloc($length) {
      return new Bytes(new BytesData(array_fill(0, max(0, intval($length)), 0)));
    }
    public static function ofString($value) {
      $items = strlen($value) === 0 ? [] : array_values(unpack("C*", strval($value)));
      return new Bytes(new BytesData($items));
    }
    public static function ofData($data) {
      return new Bytes($data);
    }
    public static function ofHex($hex) {
      $bytes = [];
      $text = strval($hex);
      for ($i = 0; $i + 1 < strlen($text); $i += 2) $bytes[] = hexdec(substr($text, $i, 2));
      return new Bytes(new BytesData($bytes));
    }
    public static function fastGet($data, $pos) {
      $items = $data instanceof BytesData ? $data->bytes : $data;
      return $items[intval($pos)] ?? 0;
    }
    public function getData() {
      return $this->data;
    }
    public function get($pos) {
      return $this->data->bytes[intval($pos)] ?? 0;
    }
    public function set($pos, $value) {
      $index = intval($pos);
      if ($index < 0 || $index >= $this->length) return null;
      $this->data->bytes[$index] = intval($value) & 255;
      return null;
    }
    public function blit($pos, $src, $srcpos, $len) {
      $pos = intval($pos); $srcpos = intval($srcpos); $len = intval($len);
      if ($pos < 0 || $srcpos < 0 || $len < 0 || $pos + $len > $this->length || $srcpos + $len > $src->length) throw new \Exception("Bytes.blit out of bounds");
      $slice = array_slice($src->data->bytes, $srcpos, $len);
      for ($i = 0; $i < $len; $i++) $this->data->bytes[$pos + $i] = $slice[$i];
      return null;
    }
    public function getString($pos, $len) {
      $pos = intval($pos); $len = intval($len);
      if ($pos < 0 || $len < 0 || $pos + $len > $this->length) throw new \Exception("Bytes.getString out of bounds");
      $out = "";
      foreach (array_slice($this->data->bytes, $pos, $len) as $byte) $out .= chr(intval($byte) & 255);
      return $out;
    }
    public function toString() {
      return $this->getString(0, $this->length);
    }
    public function __toString() {
      return $this->toString();
    }
    public function compare($other) {
      $cmp = strcmp($this->toString(), $other->toString());
      return $cmp < 0 ? -1 : ($cmp > 0 ? 1 : 0);
    }
    public function sub($pos, $len) {
      $pos = intval($pos); $len = intval($len);
      if ($pos < 0 || $len < 0 || $pos + $len > $this->length) throw new \Exception("Bytes.sub out of bounds");
      return new Bytes(new BytesData(array_slice($this->data->bytes, $pos, $len)));
    }
    public function toHex() {
      $out = "";
      foreach ($this->data->bytes as $byte) $out .= sprintf("%02x", intval($byte) & 255);
      return $out;
    }
  }
  class BytesInput {
    private $bytes;
    private $positionValue = 0;
    public $length;
    public $bigEndian = false;
    public function __construct($bytes) {
      $this->bytes = $bytes;
      $this->length = $bytes->length;
    }
    public function __get($name) {
      if ($name === "position") return $this->get_position();
      return null;
    }
    public function __set($name, $value) {
      if ($name === "position") $this->set_position($value);
    }
    public function get_position() {
      return $this->positionValue;
    }
    public function set_position($value) {
      $this->positionValue = max(0, min($this->length, intval($value)));
      return $this->positionValue;
    }
    private function fail($name) {
      throw \ValueException::thrown(__hxhx_io_error($name));
    }
    private function ensure($len) {
      if ($this->positionValue + $len > $this->length) $this->fail("OutsideBounds");
    }
    public function read($len) {
      $len = intval($len);
      $this->ensure($len);
      $out = $this->bytes->sub($this->positionValue, $len);
      $this->positionValue += $len;
      return $out;
    }
    public function readBytes($buf, $pos, $len) {
      $pos = intval($pos); $len = intval($len);
      if ($pos < 0 || $len < 0 || $pos + $len > $buf->length) $this->fail("OutsideBounds");
      $available = $this->length - $this->positionValue;
      if ($available <= 0) $this->fail("OutsideBounds");
      $count = min($len, $available);
      $buf->blit($pos, $this->bytes, $this->positionValue, $count);
      $this->positionValue += $count;
      return $count;
    }
    public function readByte() {
      $this->ensure(1);
      return $this->bytes->get($this->positionValue++);
    }
    private function readUnsigned($count) {
      $value = 0;
      if ($this->bigEndian) {
        for ($i = 0; $i < $count; $i++) $value = ($value * 256) + $this->readByte();
      } else {
        $shift = 1;
        for ($i = 0; $i < $count; $i++) { $value += $this->readByte() * $shift; $shift *= 256; }
      }
      return $value;
    }
    private function signed($value, $bits) {
      $limit = 1 << ($bits - 1);
      $mod = 1 << $bits;
      return $value >= $limit ? $value - $mod : $value;
    }
    public function readInt8() { return $this->signed($this->readUnsigned(1), 8); }
    public function readInt16() { return $this->signed($this->readUnsigned(2), 16); }
    public function readUInt16() { return $this->readUnsigned(2); }
    public function readInt24() { return $this->signed($this->readUnsigned(3), 24); }
    public function readUInt24() { return $this->readUnsigned(3); }
    public function readInt32() {
      $value = $this->readUnsigned(4);
      return $value >= 0x80000000 ? $value - 0x100000000 : $value;
    }
    public function readFloat() {
      $raw = $this->read(4)->toString();
      $data = unpack($this->bigEndian ? "G" : "g", $raw);
      return $data[1];
    }
    public function readDouble() {
      $raw = $this->read(8)->toString();
      $data = unpack($this->bigEndian ? "E" : "e", $raw);
      return $data[1];
    }
    public function readString($len) {
      return $this->read($len)->toString();
    }
    public function readAll() {
      return $this->read($this->length - $this->positionValue);
    }
  }
  class BytesOutput {
    private $items = [];
    public $length = 0;
    public $bigEndian = false;
    public function prepare($nbytes) { return null; }
    private function fail($name) {
      throw \ValueException::thrown(__hxhx_io_error($name));
    }
    public function writeByte($c) {
      $this->items[] = intval($c) & 255;
      $this->length = count($this->items);
      return null;
    }
    public function write($bytes) {
      $this->writeBytes($bytes, 0, $bytes->length);
      return null;
    }
    public function writeBytes($bytes, $pos, $len) {
      $pos = intval($pos); $len = intval($len);
      if ($pos < 0 || $len < 0 || $pos + $len > $bytes->length) $this->fail("OutsideBounds");
      for ($i = 0; $i < $len; $i++) $this->writeByte($bytes->get($pos + $i));
      return $len;
    }
    private function checkSigned($value, $bits) {
      $min = -(1 << ($bits - 1)); $max = (1 << ($bits - 1)) - 1;
      if ($value < $min || $value > $max) $this->fail("Overflow");
    }
    private function checkUnsigned($value, $bits) {
      $max = (1 << $bits) - 1;
      if ($value < 0 || $value > $max) $this->fail("Overflow");
    }
    private function writeUnsigned($value, $count) {
      $value = intval($value);
      if ($this->bigEndian) {
        for ($i = $count - 1; $i >= 0; $i--) $this->writeByte(intdiv($value, 1 << ($i * 8)));
      } else {
        for ($i = 0; $i < $count; $i++) $this->writeByte(intdiv($value, 1 << ($i * 8)));
      }
    }
    public function writeInt8($x) { $this->checkSigned($x, 8); $this->writeByte($x); }
    public function writeUInt8($x) { $this->checkUnsigned($x, 8); $this->writeByte($x); }
    public function writeInt16($x) { $this->checkSigned($x, 16); $this->writeUnsigned($x & 0xFFFF, 2); }
    public function writeUInt16($x) { $this->checkUnsigned($x, 16); $this->writeUnsigned($x, 2); }
    public function writeInt24($x) { $this->checkSigned($x, 24); $this->writeUnsigned($x & 0xFFFFFF, 3); }
    public function writeUInt24($x) { $this->checkUnsigned($x, 24); $this->writeUnsigned($x, 3); }
    public function writeInt32($x) { $this->writeUnsigned($x & 0xFFFFFFFF, 4); }
    public function writeFloat($x) {
      foreach (array_values(unpack("C*", pack($this->bigEndian ? "G" : "g", floatval($x)))) as $byte) $this->writeByte($byte);
    }
    public function writeDouble($x) {
      foreach (array_values(unpack("C*", pack($this->bigEndian ? "E" : "e", floatval($x)))) as $byte) $this->writeByte($byte);
    }
    public function writeString($s) { $this->write(Bytes::ofString(strval($s))); }
    public function getBytes() { return new Bytes(new BytesData($this->items)); }
  }
}
