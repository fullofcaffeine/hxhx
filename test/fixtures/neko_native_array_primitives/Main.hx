import neko.NativeArray;

/** Exercise the fixed-size backing storage used by the standard Neko Array provider. */
class Main {
	static var effects = 0;

	static function storage(label:String, value:NativeArray<Int>):NativeArray<Int> {
		Sys.println(label);
		effects++;
		return value;
	}

	static function offset(label:String, value:Int):Int {
		Sys.println(label);
		effects++;
		return value;
	}

	// A declared Haxe method with a reserved-looking name remains an ordinary call.
	static function __dollar__amake(size:Int):Int {
		return size + 100;
	}

	static function main():Void {
		final values:NativeArray<Int> = NativeArray.alloc(4);
		Sys.println(NativeArray.length(values));
		values[0] = 1;
		values[1] = 2;
		values[2] = 3;
		values[3] = 4;
		NativeArray.blit(values, 1, values, 0, 3);
		Sys.println(values[0]);
		Sys.println(values[1]);
		Sys.println(values[2]);
		Sys.println(values[3]);
		final copied = NativeArray.sub(values, 1, 2);
		values[1] = 8;
		Sys.println(copied[0]);
		Sys.println(copied[1]);
		Sys.println(NativeArray.length(copied));
		Sys.println(values[1]);
		NativeArray.blit(values, 0, values, 1, 3);
		Sys.println(values[0]);
		Sys.println(values[1]);
		Sys.println(values[2]);
		Sys.println(values[3]);
		NativeArray.blit(storage("destination", values), offset("destination-offset", 1), storage("source", copied), offset("source-offset", 0),
			offset("length", 2));
		Sys.println(values[0]);
		Sys.println(values[1]);
		Sys.println(values[2]);
		Sys.println(values[3]);
		Sys.println(effects);
		Sys.println(NativeArray.length(NativeArray.alloc(0)));
		Sys.println(__dollar__amake(3));
	}
}
