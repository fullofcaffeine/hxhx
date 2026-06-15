namespace haxe\rtti {
  class Meta {
    public static function getType($cls) { return \__hxhx_meta_type($cls); }
    public static function getStatics($cls) { return \__hxhx_meta_statics($cls); }
    public static function getFields($cls) { return \__hxhx_meta_fields($cls); }
  }
}
