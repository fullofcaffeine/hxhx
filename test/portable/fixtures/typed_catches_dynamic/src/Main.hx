enum MyEnum {
	A;
	B(x:Int);
}

class Main {
	static function main() {
		final dEnum:Dynamic = MyEnum.A;
		try {
			throw dEnum;
		} catch (e:MyEnum) {
			switch (e) {
				case A:
					Sys.println("catch_enum=A");
				case B(x):
					Sys.println("catch_enum=B:" + x);
			}
		} catch (_:Dynamic) {
			Sys.println("catch_enum=miss");
		}

		final dBool:Dynamic = true;
		try {
			throw dBool;
		} catch (b:Bool) {
			Sys.println("catch_bool=" + b);
		} catch (_:Dynamic) {
			Sys.println("catch_bool=miss");
		}

		final dInt:Dynamic = 123;
		try {
			throw dInt;
		} catch (i:Int) {
			Sys.println("catch_int=" + i);
		} catch (_:Dynamic) {
			Sys.println("catch_int=miss");
		}

		final dFloat:Dynamic = 1.5;
		try {
			throw dFloat;
		} catch (f:Float) {
			Sys.println("catch_float=" + f);
		} catch (_:Dynamic) {
			Sys.println("catch_float=miss");
		}

		final dStr:Dynamic = "hi";
		try {
			throw dStr;
		} catch (s:String) {
			Sys.println("catch_string=" + s);
		} catch (_:Dynamic) {
			Sys.println("catch_string=miss");
		}
	}
}
