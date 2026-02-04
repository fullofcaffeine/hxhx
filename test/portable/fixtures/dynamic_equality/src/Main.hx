typedef Point = { x:Int };

enum E {
	A;
	B(x:Int);
}

class Main {
	static function main() {
		final dInt:Dynamic = 1;
		final dFloat:Dynamic = 1.0;
		Sys.println("dyn_int_float=" + (dInt == dFloat));

		final dBool:Dynamic = true;
		Sys.println("dyn_int_bool=" + (dInt == dBool));

		final dStr:Dynamic = "x";
		Sys.println("dyn_string=" + (dStr == "x"));

		final ns:Null<String> = null;
		final dNullStr:Dynamic = ns;
		Sys.println("dyn_null_string_is_null=" + (dNullStr == null));

		final eConst1:Dynamic = E.A;
		final eConst2:Dynamic = E.A;
		Sys.println("dyn_enum_const=" + (eConst1 == eConst2));

		final eArg1:Dynamic = E.B(1);
		final eArg2:Dynamic = E.B(1);
		Sys.println("dyn_enum_args=" + (eArg1 == eArg2));

		final p1:Point = { x: 1 };
		final p2:Point = { x: 1 };
		Sys.println("typed_anon=" + (p1 == p2));
		final p3 = p1;
		Sys.println("typed_anon_same=" + (p1 == p3));

		final f = (x:Int) -> x + 1;
		final g = (x:Int) -> x + 1;
		Sys.println("typed_fn=" + (f == g));
		Sys.println("typed_fn_same=" + (f == f));
	}
}
