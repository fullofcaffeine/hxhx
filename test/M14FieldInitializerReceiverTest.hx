/** Field initializers cannot read their future receiver, including through captured or implicit member access. */
class M14FieldInitializerReceiverTest {
	static function main():Void {
		for (entry in [
			{name: "this", expression: "this.first", accepted: false},
			{name: "bare", expression: "first", accepted: false},
			{name: "method", expression: "read()", accepted: false},
			{name: "capture_this", expression: "(function(){return this.first;})()", accepted: false},
			{name: "static", expression: "shared", accepted: true},
			{name: "shadow", expression: "{var first=7;first;}", accepted: true},
			{name: "capture_local", expression: "{var first=7;(function(){return first;})();}", accepted: true},
			{name: "other_receiver", expression: "new Other().first", accepted: true}
		]) {
			final root = ".tmp/field-initializer-receiver-" + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			final source = 'class Other{public var first:Int=7;public function new(){}}class Main{static var shared:Int=7;var first:Int=7;var result:Int='
				+ entry.expression
				+ ';function read():Int{return first;}public function new(){}static function main():Void{new Main();}}';
			sys.io.File.saveContent(path, source);
			final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
			final child = new sys.io.Process(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", root, "-main", "Main", "--interp"]);
			final stdout = child.stdout.readAll().toString();
			final stderr = child.stderr.readAll().toString();
			final code = child.exitCode();
			child.close();
			if ((code == 0) != entry.accepted || (!entry.accepted && stderr.indexOf("variable initialization") < 0))
				throw "upstream initializer receiver contract differs: " + entry.name + stdout + stderr;
			var diagnostic = "";
			try {
				final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
				TyperStage.typeResolvedModule(module, TyperIndex.build([module])).getBackendProjection();
			} catch (error:haxe.Exception) {
				diagnostic = error.message;
			}
			if (entry.accepted ? diagnostic.length > 0 : diagnostic.indexOf("variable initialization") < 0)
				throw "local initializer receiver contract differs: " + entry.name + " " + diagnostic;
			Sys.println("FIELD_INITIALIZER_RECEIVER:PASS " + entry.name);
		}
	}
}
