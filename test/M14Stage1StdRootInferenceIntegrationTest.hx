import haxe.io.Path;
import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage1Compiler.Stage1Resolver;
import sys.FileSystem;
import sys.io.File;

/** SDK selection follows each request's explicit configuration and directories without retaining another request's choice. */
class M14Stage1StdRootInferenceIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function hasValue(values:Array<String>, expected:String):Bool {
		if (values == null)
			return false;
		for (value in values)
			if (value == expected)
				return true;
		return false;
	}

	static function envOrEmpty(name:String):String {
		final value = Sys.getEnv(name);
		return value == null ? "" : value;
	}

	static function restoreEnv(name:String, original:String):Void {
		Sys.putEnv(name, original);
	}

	static function rmrf(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (name in FileSystem.readDirectory(path))
				rmrf(Path.join([path, name]));
			FileSystem.deleteDirectory(path);
			return;
		}
		FileSystem.deleteFile(path);
	}

	static function readRepoVersion():String {
		final content = File.getContent(".haxerc");
		final versionPattern = ~/"version"\s*:\s*"([^"]+)"/;
		if (!versionPattern.match(content))
			throw "expected .haxerc to define version";
		return StringTools.trim(versionPattern.matched(1));
	}

	static function resolveExpectedStdRoot(home:String, version:String):String {
		if (home.length == 0)
			return "";
		final direct = Path.normalize(Path.join([home, "haxe", "versions", version, "std"]));
		if (FileSystem.exists(direct) && FileSystem.isDirectory(direct))
			return direct;
		final hidden = Path.normalize(Path.join([home, ".haxe", "versions", version, "std"]));
		if (FileSystem.exists(hidden) && FileSystem.isDirectory(hidden))
			return hidden;
		return "";
	}

	/** Use independent SDK directories outside the checkout so repository ancestors cannot make an absent SDK appear configured. */
	static function checkExternalCwdSelection():Void {
		final originalCwd = Sys.getCwd();
		final originalHome = envOrEmpty("HOME");
		final originalStd = envOrEmpty("HAXE_STD_PATH");
		final originalHaxePath = envOrEmpty("HAXEPATH");
		var tempParent = envOrEmpty("TMPDIR");
		if (tempParent.length == 0)
			tempParent = envOrEmpty("TEMP");
		if (tempParent.length == 0)
			tempParent = "/tmp";
		final root = Path.normalize(FileSystem.absolutePath(tempParent) + "/hxhx_sdk_cwd_" + Date.now().getTime());
		final home = root + "/home";
		final startup = root + "/startup";
		final otherStartup = root + "/other_startup";
		final target = root + "/target";
		final external = root + "/unconfigured";
		final firstSdk = home + "/haxe/versions/0.0.101/std";
		final secondSdk = home + "/haxe/versions/0.0.102/std";
		final explicitSdk = root + "/explicit/std";
		final environmentSdk = root + "/environment/std";
		var failure = "";
		try {
			for (directory in [
				startup,
				otherStartup,
				target,
				external,
				firstSdk,
				secondSdk,
				explicitSdk,
				environmentSdk
			])
				FileSystem.createDirectory(directory);
			File.saveContent(startup + "/.haxerc", '{"version":"0.0.101"}');
			File.saveContent(otherStartup + "/.haxerc", '{"version":"0.0.102"}');
			File.saveContent(target + "/.haxerc", '{"version":"0.0.102"}');
			Sys.putEnv("HOME", home);
			Sys.putEnv("HAXE_STD_PATH", "");
			Sys.putEnv("HAXEPATH", "");
			Sys.setCwd(startup);
			assertTrue(@:privateAccess Stage1Args.inferStdRootFromHaxerc(external) == "",
				"directory ancestry must stop at the filesystem root instead of reading startup configuration");
			function selected(args:Array<String>):String {
				final parsed = Stage1Args.parse(args, true);
				assertTrue(parsed != null, "SDK selection arguments must parse");
				return Path.normalize(Stage1Args.getStandardLibraryRoot(parsed));
			}
			assertTrue(selected(["--cwd", external]) == firstSdk, "external cwd must retain the startup SDK");
			assertTrue(selected(["--cwd", target]) == secondSdk, "target directory configuration must precede the startup SDK");
			Sys.putEnv("HAXE_STD_PATH", environmentSdk);
			assertTrue(selected(["--cwd", target]) == environmentSdk, "explicit SDK environment must precede directory configuration");
			assertTrue(selected(["--cwd", target, "--std", explicitSdk]) == explicitSdk, "--std must precede SDK environment configuration");
			Sys.putEnv("HAXE_STD_PATH", "");
			Sys.putEnv("HAXEPATH", root + "/environment");
			assertTrue(selected(["--cwd", target]) == environmentSdk, "HAXEPATH must precede directory configuration");
			Sys.putEnv("HAXEPATH", "");
			Sys.setCwd(external);
			assertTrue(selected(["--cwd", external]) == "", "an unconfigured request must not reuse the previous SDK");
			Sys.setCwd(otherStartup);
			assertTrue(selected(["--cwd", external]) == secondSdk, "each request must discover its own startup SDK");
		} catch (error:haxe.Exception) {
			failure = error.message;
		}
		Sys.setCwd(originalCwd);
		restoreEnv("HOME", originalHome);
		restoreEnv("HAXE_STD_PATH", originalStd);
		restoreEnv("HAXEPATH", originalHaxePath);
		rmrf(root);
		assertTrue(failure.length == 0, failure);
	}

	static function main():Void {
		checkExternalCwdSelection();
		final originalHome = envOrEmpty("HOME");
		final originalStdPath = envOrEmpty("HAXE_STD_PATH");
		final originalHaxePath = envOrEmpty("HAXEPATH");

		final tmpRoot = Path.normalize("tmp_m14_stage1_std_root_inference_" + Std.string(Std.int(Date.now().getTime())));
		final version = readRepoVersion();
		final expectedStd = resolveExpectedStdRoot(originalHome, version);
		final projectDir = Path.join([tmpRoot, "project"]);
		final projectSrcDir = Path.join([projectDir, "src"]);

		var failureMessage = "";
		try {
			FileSystem.createDirectory(projectDir);
			FileSystem.createDirectory(projectSrcDir);
			File.saveContent(Path.join([projectDir, ".haxerc"]), '{\n  "version": "' + version + '"\n}\n');
			File.saveContent(Path.join([projectSrcDir, "Main.hx"]),
				"import haxe.io.Path;\nclass Main {\n\tstatic function main():Void {\n\t\tPath.directory(\"a/b\");\n\t}\n}\n");

			assertTrue(expectedStd.length > 0, "expected Lix std root at ~/haxe/versions/<version>/std or ~/.haxe/versions/<version>/std");
			Sys.putEnv("HOME", originalHome);
			Sys.putEnv("HAXE_STD_PATH", "");
			Sys.putEnv("HAXEPATH", "");

			final parsed = Stage1Args.parse(["--cwd", projectDir, "-cp", "src", "-main", "Main"], true);
			assertTrue(parsed != null, "expected Stage1Args.parse to succeed");
			final classPaths = Stage1Args.getClassPaths(parsed);

			final nativeLibParsed = Stage1Args.parse([
				"--cwd",
				projectDir,
				"-cp",
				"src",
				"-main",
				"Main",
				"--java-lib",
				"native.jar",
				"--net-lib",
				"native.dll"
			], true);
			assertTrue(nativeLibParsed != null, "expected native-library args to parse in permissive Stage1 mode");
			final nativeLibDefines = Stage1Args.getDefines(nativeLibParsed);
			assertTrue(hasValue(nativeLibDefines, "hxhx_java_lib=1"), "expected --java-lib to seed native Java library define");
			assertTrue(hasValue(nativeLibDefines, "hxhx_net_lib=1"), "expected --net-lib to seed native .NET library define");

			final shortDceParsed = Stage1Args.parse(["--cwd", projectDir, "-cp", "src", "-main", "Main", "-dce", "no", "-D", "Mac"], true);
			assertTrue(shortDceParsed != null, "expected short -dce args to parse in permissive Stage1 mode");
			final shortDceDefines = Stage1Args.getDefines(shortDceParsed);
			assertTrue(hasValue(shortDceDefines, "dce=no"), "expected short -dce to seed dce define");
			assertTrue(Stage1Args.getRoots(shortDceParsed).length == 0, "short -dce value should not be treated as a positional root");

			final noHaxercDir = Path.join([tmpRoot, "no_haxerc"]);
			FileSystem.createDirectory(noHaxercDir);
			Sys.putEnv("HAXE_STD_PATH", "");
			Sys.putEnv("HAXEPATH", "");
			final noHaxercParsed = Stage1Args.parse(["--cwd", noHaxercDir, "--run", "Main", "arg1", "--js", "out.js"], true);
			assertTrue(noHaxercParsed != null, "expected relative no-.haxerc cwd parse to terminate");
			assertTrue(Stage1Args.getMain(noHaxercParsed) == "Main", "expected --run to set the main module");
			assertTrue(Stage1Args.getRoots(noHaxercParsed).length == 0, "runtime args after --run should not become roots");
			assertTrue(Stage1Args.getHadRun(noHaxercParsed), "expected --run to be recorded for target runners");
			assertTrue(Stage1Args.getRunArgs(noHaxercParsed).join(",") == "arg1", "expected runtime args after --run to be preserved");

			var found = false;
			for (cp in classPaths) {
				if (Path.normalize(cp) == expectedStd) {
					found = true;
					break;
				}
			}
			assertTrue(found, "expected classpaths to include std root inferred from .haxerc: " + expectedStd);

			final resolverClassPaths = new Array<String>();
			for (cp in classPaths) {
				if (Path.isAbsolute(cp))
					resolverClassPaths.push(Path.normalize(cp));
				else
					resolverClassPaths.push(Path.normalize(Path.join([projectDir, cp])));
			}
			final resolvedStd = Stage1Resolver.resolveModule(resolverClassPaths, "haxe.io.Path", projectDir);
			assertTrue(resolvedStd != null, "expected Stage1 resolver to resolve std module haxe.io.Path with inferred classpath");
		} catch (error:haxe.Exception) {
			failureMessage = error.message;
		}

		restoreEnv("HOME", originalHome);
		restoreEnv("HAXE_STD_PATH", originalStdPath);
		restoreEnv("HAXEPATH", originalHaxePath);
		rmrf(tmpRoot);

		if (failureMessage.length > 0)
			throw failureMessage;
	}
}
