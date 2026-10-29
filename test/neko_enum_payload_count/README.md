# Enum payload length

The component observer checks the generated guard for `Pair(4, Nested(7))`.
It constructs native VM vectors and real upstream Haxe Array objects separately.
Both complete values must match. Missing outer or nested arguments and a
different constructor name must return false without reading absent arguments.
The short Haxe arrays retain spare backing slots, so their logical length must
win over the backing vector's capacity.

Run `haxe test/m14_neko_enum_payload_count_test.hxml`. The original macro-array
command runs this check too, then compares the full production runtime and
provider with upstream Neko in split and single output layouts.
