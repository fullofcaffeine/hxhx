class Counter {
	public var i:Int;

	public function new() {
		i = 0;
	}

	public function loopTo(n:Int):Int {
		while (true) {
			if (i == n) return i;
			i++;
		}
		return -1;
	}
}

class Main {
	static function main() {
		// Local ref lowering (`var x` mutated => `ref`).
		var x = 0;
		final localPost = x++;
		Sys.println("local_post=" + localPost);
		Sys.println("local_now=" + x);
		final localPre = ++x;
		Sys.println("local_pre=" + localPre);

		// Instance field lowering (record field).
		final c = new Counter();
		final fieldPost = c.i++;
		Sys.println("field_post=" + fieldPost);
		Sys.println("field_now=" + c.i);
		final fieldPre = ++c.i;
		Sys.println("field_pre=" + fieldPre);

		// Array element lowering.
		final a = [0];
		final arrayPost = a[0]++;
		Sys.println("array_post=" + arrayPost);
		Sys.println("array_now=" + a[0]);
		final arrayPre = ++a[0];
		Sys.println("array_pre=" + arrayPre);

		// Regression: would hang if `self.i++` does not update.
		Sys.println("loop_field=" + c.loopTo(3));

		Sys.println("OK inc_dec");
	}
}

