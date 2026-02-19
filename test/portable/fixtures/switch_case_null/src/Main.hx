class Main {
	static function main() {
		var ni:Null<Int> = null;
		final kindInt = switch (ni) {
			case null, 1: "null_or_one";
			default: "other";
		}
		Sys.println("int=" + kindInt);

		final kindInt2 = switch (ni) {
			case 1: "one";
			case null: "null";
			default: "other";
		}
		Sys.println("int2=" + kindInt2);

		var nb:Null<Bool> = null;
		final kindBool = switch (nb) {
			case null: "null";
			case true: "true";
			case false: "false";
		}
		Sys.println("bool=" + kindBool);
		nb = true;
		Sys.println("bool2=" + switch (nb) {
			case null: "null";
			case true: "true";
			case false: "false";
		});

		var nf:Null<Float> = null;
		final kindFloat = switch (nf) {
			case null: "null";
			case 1.5: "onehalf";
			default: "other";
		}
		Sys.println("float=" + kindFloat);
		nf = 1.5;
		Sys.println("float2=" + switch (nf) {
			case null: "null";
			case 1.5: "onehalf";
			default: "other";
		});

		Sys.println("OK switch_case_null");
	}
}
