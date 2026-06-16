import sys.FileSystem;
import sys.io.File;

class M14ResolverImplicitCwdClassPathIntegrationTest {
	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(haxe.io.Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	static function main():Void {
		final tmpRoot = haxe.io.Path.normalize('.tmp/m14_resolver_implicit_cwd_' + Std.string(Date.now().getTime()));
		final explicitSrc = haxe.io.Path.join([tmpRoot, 'src']);
		final casesDir = haxe.io.Path.join([explicitSrc, 'cases']);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		FileSystem.createDirectory(explicitSrc);
		FileSystem.createDirectory(casesDir);
		File.saveContent(haxe.io.Path.join([tmpRoot, 'RootMain.hx']), ['class RootMain {', '  static function main() {}', '}'].join("\n"));
		File.saveContent(haxe.io.Path.join([explicitSrc, 'Main.hx']), [
			'class Main {',
			'  static function main() {',
			'    var runner = new Runner();',
			'    runner.addCases("cases");',
			'  }',
			'}'
		].join("\n"));
		File.saveContent(haxe.io.Path.join([casesDir, 'TestOne.hx']), ['package cases;', 'class TestOne {}'].join("\n"));
		File.saveContent(haxe.io.Path.join([casesDir, 'TestTwo.hx']), ['package cases;', 'class TestTwo {}'].join("\n"));
		File.saveContent(haxe.io.Path.join([casesDir, 'Helper.hx']), ['package cases;', 'class Helper {}'].join("\n"));

		try {
			var missingWithoutCwd = false;
			try {
				ResolverStage.parseProjectRoots([explicitSrc], ['RootMain'], null);
			} catch (raw:String) {
				missingWithoutCwd = raw.indexOf('import_missing RootMain') >= 0;
			}
			assertTrue(missingWithoutCwd, 'Expected explicit classpath alone to miss the root-level module.');

			final classPaths = ResolverStage.withImplicitCwdClassPath([explicitSrc], tmpRoot);
			assertTrue(classPaths.length == 2, 'Expected cwd compatibility classpath to append cwd once.');
			assertTrue(haxe.io.Path.normalize(classPaths[1]) == haxe.io.Path.normalize(tmpRoot),
				'Expected cwd compatibility classpath to append the project cwd after explicit classpaths.');
			final resolved = ResolverStage.parseProjectRoots(classPaths, ['RootMain'], null);
			assertTrue(resolved.length == 1, 'Expected resolver to find root-level module via implicit cwd classpath.');

			final duplicate = ResolverStage.withImplicitCwdClassPath([explicitSrc, tmpRoot], tmpRoot);
			assertTrue(duplicate.length == 2, 'Expected implicit cwd classpath to avoid duplicate cwd entries.');

			final addCasesResolved = ResolverStage.parseProjectRoots([explicitSrc], ['Main'], null);
			final addCasesModules = new Map<String, Bool>();
			for (m in addCasesResolved)
				addCasesModules.set(ResolvedModule.getModulePath(m), true);
			assertTrue(addCasesModules.exists('Main'), 'Expected root Main module to resolve.');
			assertTrue(addCasesModules.exists('cases.TestOne'), 'Expected utest addCases("cases") to include TestOne.');
			assertTrue(addCasesModules.exists('cases.TestTwo'), 'Expected utest addCases("cases") to include TestTwo.');
			assertTrue(!addCasesModules.exists('cases.Helper'), 'Expected utest addCases("cases") to ignore non-Test helper modules.');
		} catch (e:Dynamic) {
			Sys.println('debug_out=' + tmpRoot);
			throw e;
		}

		deleteRecursive(tmpRoot);
	}
}
