enum MyEnum {
	A;
	B(x:Int);
}

class Main {
	/** Prints one comparable line on both the stock JavaScript oracle and system targets. */
	static function printLine(value:String):Void {
		#if js
		js.Syntax.code("console.log({0})", value);
		#else
		Sys.println(value);
		#end
	}

	static function main() {
		final firstConstant:Dynamic = MyEnum.A;
		final secondConstant:Dynamic = MyEnum.A;
		final firstPayload:Dynamic = MyEnum.B(7);
		final secondPayload:Dynamic = MyEnum.B(7);
		printLine("enum_constant_same=" + (firstConstant == secondConstant));
		printLine("enum_payload_distinct=" + (firstPayload != secondPayload));

		try {
			throw firstConstant;
		} catch (e:MyEnum) {
			switch (e) {
				case A:
					printLine("catch_enum=A");
				case B(x):
					printLine("catch_enum=B:" + x);
			}
		} catch (_:Dynamic) {
			printLine("catch_enum=miss");
		}

		try {
			throw firstPayload;
		} catch (e:MyEnum) {
			switch (e) {
				case A:
					printLine("catch_payload=A");
				case B(x):
					printLine("catch_payload=B:" + x);
			}
		} catch (_:Dynamic) {
			printLine("catch_payload=miss");
		}

		final dBool:Dynamic = true;
		try {
			throw dBool;
		} catch (b:Bool) {
			printLine("catch_bool=" + b);
		} catch (_:Dynamic) {
			printLine("catch_bool=miss");
		}

		final dInt:Dynamic = 123;
		try {
			throw dInt;
		} catch (i:Int) {
			printLine("catch_int=" + i);
		} catch (_:Dynamic) {
			printLine("catch_int=miss");
		}

		final dFloat:Dynamic = 1.5;
		try {
			throw dFloat;
		} catch (f:Float) {
			printLine("catch_float=" + f);
		} catch (_:Dynamic) {
			printLine("catch_float=miss");
		}

		final dStr:Dynamic = "hi";
		try {
			throw dStr;
		} catch (s:String) {
			printLine("catch_string=" + s);
		} catch (_:Dynamic) {
			printLine("catch_string=miss");
		}
	}
}
