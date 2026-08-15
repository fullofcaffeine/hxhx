/**
	Exercises one source `throw` that nullable-switch lowering places at two output sites.

	The null guard and the non-null default branch must both raise the same Haxe
	value. Final runtime-use reconciliation must give those sites distinct hidden
	identities without changing their caller-visible behavior.
**/
class ThrowOutputCopyMain {
	static function classify(value:Null<Int>):Int {
		return switch (value) {
			case 43: 1;
			case _:
				throw "unexpected";
		}
	}

	static function caught(value:Null<Int>):String {
		try {
			classify(value);
			return "missing";
		} catch (error:String) {
			return error;
		}
	}

	static function main():Void {
		Sys.println(classify(43));
		Sys.println("null=" + caught(null));
		Sys.println("other=" + caught(99));
	}
}
