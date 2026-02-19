class Main {
	static function main() {
		var ni:Null<Int> = null;
		Sys.println("ni_eq_0=" + (ni == 0));
		Sys.println("0_eq_ni=" + (0 == ni));
		Sys.println("ni_eq_null=" + (ni == null));
		Sys.println("std_string_null_int=" + Std.string(ni));
		ni = 1;
		Sys.println("std_string_val_int=" + Std.string(ni));

		var nf:Null<Float> = null;
		var f:Float = 0.0;
		Sys.println("float_eq_null=" + (f == nf));
		Sys.println("null_eq_float=" + (nf == f));
		Sys.println("std_string_null_float=" + Std.string(nf));
		nf = 1.5;
		Sys.println("std_string_val_float=" + Std.string(nf));

		var nb:Null<Bool> = null;
		Sys.println("bool_eq_null=" + (false == nb));
		Sys.println("std_string_null_bool=" + Std.string(nb));
		nb = true;
		Sys.println("std_string_val_bool=" + Std.string(nb));

		var s = "foo";
		Sys.println("charCodeAt7=" + Std.string(s.charCodeAt(7)));
		Sys.println("charCodeAt0=" + Std.string(s.charCodeAt(0)));

		Sys.println("OK null_primitives");
	}
}
