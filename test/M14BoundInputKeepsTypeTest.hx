import hxhx.Stage1Compiler.Stage1Args;
import sys.io.File;

/**
	Compare input types around a recursive call that passes a wider value to a parameter the body
	already bound, with upstream Haxe 4.3.7; check the full (wrapped) types; then run the native
	output.

	`switch (s)` binds `s` to `Item`; the later `show(inner)` with `inner:Null<Item>` must not
	widen it. hxhx started the recursive call's input trial from the declaration header, where `s`
	is still open, so the call's `Null<Item>` won (haxe_ocaml-wynm4; haxe.CallStack.itemToString,
	where the pattern variable also shadows the parameter). The upstream observer reads through
	`Null`, so the wrapped types are checked separately below.
**/
class M14BoundInputKeepsTypeTest {
	static final root = "test/fixtures/bound_input_keeps_type";

	static function observe(command:String, arguments:Array<String>, expected:String):Void {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != expected)
			throw "bound input keeps type observer differs: " + stdout + stderr;
	}

	/** An inferred type of this fixture's module displays as `Main.Item`; upstream's observer prints `Item`. **/
	static function local(display:String):String
		return StringTools.replace(display, "Main.", "");

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
		final expected = File.getContent(root + "/expected.stdout");
		observe("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"], expected);
		Sys.println("BOUND_INPUT_KEEPS_TYPE_UPSTREAM:PASS");

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
							+ local(parameter.getType().unwrapNull().getDisplay()));
		// The wrapped types upstream gives, which the observer above reads through.
		final wrapped:Array<String> = [];
		for (cls in typed.getTypedClasses())
			if (HxClassDecl.getName(cls.getSourceDeclaration()) == "Ops")
				for (fn in cls.getFunctions())
					for (parameter in fn.getEnvironment().getParams())
						wrapped.push(HxFunctionDecl.getName(fn.getSourceDeclaration()) + "." + parameter.getName() + "="
							+ local(parameter.getType().getDisplay()));
		wrapped.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		final expectedWrapped = "shadowed.s=Item\nshow.s=Item";
		if (wrapped.join("\n") != expectedWrapped)
			throw "bound input keeps type wrapped types differ:\n" + wrapped.join("\n");
		observations.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		if (observations.join("\n") + "\n" != expectedTypes)
			throw "bound input keeps type input facts differ:\n" + observations.join("\n");
		final fullModule = new ResolvedModule("Main", path, ParserStage.parse(full, path));
		final fullIndex = TyperIndex.buildHeaders([fullModule]);
		final fullLoader = new ModuleLoader(classPaths, defines, fullIndex);
		fullLoader.markResolvedAlready([fullModule]);
		final program = TyperStage.typeResolvedModule(fullModule, fullIndex, fullLoader, true);
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([program], []), ".tmp/bound_input_keeps_type");
		observe(executable, [], expected);
		Sys.println("BOUND_INPUT_KEEPS_TYPE_NATIVE:PASS");
	}
}
