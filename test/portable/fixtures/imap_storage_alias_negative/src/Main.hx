import haxe.Constraints.IMap;

/**
	Proves that ordinary `Map` values keep the public `IMap` adapter.

	Each function creates an `IMap` local from a standard `Map`, then uses that
	local outside the target standard library's closed native-storage pattern.
	The compiler must build the checked interface record in every case.
**/
class Main {
	static function returned():IMap<String, Int> {
		final source:Map<String, Int> = [];
		source.set("returned", 1);
		final candidate:IMap<String, Int> = source;
		return candidate;
	}

	static function captured():Bool {
		final source:Map<String, Int> = [];
		source.set("captured", 1);
		final candidate:IMap<String, Int> = source;
		final read = function():Bool {
			return candidate.exists("captured");
		};
		return read();
	}

	static function assigned():Null<Int> {
		final first:Map<String, Int> = [];
		first.set("assigned", 1);
		var candidate:IMap<String, Int> = first;
		final beforeAssignment = candidate.exists("assigned");
		final second:Map<String, Int> = [];
		second.set("assigned", 2);
		candidate = second;
		return beforeAssignment ? candidate.get("assigned") : null;
	}

	static function compared():Bool {
		final source:Map<String, Int> = [];
		source.set("compared", 1);
		final candidate:IMap<String, Int> = source;
		return candidate != null && candidate.exists("compared");
	}

	static function consume(candidate:IMap<String, Int>):Bool {
		return candidate.exists("passed");
	}

	static function passed():Bool {
		final source:Map<String, Int> = [];
		source.set("passed", 1);
		final candidate:IMap<String, Int> = source;
		return consume(candidate);
	}

	static function main():Void {
		Sys.println("returned=" + returned().get("returned"));
		Sys.println("captured=" + captured());
		Sys.println("assigned=" + assigned());
		Sys.println("compared=" + compared());
		Sys.println("passed=" + passed());
	}
}
