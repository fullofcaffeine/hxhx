import haxe.io.Path;
import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage1Compiler.Stage1Resolver;
import sys.FileSystem;
import sys.io.File;

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

	static function main():Void {
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
