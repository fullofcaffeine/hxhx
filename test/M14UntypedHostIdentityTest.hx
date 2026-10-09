/** Compare direct host occurrences with stored callable identity without requiring a host runtime. */
class M14UntypedHostIdentityTest {
	public static function main():Void {
		for (entry in [
			{name: "direct", body: 'untyped {foreign(1);foreign("text");}', reject: false},
			{name: "expression", body: 'untyped {var value=foreignValue;foreign(value.left+value.right);}', reject: false},
			{name: "stored", body: 'untyped {var fn=foreign;fn(1);fn("text");}', reject: true}
		]) {
			final source = 'class Main{public static function main():Void{' + entry.body + '}}';
			final root = '.tmp/untyped_host_identity_' + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + '/Main.hx';
			sys.io.File.saveContent(path, source);
			final process = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '-main', 'Main', '-js', root + '/upstream.js']);
			final error = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if ((code != 0) != entry.reject || (entry.reject && error.indexOf('String should be Int') < 0))
				throw 'upstream mismatch ' + entry.name + error;
			var rejected = false;
			try {
				final module = new ResolvedModule('Main', path, ParserStage.parse(source, path));
				TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			} catch (error:TyperError) {
				if (!entry.reject)
					throw error;
				rejected = error.message.indexOf('conflicts with its inferred type') >= 0;
			}
			if (rejected != entry.reject)
				throw 'local mismatch ' + entry.name;
			Sys.println('HOST_IDENTITY:PASS ' + entry.name);
		}
	}
}
