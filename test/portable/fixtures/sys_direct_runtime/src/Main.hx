class Main {
	static function main():Void {
		final args = Sys.args();
		Sys.println("args-array=" + (args != null && args.length >= 0));

		final missing = Sys.getEnv("HXHX_SYS_DIRECT_RUNTIME_MISSING_7D583F9A");
		Sys.println("missing-env=" + (missing == null));

		final environment = Sys.environment();
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

		final effectsMustStayGuarded = args.length < 0;
		if (effectsMustStayGuarded) {
			Sys.exit(23);
			Sys.getChar(false);
		}
		Sys.println("guarded-effects=" + !effectsMustStayGuarded);
	}
}
