import sys.FileSystem;

/**
	Finds the standard library of the pinned Haxe 4.3.7 compiler for tests that
	parse a real upstream std module such as `DateTools.hx`.

	CI installs Haxe through Lix, so the library is at
	`~/haxe/versions/<version>/std`. A developer can select another complete
	installation with `HAXE_STD_PATH`. An untracked `vendor/haxe` checkout is
	the last fallback, because the Core Tests shards do not fetch one.
**/
class M14Stage0StdPath {
	public static function locate(version:String = "4.3.7"):String {
		final configured = Sys.getEnv("HAXE_STD_PATH");
		if (configured != null && configured != "" && FileSystem.isDirectory(configured))
			return configured;

		final home = Sys.getEnv("HOME");
		if (home != null && home != "") {
			final lixManaged = haxe.io.Path.join([home, "haxe", "versions", version, "std"]);
			if (FileSystem.isDirectory(lixManaged))
				return lixManaged;
		}

		final localOracle = haxe.io.Path.normalize("vendor/haxe/std");
		if (FileSystem.isDirectory(localOracle))
			return localOracle;

		throw 'Could not locate the Haxe $version standard library. Set HAXE_STD_PATH or install that version through Lix.';
	}
}
