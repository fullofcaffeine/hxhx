class TypeReflectionMain {
	static function main() {
		// Keep a hard guardrail for `Type.*` until we implement the minimal `Type` API.
		// (bd: haxe.ocaml-eli)
		final name = Type.getClassName(Type.getClass("x"));
		Sys.println(name);
	}
}
