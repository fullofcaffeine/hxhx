package reflaxe.ocaml.target;

/**
	Deterministic validation and encoding shared by target declaration facts.

	This stateless abstract gives native code generation a separate module for
	helper functions. Additional fact types can call it without depending on the
	declaration request's generated function order.
**/
abstract OcamlTargetDeclarationCodec(Bool) {
	public static function required(value:String, label:String):String {
		final normalized = value == null ? "" : StringTools.trim(value);
		if (normalized.length == 0)
			throw "OCaml target declaration request requires " + label;
		return normalized;
	}

	public static function flag(value:Bool):String
		return value ? "1" : "0";

	public static function addStrings(out:Array<Null<String>>, values:Array<String>):Void {
		out.push(Std.string(values.length));
		for (value in values)
			out.push(value);
	}

	public static function encode(values:Array<Null<String>>):String {
		final out = new StringBuf();
		for (value in values)
			if (value == null) {
				out.add("n;");
			} else {
				out.add("s");
				out.add(value.length);
				out.add(":");
				out.add(value);
				out.add(";");
			}
		return out.toString();
	}
}
