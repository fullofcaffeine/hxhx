class TypeReflectionMain {
	static function main() {
		// Smoke test: minimal `Type.*` reflection API should compile.
		final fields = Type.getClassFields(TypeReflectionMain);
		Sys.println(fields.length);
	}
}
