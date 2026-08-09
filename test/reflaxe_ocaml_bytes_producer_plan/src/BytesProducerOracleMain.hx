package;

import haxe.io.Bytes;
import haxe.io.BytesData;

/**
	Records the constructor behavior expected from upstream Haxe 4.3.7.

	Both arguments change a shared log. The expected result proves that Haxe
	evaluates the length first and the backing data second, exactly once each.
	The OCaml target must preserve this behavior even though OCaml itself does not
	promise the same function-argument order.
**/
@:access(haxe.io.Bytes)
class BytesProducerOracleMain {
	static final evaluationOrder:Array<String> = [];

	static function orderedInt(label:String, value:Int):Int {
		evaluationOrder.push(label);
		return value;
	}

	static function orderedData(label:String, value:BytesData):BytesData {
		evaluationOrder.push(label);
		return value;
	}

	public static function main():Void {
		final data = Bytes.ofString("abc").getData();
		final value = new Bytes(orderedInt("length", 1), orderedData("data", data));
		if (value.length != 1 || value.toString() != "a" || evaluationOrder.join(",") != "length,data")
			throw "Bytes constructor evaluation order changed";
		Sys.println("REFLAXE_OCAML_BYTES_PRODUCER_ORACLE:PASS");
	}
}
