class Main {
	static var localeArgumentEvaluated = false;

	static function requestedLocale():String {
		localeArgumentEvaluated = true;
		return "C";
	}

	static function main():Void {
		final args = Sys.args();
		if (args.length == 2 && args[0] == "--sys-command-child")
			Sys.exit(args[1] == "spaced value" ? 7 : 19);

		Sys.print("args-array=");
		Sys.println(args != null && args.length >= 0);

		final environmentKey = "HXHX_SYS_DIRECT_RUNTIME_7D583F9A";
		Sys.putEnv(environmentKey, "present");
		Sys.println("set-env=" + (Sys.getEnv(environmentKey) == "present"));
		Sys.putEnv(environmentKey, null);
		final missing = Sys.getEnv(environmentKey);
		Sys.println("missing-env=" + (missing == null));

		final environment = Sys.environment();
		Sys.println("removed-env=" + !environment.exists(environmentKey));
		Sys.println("environment-map=" + (environment != null));

		Sys.sleep(0.0);
		Sys.println("sleep-returned=true");

		final cwd = Sys.getCwd();
		Sys.setCwd(cwd);
		Sys.println("cwd-roundtrip=" + (Sys.getCwd() == cwd));

		Sys.println("system-name=" + (Sys.systemName().length > 0));
		Sys.println("time-positive=" + (Sys.time() > 0.0));
		Sys.println("cpu-time-nonnegative=" + (Sys.cpuTime() >= 0.0));
		Sys.println("program-path=" + (Sys.programPath().length > 0));
		Sys.println("executable-alias=" + (Sys.executablePath().length > 0));
		Sys.println("command-shell=" + (Sys.command("exit 6") == 6));
		Sys.println("command-null=" + (Sys.command("exit 5", null) == 5));
		Sys.println("command-args=" + (Sys.command(Sys.programPath(), ["--sys-command-child", "spaced value"]) == 7));
		Sys.println("time-locale-unsupported=" + (!Sys.setTimeLocale(requestedLocale()) && localeArgumentEvaluated));

		final effectsMustStayGuarded = args.length < 0;
		if (effectsMustStayGuarded) {
			Sys.exit(23);
			Sys.getChar(false);
		}
		Sys.println("guarded-effects=" + !effectsMustStayGuarded);
	}
}
