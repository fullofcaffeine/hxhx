/** Extern defaults and written modifiers must agree in parsing, extension selection, and execution. */
class M14ExternMemberVisibilityTest {
	static function main():Void {
		for (entry in [
			{
				name: "extern_default",
				owner: "extern class",
				access: "",
				accepted: true
			},
			{
				name: "extern_public",
				owner: "extern class",
				access: "public ",
				accepted: true
			},
			{
				name: "extern_private",
				owner: "extern class",
				access: "private ",
				accepted: false
			},
			{
				name: "class_default",
				owner: "class",
				access: "",
				accepted: false
			}
		]) {
			final root = ".tmp/extern-member-visibility-" + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			final source = 'using Main.Helper;'
				+ entry.owner
				+ ' Helper {'
				+ entry.access
				+ 'static var token:Int;'
				+ entry.access
				+ 'static inline function twice(value:Int):Int{return value*2;}}'
				+ 'class Main {static function take(value:Int):Void{if(value!=6)throw "extension result";}'
				+ 'static function main():Void{var value=3;take(value.twice());}}';
			sys.io.File.saveContent(path, source);
			final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
			final process = new sys.io.Process(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", root, "-main", "Main", "--interp"]);
			final output = process.stdout.readAll().toString();
			final errors = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if ((code == 0) != entry.accepted || (!entry.accepted && errors.indexOf("has no field twice") < 0))
				throw "upstream extern visibility differs: " + entry.name + output + errors;
			// Extern storage needs a host implementation to execute. Type-check its
			// visibility separately while the inline method supplies runtime evidence.
			final fieldSource = entry.owner
				+ ' FieldProvider {'
				+ entry.access
				+ 'static var token:Int;}'
				+ 'class FieldMain {static function main():Void{var value:Int=FieldProvider.token;}}';
			sys.io.File.saveContent(root + "/FieldMain.hx", fieldSource);
			final fieldCheck = new sys.io.Process(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", root, "-main", "FieldMain", "--no-output"]);
			final fieldOutput = fieldCheck.stdout.readAll().toString();
			final fieldErrors = fieldCheck.stderr.readAll().toString();
			final fieldCode = fieldCheck.exitCode();
			fieldCheck.close();
			if ((fieldCode == 0) != entry.accepted || (!entry.accepted && fieldErrors.indexOf("private field token") < 0))
				throw "upstream field visibility differs: " + entry.name + fieldOutput + fieldErrors;
			final parsed = ParserStage.parse(source, path);
			final expected = entry.accepted ? HxVisibility.Public : HxVisibility.Private;
			for (owner in HxModuleDecl.getClasses(parsed.getDecl()))
				if (HxClassDecl.getName(owner) == "Helper") {
					if (HxFieldDecl.getVisibility(HxClassDecl.getFields(owner)[0]) != expected
						|| HxFunctionDecl.getVisibility(HxClassDecl.getFunctions(owner)[0]) != expected)
						throw "extern field or method visibility differs";
				}
			var typed:Null<TypedModule> = null;
			try {
				final module = new ResolvedModule("Main", path, parsed);
				typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
				typed.getBackendProjection();
			} catch (error:haxe.Exception) {
				if (entry.accepted)
					throw error;
				typed = null;
			}
			if ((typed != null) != entry.accepted)
				throw "local extern visibility differs: " + entry.name;
			if (typed != null)
				JsRuntimeFixture.assertRuntime(typed, "Main", "");
			Sys.println("EXTERN_MEMBER_VISIBILITY:PASS " + entry.name);
		}
		checkInlineExecution();
		M14ExternInlineGenericTest.run();
	}

	/** Independent expected effects catch argument duplication, name capture, and returns escaping into the caller. */
	static function checkInlineExecution():Void {
		final source = 'using Main.Helper;
extern class Helper {
static inline function twice(value:Int):Int {return value*2;}
static inline function combine(left:Int,right:Int):Int {var local=left*10;return local+right;}
static inline function choose(value:Int):Int {if(value<0)return twice(-value);var local=value+1;return twice(local);}
static inline function ignore(value:Int):Int {return 7;}
static inline function repeat(value:Int):Int {return value+value;}
}
@:native("console") extern class Console {public static function log(value:String):Void;}
class Main {
static function print(value:Int):Void {Console.log(""+value);}
static var initialized=Helper.twice(4);
static var events="";
static function mark(name:String,value:Int):Int {events=events+name;return value;}
static function main():Void {
var local=100;
print(initialized);
print(mark("a",2).combine(mark("b",3)));
print(Helper.combine(mark("c",4),mark("d",5)));
print(Helper.ignore(mark("e",9)));
print(Helper.repeat(mark("f",6)));
print(Helper.choose(-3));
print(Helper.choose(3));
print(local);
Console.log(events);
Console.log("continued");
}}';
		final expected = "8\n23\n45\n7\n12\n6\n8\n100\nabcdef\ncontinued\n";
		final root = ".tmp/extern-inline-execution";
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		sys.io.File.saveContent(path, source);
		final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		final upstream = @:privateAccess M14JsPlainExternBindingTest.run(compiler == null ? "node_modules/.bin/haxe" : compiler,
			["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
		if (upstream.code != 0)
			throw "upstream extern inline compilation failed: " + upstream.stderr;
		final observed = @:privateAccess M14JsPlainExternBindingTest.run("node", [root + "/upstream.js"]);
		if (observed.code != 0 || observed.stdout != expected)
			throw "upstream extern inline execution differs: " + observed.stdout + observed.stderr;
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		Sys.println("EXTERN_INLINE_EXECUTION:PASS");
	}
}
