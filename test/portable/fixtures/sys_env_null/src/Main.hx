class Main {
	static function showEnv(name:String):String {
		final v = Sys.getEnv(name);
		return v == null ? "null" : v;
	}

	static function main() {
		Sys.println("getEnv(HX_TEST_ENV)=" + showEnv("HX_TEST_ENV"));
		Sys.println("getEnv(HX_TEST_ENV_MISSING_REFLAXE_OCAML)=" + showEnv("HX_TEST_ENV_MISSING_REFLAXE_OCAML"));

		final env = Sys.environment();
		Sys.println("environment(HX_TEST_ENV)=" + (env.exists("HX_TEST_ENV") ? env.get("HX_TEST_ENV") : "absent"));
		Sys.println("environment(HX_TEST_ENV_MISSING_REFLAXE_OCAML)=" + (env.exists("HX_TEST_ENV_MISSING_REFLAXE_OCAML") ? "present" : "absent"));
	}
}

