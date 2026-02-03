class TypeReflectionMain {
	static function main() {
		// Keep a hard guardrail for `Type.*` until we implement the minimal `Type` API.
		// (bd: haxe.ocaml-eli)
		final fields = Type.getClassFields(TypeReflectionMain);
		Sys.println(fields.length);
	}
}
