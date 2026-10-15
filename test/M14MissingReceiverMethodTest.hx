import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Missing methods fail during shared typing, while declared and unchecked calls retain their contracts. */
class M14MissingReceiverMethodTest {
	static function main():Void {
		for (entry in [
			{
				name: "string_return",
				header: "",
				parameter: "value:String",
				body: "return value.absent();",
				accepted: false
			},
			{
				name: "string_discard",
				header: "",
				parameter: "value:String",
				body: "value.absent(); return 1;",
				accepted: false
			},
			{
				name: "computed",
				header: "",
				parameter: "value:String",
				body: "return (value + value).absent();",
				accepted: false
			},
			{
				name: "class",
				header: "class Item {}",
				parameter: "value:Item",
				body: "return value.absent();",
				accepted: false
			},
			{
				name: "record",
				header: "",
				parameter: "value:{present:Int}",
				body: "return value.absent();",
				accepted: false
			},
			{
				name: "dynamic",
				header: "",
				parameter: "value:Dynamic",
				body: "return value.absent();",
				accepted: true
			},
			{
				name: "untyped",
				header: "",
				parameter: "value:String",
				body: "return untyped value.absent();",
				accepted: true
			},
			{
				name: "string_method",
				header: "",
				parameter: "value:String",
				body: "return value.indexOf('x');",
				accepted: true
			},
			{
				name: "method",
				header: "class Item {public function present():Int return 7;}",
				parameter: "value:Item",
				body: "return value.present();",
				accepted: true
			},
			{
				name: "callback_field",
				header: "class Item {public var present:Void->Int;}",
				parameter: "value:Item",
				body: "return value.present();",
				accepted: true
			},
			{
				name: "record_callback",
				header: "",
				parameter: "value:{present:Void->Int}",
				body: "return value.present();",
				accepted: true
			},
			{
				name: "inferred",
				header: "",
				parameter: "value",
				body: "return value.present();",
				accepted: true
			},
			{
				name: "extension",
				header: "using Main.Extensions; class Item {} class Extensions {public static function present(value:Item):Int return 7;}",
				parameter: "value:Item",
				body: "return value.present();",
				accepted: true
			},
			{
				name: "dynamic_members",
				header: "extern class Item implements Dynamic<Dynamic> {}",
				parameter: "value:Item",
				body: "return value.absent();",
				accepted: true
			},
			{
				name: "inherited_method",
				header: "class Base {public function present():Int return 7;} class Item extends Base {}",
				parameter: "value:Item",
				body: "return value.present();",
				accepted: true
			},
			{
				name: "interface_method",
				header: "interface Base {function present():Int;} interface Item extends Base {}",
				parameter: "value:Item",
				body: "return value.present();",
				accepted: true
			},
			{
				name: "interface_missing",
				header: "interface Base {function present():Int;} interface Item extends Base {}",
				parameter: "value:Item",
				body: "return value.absent();",
				accepted: false
			},
			{
				name: "enum_match",
				header: "enum Item {Present;}",
				parameter: "value:Item",
				body: "return value.match(Item.Present) ? 1 : 0;",
				accepted: true
			}
		]) {
			final root = ".tmp/missing_receiver_method_" + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			final source = entry.header + "\nclass Main {\nstatic function inspect(" + entry.parameter + "):Int {\n" + entry.body
				+ "\n}\nstatic function main():Void {}\n}";
			sys.io.File.saveContent(path, source);
			final upstream = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--interp"]);
			final stdout = upstream.stdout.readAll().toString();
			final stderr = upstream.stderr.readAll().toString();
			final code = upstream.exitCode();
			upstream.close();
			if ((code == 0) != entry.accepted || (!entry.accepted && stderr.indexOf("has no field absent") < 0))
				throw "upstream method contract differs for " + entry.name + ": " + stdout + stderr;
			var rejected:Null<TyperError> = null;
			try {
				typeSource(root, "Main").getBackendProjection();
			} catch (error:TyperError) {
				rejected = error;
			}
			if (entry.accepted ? rejected != null : rejected == null)
				throw "candidate method contract differs for " + entry.name + ": " + Std.string(rejected);
			if (rejected != null
				&& (rejected.toString().indexOf("has no field absent") < 0 || rejected.toString().indexOf(path + ":4:") < 0))
				throw "missing-method diagnostic lost its field or source line: " + rejected.toString();
			Sys.println("MISSING_RECEIVER_METHOD:PASS " + entry.name);
		}
		checkPrimitiveShadow();
		checkPrimitiveFieldShadow();
		checkRuntime();
	}

	/** A field read loads the core provider even when a local String advertises a conflicting field type. */
	static function checkPrimitiveFieldShadow():Void {
		final root = ".tmp/primitive_field_shadow";
		sys.FileSystem.createDirectory(root + "/demo");
		final source = 'package demo; class String {public var length:Bool;} '
			+ 'class Main {static function inspect():Int return "xy".length; static function main() {Sys.println(inspect());}}';
		sys.io.File.saveContent(root + "/demo/Main.hx", source);
		final upstream = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "--run", "demo.Main"]);
		final stdout = upstream.stdout.readAll().toString();
		final stderr = upstream.stderr.readAll().toString();
		final code = upstream.exitCode();
		upstream.close();
		if (code != 0 || stdout != "2\n" || stderr != "")
			throw "upstream primitive field shadow contract differs: " + stdout + stderr;
		var selected = 0;
		for (owner in typeSource(root, "demo.Main").getBackendProjection().getClasses())
			for (fn in owner.getFunctions())
				TypedBackendSourceWalk.functionDeclaration(fn.getDeclaration(), expression -> {
					final field = fn.findField(expression);
					if (field != null && field.getField().getName() == "length") {
						selected++;
						if (field.getField().getOwner().getCanonicalName() != "String"
							|| field.getType().getSemanticKey() != "primitive:Int")
							throw "primitive field read lost its core declaration or Int result";
					}
				}, _ -> {});
		if (selected != 1)
			throw "primitive field ownership observer did not run";
		Sys.println("PRIMITIVE_FIELD_SHADOW:PASS");
	}

	/** Use real providers and declaration dependencies for both ordinary and package-qualified inputs. */
	static function typeSource(root:String, mainModule:String):TypedModule {
		final args = Stage1Args.parse(["-cp", root, "-main", mainModule], true);
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [root],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(args),
			targetDefine: "js"
		});
		final defines = Stage3SetupSupport.buildDefinesMap([], "js", "js-native");
		final resolved = ResolverStage.parseProjectRoots(paths, [mainModule], defines);
		final roots = resolved.filter(value -> ResolvedModule.getModulePath(value) == mainModule);
		if (roots.length != 1)
			throw "receiver fixture requires one exact main module";
		final index = TyperIndex.buildHeaders(resolved);
		final loader = new ModuleLoader(paths, defines, index);
		loader.markResolvedAlready(resolved);
		return TyperStage.typeResolvedModule(roots[0], index, loader, true);
	}

	/** A same-named source class cannot add methods to literals or replace a real primitive signature. */
	static function checkPrimitiveShadow():Void {
		for (accepted in [false, true]) {
			final root = ".tmp/primitive_receiver_shadow_" + accepted;
			sys.FileSystem.createDirectory(root + "/demo");
			final source = 'package demo; class String {public function absent():Int return 7; public function indexOf(value:Int):Bool return true;}'
				+ 'class Main {static function inspect():Int return '
				+ (accepted ? '"x".indexOf("x")' : '"x".absent()')
				+ '; static function main():Void {}}';
			sys.io.File.saveContent(root + "/demo/Main.hx", source);
			final upstream = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "demo.Main", "--interp"]);
			final stdout = upstream.stdout.readAll().toString();
			final stderr = upstream.stderr.readAll().toString();
			final code = upstream.exitCode();
			upstream.close();
			if ((code == 0) != accepted || (!accepted && stderr.indexOf("String has no field absent") < 0))
				throw "upstream primitive shadow contract differs: " + stdout + stderr;
			var failure:Null<TyperError> = null;
			try
				typeSource(root, "demo.Main").getBackendProjection()
			catch (error:TyperError)
				failure = error;
			if (accepted ? failure != null : failure == null || failure.getMessage().indexOf("String has no field absent") < 0)
				throw "a local String changed primitive member lookup: " + Std.string(failure);
			Sys.println("PRIMITIVE_RECEIVER_SHADOW:PASS accepted=" + accepted);
		}
	}

	/** Declared methods and callback fields still execute through the ordinary JavaScript backend. */
	static function checkRuntime():Void {
		final source = 'class Item {
public var action:Void->Int;
public function new() {action = function():Int return 7;}
public function present():Int return 9;
}
class Main {
static function read(value:{action:Void->Int}):Int return value.action();
static function main():Void {
var item = new Item();
var record = {action: function():Int return 11};
Sys.println(item.present());
Sys.println(item.action());
Sys.println(record.action());
Sys.println(read(record));
}
}';
		final expected = "9\n7\n11\n11\n";
		final root = ".tmp/missing_receiver_method_runtime";
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		sys.io.File.saveContent(path, source);
		final upstream = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"]);
		final stdout = upstream.stdout.readAll().toString();
		final stderr = upstream.stderr.readAll().toString();
		final code = upstream.exitCode();
		upstream.close();
		if (code != 0 || stdout != expected)
			throw "upstream receiver runtime differs: " + stdout + stderr;
		final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		Sys.println("MISSING_RECEIVER_METHOD_RUNTIME:PASS");
	}
}
