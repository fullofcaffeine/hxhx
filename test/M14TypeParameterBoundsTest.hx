import hxhx.Stage1Compiler.Stage1Args;
import sys.io.File;

/**
	Compare members read through type parameter bounds, abstract headers with braces before the
	body, and a field assignment that binds a generic instance's type argument with upstream
	Haxe 4.3.7, then run the native output (haxe_ocaml-f0r0c; haxe.ds.HashMap).

	- The abstract scanner took the first `{` after the name as the body, so
	  `abstract HashMap<K:{function hashCode():Int;}, V>(...)` and `abstract Point({x:Int, y:Int})`
	  lost their members.
	- Constraint text lost the space in `function hashCode`.
	- `t.code()` with `T:Base`, a typedef bound or a structure bound gave Dynamic.
	- `box.items = source.copy()` left `new Box()`'s type argument unsolved.

	Upstream displays a method type parameter as `method.T`, so the test qualifies hxhx's. The
	native run uses `native/Main.hx`: frozen Stage3 cannot emit generic methods with constraints or
	call a method on a type parameter value, on main too.
**/
class M14TypeParameterBoundsTest {
	static final root = "test/fixtures/type_parameter_bounds";

	static function observe(command:String, arguments:Array<String>, expected:String):Void {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != expected)
			throw "type parameter bounds observer differs: " + stdout + stderr;
	}

	/** An inferred type of this fixture's module displays as `Main.Node`; upstream prints `Node`. **/
	static function local(display:String):String
		return StringTools.replace(display, "Main.", "");

	/** Upstream displays a method type parameter as `method.T`. **/
	static function shown(type:TyType, method:String):String
		return type.isTypeParameter() ? method + "." + type.getDisplay() : local(type.getDisplay());

	public static function main():Void {
		final expectedTypes = File.getContent(root + "/expected.types");
		observe("node_modules/.bin/haxe", [
			"-cp",
			"test/fixtures/method_parameter_dynamic_context",
			"-cp",
			root,
			"-main",
			"Main",
			"--macro",
			"UpstreamTypes.check(\"Main.Ops\")",
			"--no-output"
		], expectedTypes);
		final expectedSignatures = File.getContent(root + "/expected.signatures");
		observe("node_modules/.bin/haxe", [
			"-cp",
			"test/fixtures/method_parameter_dynamic_context",
			"-cp",
			root,
			"-main",
			"Main",
			"--macro",
			"UpstreamSignatures.check(\"Main.Ops\")",
			"--no-output"
		], expectedSignatures);
		final expected = File.getContent(root + "/expected.stdout");
		observe("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"], expected);
		observe("node_modules/.bin/haxe", ["-cp", root + "/native", "--run", "Main"], File.getContent(root + "/native/expected.stdout"));
		Sys.println("TYPE_PARAMETER_BOUNDS_UPSTREAM:PASS");

		final path = root + "/Main.hx";
		// Type the operations alone. With the calls in `main`, call-site evidence would supply the
		// types, and the check would not show what the method bodies imply.
		final full = File.getContent(path);
		final operationsOnly = full.substr(0, full.indexOf("class Main {")) + "class Main {\n\tstatic function main() {}\n}\n";
		final module = new ResolvedModule("Main", path, ParserStage.parse(operationsOnly, path));
		// Array access needs the standard library's Array, so type with a module loader, as the
		// typed oracle does.
		final arguments = Stage1Args.parse(["-cp", root, "-main", "Main"], true);
		final standardRoot = haxe.io.Path.removeTrailingSlashes(Stage1Args.getStandardLibraryRoot(arguments));
		final classPaths = [root, standardRoot + "/eval/_std", standardRoot];
		final defines = new haxe.ds.StringMap<String>();
		for (name in ["eval", "interp", "sys", "haxe4"])
			defines.set(name, "1");
		final index = TyperIndex.buildHeaders([module]);
		final loader = new ModuleLoader(classPaths, defines, index);
		loader.markResolvedAlready([module]);
		final typed = TyperStage.typeResolvedModule(module, index, loader, true);
		final observations:Array<String> = [];
		for (cls in typed.getTypedClasses())
			if (HxClassDecl.getName(cls.getSourceDeclaration()) == "Ops")
				for (fn in cls.getFunctions())
					for (parameter in fn.getEnvironment().getParams())
						observations.push(HxFunctionDecl.getName(fn.getSourceDeclaration()) + "." + parameter.getName() + "="
							+ shown(parameter.getType().unwrapNull(), HxFunctionDecl.getName(fn.getSourceDeclaration())));
		// The full signatures upstream gives, `Null` wrappers and results included.
		final signatures:Array<String> = [];
		// The local abstracts' members, which the upstream observers do not read. Upstream's
		// generic signatures (`$type` on the members): set (k:K, v:V) -> Void, get (k:K) -> V,
		// sum () -> Int.
		final members:Array<String> = [];
		for (cls in typed.getTypedClasses()) {
			final owner = HxClassDecl.getName(cls.getSourceDeclaration());
			for (fn in cls.getFunctions()) {
				final method = HxFunctionDecl.getName(fn.getSourceDeclaration());
				final environment = fn.getEnvironment();
				final inputs = [
					for (parameter in environment.getParams())
						parameter.getName() + " : " + (owner == "Ops" ? shown(parameter.getType(), method) : local(parameter.getType().getDisplay()))
				];
				final signature = "=(" + inputs.join(", ") + ") -> " + local(environment.getReturnType().getDisplay());
				if (owner == "Ops")
					signatures.push(method + signature);
				else if (owner == "Table" || owner == "Point")
					members.push(owner + "." + method + signature);
			}
		}
		members.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		final expectedMembers = [
			"Point.new=(x : Int, y : Int) -> Void",
			"Point.sum=() -> Int",
			"Table.get=(k : K) -> V",
			"Table.new=() -> Void",
			"Table.set=(k : K, v : V) -> Void"
		].join("\n");
		if (members.join("\n") != expectedMembers)
			throw "type parameter bounds abstract members differ:\n" + members.join("\n");
		signatures.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		if (signatures.join("\n") + "\n" != expectedSignatures)
			throw "type parameter bounds signatures differ:\n" + signatures.join("\n");
		observations.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		if (observations.join("\n") + "\n" != expectedTypes)
			throw "type parameter bounds input facts differ:\n" + observations.join("\n");
		final nativePath = root + "/native/Main.hx";
		final fullModule = new ResolvedModule("Main", nativePath, ParserStage.parse(File.getContent(nativePath), nativePath));
		final fullIndex = TyperIndex.buildHeaders([fullModule]);
		final fullLoader = new ModuleLoader([root + "/native"].concat(classPaths.slice(1)), defines, fullIndex);
		fullLoader.markResolvedAlready([fullModule]);
		final program = TyperStage.typeResolvedModule(fullModule, fullIndex, fullLoader, true);
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([program], []), ".tmp/type_parameter_bounds");
		observe(executable, [], File.getContent(root + "/native/expected.stdout"));
		Sys.println("TYPE_PARAMETER_BOUNDS_NATIVE:PASS");
	}
}
