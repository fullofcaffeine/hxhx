typedef Point = {x:Float, y:Float};
typedef Optional = {?o:Float, v:Float};
typedef NullableFloats = {n:Null<Float>};

class Holder {
	public var f:Float = 0.5;
	public var nf:Null<Float> = null;

	public function new() {}
}

class Main {
	static function count():Int {
		return 3;
	}

	static function nothing():Null<Int> {
		return null;
	}

	static function returned(n:Null<Int>):Float {
		return n;
	}

	static function half(value:Float):Float {
		return value / 2;
	}

	static function main():Void {
		final n:Null<Int> = count();
		final m:Null<Float> = 1.25;

		// Null<Int> and Null<Float> values entering Float destinations.
		final h = new Holder();
		h.f = n;
		Sys.println("field " + (h.f + 0.25));
		h.f = m;
		Sys.println("nullable float field " + (h.f + 0.5));
		final list:Array<Float> = [];
		list.push(n);
		list.push(m);
		Sys.println("push " + (list[0] + 0.25) + " " + (list[1] + 0.5));
		list[0] = n;
		Sys.println("index write " + (list[0] + 0.5));
		Sys.println("return " + (returned(n) + 0.25));
		Sys.println("argument " + half(n));
		var local:Float = 0.5;
		local = n;
		Sys.println("local " + (local + 0.5));

		// Int values in anonymous-structure Float fields.
		final p:Point = {x: 1, y: count()};
		Sys.println("literal " + (p.x + p.y + 0.5));
		p.x = count();
		Sys.println("write " + (p.x + p.y + 0.5));
		final q:Point = {x: n, y: 0.25};
		q.y = n;
		Sys.println("nullable literal " + (q.x + q.y + 0.5));

		// Null<Float> destinations and optional Float fields keep null as null,
		// and store a present Int as a Float.
		final z:Null<Int> = nothing();
		final optional:Optional = {o: z, v: 1.5};
		Sys.println("optional literal " + (optional.o == null));
		optional.o = z;
		Sys.println("optional write " + (optional.o == null));
		optional.o = n;
		Sys.println("optional present " + (optional.o + 0.25));
		final nullables:Array<Null<Float>> = [n, z];
		Sys.println("nullable array " + (nullables[0] + 0.25) + " " + (nullables[1] == null));
		nullables.push(n);
		nullables[1] = n;
		Sys.println("nullable array write " + (nullables[1] + 0.5) + " " + (nullables[2] + 0.5));
		h.nf = n;
		Sys.println("nullable field " + (h.nf + 0.25));
		h.nf = z;
		Sys.println("nullable field null " + (h.nf == null));
		h.nf = 4;
		Sys.println("nullable field int " + (h.nf + 0.5));
		final nullableFields:NullableFloats = {n: n};
		Sys.println("nullable anon " + (nullableFields.n + 0.25));
		nullableFields.n = z;
		Sys.println("nullable anon null " + (nullableFields.n == null));
		var nullableLocal:Null<Float> = n;
		Sys.println("nullable local " + (nullableLocal + 0.25));

		// Int literals stored in Float slots, then read as Float.
		final floats:Array<Float> = [1, 2];
		floats[0] = floats[0] + 1.5;
		Sys.println("int literal element " + floats[0] + " " + (floats[1] + 0.5));
		final box = new Holder();
		box.f = 3;
		Sys.println("int literal field " + (box.f + 0.5));
	}
}
