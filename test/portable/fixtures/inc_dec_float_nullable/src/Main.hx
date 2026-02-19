class Box {
	public var f:Float;

	public function new() {
		f = 0.5;
	}
}

class Main {
	static function main() {
		// Local Float.
		var x:Float = 1.5;
		final floatPost = x++;
		Sys.println("float_post=" + floatPost);
		Sys.println("float_now=" + x);
		final floatPre = ++x;
		Sys.println("float_pre=" + floatPre);

		// Instance field Float.
		final b = new Box();
		final fieldPost = b.f++;
		Sys.println("field_post=" + fieldPost);
		Sys.println("field_now=" + b.f);
		final fieldPre = ++b.f;
		Sys.println("field_pre=" + fieldPre);

		// Nullable Int.
		var ni:Null<Int> = 0;
		final niPost = ni++;
		Sys.println("nullint_post=" + niPost);
		Sys.println("nullint_now=" + ni);
		final niPre = ++ni;
		Sys.println("nullint_pre=" + niPre);

		// Nullable Float.
		var nf:Null<Float> = 1.0;
		final nfPost = nf++;
		Sys.println("nullfloat_post=" + nfPost);
		Sys.println("nullfloat_now=" + nf);
		final nfPre = ++nf;
		Sys.println("nullfloat_pre=" + nfPre);

		// Array element Float.
		final a = [0.5];
		final arrayPost = a[0]++;
		Sys.println("array_post=" + arrayPost);
		Sys.println("array_now=" + a[0]);
		final arrayPre = ++a[0];
		Sys.println("array_pre=" + arrayPre);

		// Array element Null<Int>.
		final na:Array<Null<Int>> = [0];
		final nullArrayPost = na[0]++;
		Sys.println("nullarray_post=" + nullArrayPost);
		Sys.println("nullarray_now=" + na[0]);
		final nullArrayPre = ++na[0];
		Sys.println("nullarray_pre=" + nullArrayPre);

		Sys.println("OK inc_dec_float_nullable");
	}
}
