import backend.BackendContext;
import backend.js.JsBackend;

/** Declaration lookup follows generic aliases without weakening value-type arity checks. */
class M14GenericAliasProviderTest {
	static function check(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function run(command:String, args:Array<String>):{code:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(command, args);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}

	static function main():Void {
		final root = ".tmp/generic_alias_provider";
		sys.FileSystem.createDirectory(root);
		for (file in [
			{name: "Box", source: 'class Box<T>{public static function answer():Int {return 7;}}'},
			{name: "Alias", source: 'typedef Alias<T> = Box<T>;'},
			{name: "Chain", source: 'typedef Chain<T> = Alias<T>;'},
			{name: "Record", source: 'typedef Record<T> = {value:T};'},
			{
				name: "Main",
				source: '@:native("console") extern class Console {public static function log(value:String):Void;} class Main {static function main():Void {Console.log(""+Chain.answer());}}'
			}
		])
			sys.io.File.saveContent(root + "/" + file.name + ".hx", file.source);
		final upstream = run("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
		check(upstream.code == 0, upstream.stderr);
		check(run("node", [root + "/upstream.js"]).stdout == "7\n", "upstream alias result differs");
		final roots = ResolverStage.parseProjectRootsShallow([root], ["Main"]);
		final index = TyperIndex.buildHeaders(roots);
		final loader = new ModuleLoader([root], new haxe.ds.StringMap<String>(), index, null, false);
		loader.markResolvedAlready(roots);
		final owner = loader.ensureTypeAvailable("Chain", "", []);
		check(owner != null && owner.getIdentity().getCanonicalName() == "Box", "generic alias chain lost its provider");
		check(loader.ensureTypeAvailable("Record", "", []) == null, "structural alias manufactured a nominal provider");
		final context:TyTypeDeclaration.TyTypeResolutionContext = {
			packagePath: "",
			modulePath: "Main",
			directives: [],
			filePath: root + "/Main.hx",
			position: HxPos.unknown(),
			parameters: []
		};
		var rejected = false;
		try {
			index.resolveTypeUse(TyType.unresolved("Alias", []), context);
		} catch (error:TyperError) {
			rejected = error.message.indexOf("Not enough type parameters") >= 0;
		}
		check(rejected, "provider lookup weakened value type argument requirements");
		check(index.resolveTypeUse(TyType.unresolved("Chain", [TyType.fromHintText("Int")]), context)
			.getType()
			.getSemanticKey() == "nominal:Box<primitive:Int>",
			"value alias substitution changed");
		final pending = roots.concat(loader.drainNewModules());
		final typed = new Array<TypedModule>();
		var cursor = 0;
		while (cursor < pending.length) {
			typed.push(TyperStage.typeResolvedModule(pending[cursor++], index, loader, true));
			for (module in loader.drainNewModules())
				pending.push(module);
		}
		new JsBackend().emit(new MacroExpandedProgram(typed, false),
			new BackendContext(root, root + "/native.js", "Main", true, false, HxDefineMap.fromRawDefines(["js=1"])));
		final native = run("node", [root + "/native.js"]);
		check(native.code == 0 && native.stdout == "7\n", "native static alias call differs: " + native.stderr);
		sys.io.File.saveContent(root + "/Main.hx", 'class Main {static function main():Void {var missing:Alias=null;}}');
		check(run("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--interp"]).code != 0, "upstream accepted missing alias arguments");
		Sys.println("GENERIC_ALIAS_PROVIDER:PASS");
	}
}
