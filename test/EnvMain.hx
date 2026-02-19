class EnvMain {
	static function main() {
		final name = "REFLAXE_OCAML_TEST_ENV";

		// Ensure missing returns null.
		Sys.putEnv(name, null);
		if (Sys.getEnv(name) != null)
			throw "missing_not_null";

		// Set and read back.
		Sys.putEnv(name, "abc");
		if (Sys.getEnv(name) != "abc")
			throw "set_get";

		// environment() includes it.
		final env = Sys.environment();
		if (!env.exists(name))
			throw "env_missing";
		if (env.get(name) != "abc")
			throw "env_value";

		// Empty string is a real value.
		Sys.putEnv(name, "");
		if (Sys.getEnv(name) != "")
			throw "empty_value";

		// Removing hides it from Haxe view.
		Sys.putEnv(name, null);
		if (Sys.getEnv(name) != null)
			throw "removed_not_null";
		final env2 = Sys.environment();
		if (env2.exists(name))
			throw "removed_in_env";
	}
}
