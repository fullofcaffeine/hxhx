import haxe.io.Bytes;
import haxe.io.BytesData;

/**
	Negative target fixture for the internal Bytes constructor.

	Haxe 4.3.7 gives the explicit length argument observable behavior. Until the
	OCaml Bytes carrier can preserve both length and data, compilation must stop
	instead of silently lowering the constructor to `HxBytes.ofData`.
**/
@:access(haxe.io.Bytes)
class BytesConstructorUnadmittedMain {
	static function main():Void {
		final data:BytesData = Bytes.alloc(3).getData();
		final value = new Bytes(1, data);
		Sys.println(value.length);
	}
}
