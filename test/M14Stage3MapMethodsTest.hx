import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds a map program with the Stage3 native emitter and compares it with upstream Haxe.

	Why
	- `haxe.ds.StringMap`, `IntMap`, and `ObjectMap` are `extern` classes, so
	  their methods have no Haxe body. Stage3 still writes an OCaml module for
	  each one, with an empty stub per method. `new StringMap()` produced the
	  placeholder `0`, `set` did nothing, and `get`/`exists` returned `0` and
	  `false`, with exit code 0.
	- The `Map<K, V>` abstract forwards to its backing value through the `IMap`
	  interface, whose calls also bound to stubs. Iterating `m.keys()` crashed
	  with SIGBUS, and map literals produced the placeholder `0`.

	What
	- `stage3_map_methods` uses every map method on String-, Int-, and
	  object-keyed maps, missing keys, removal, copies, clearing, the three
	  `for` forms, map literals, and `map[key]` reads and writes. Receivers
	  include locals, a static field, an instance field, and a parameter.
	- The native executable must print exactly what upstream Haxe 4.3.7 prints.
	- Every instance method of the emitted extern map classes must have a native
	  adapter, and every `Map<K, V>` instance method must stay a call for it.
	- A `Map` whose key type has no native table yet must fail at emit time
	  with a named error instead of reaching a placeholder at runtime.
**/
class M14Stage3MapMethodsTest {
	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
			return;
		}
		FileSystem.deleteFile(path);
	}

	static function compareWithUpstream(source:String):Array<TypedModule> {
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_map_methods";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_MAP_METHODS_WHOLE_FILE:PASS");
		return program;
	}

	static function declaration(program:Array<TypedModule>, module:String, name:String):HxClassDecl {
		final found = [
			for (typed in program.filter(typed -> typed.getSourceOrigin().sourceModulePath == module))
				for (candidate in HxModuleDecl.getClasses(typed.getBackendDeclaration()))
					if (HxClassDecl.getName(candidate) == name)
						candidate
		];
		if (found.length != 1)
			throw "expected the emitted " + module + " declaration, found " + found.length;
		return found[0];
	}

	static function instanceMethods(owner:HxClassDecl):Array<HxFunctionDecl> {
		final methods = [
			for (method in HxClassDecl.getFunctions(owner))
				if (!HxFunctionDecl.getIsStatic(method) && HxFunctionDecl.getName(method) != "new") method
		];
		methods.sort((left, right) -> HxFunctionDecl.getName(left) < HxFunctionDecl.getName(right) ? -1 : 1);
		return methods;
	}

	/**
		Every instance method of the emitted extern map classes must have a
		native adapter. The emitter rejects a bodiless map method without one,
		so this check keeps that rejection unreachable for valid programs.
	**/
	static function requireAdapterForEveryMapMethod(program:Array<TypedModule>):Void {
		final expected = "clear,copy,exists,get,iterator,keyValueIterator,keys,remove,set,toString";
		for (name in ["StringMap", "IntMap", "ObjectMap"]) {
			final names:Array<String> = [];
			for (method in instanceMethods(declaration(program, "haxe.ds." + name, name))) {
				final methodName = HxFunctionDecl.getName(method);
				if (HxFunctionDecl.getHasBody(method))
					throw name + "." + methodName + " has a Haxe body; this check assumes the extern class";
				if (!backend.ocaml.Stage3OcamlMapCalls.supports(methodName))
					throw name + "." + methodName + " has no native adapter in Stage3OcamlMapCalls";
				names.push(methodName);
			}
			if (names.join(",") != expected)
				throw "expected " + name + " instance methods <" + expected + ">, got <" + names.join(",") + ">";
		}
		Sys.println("M14_STAGE3_MAP_METHODS_ADAPTER_COVERAGE:PASS");
	}

	/** A Map method that stayed inline would reach the IMap interface stub again. */
	static function requireRetainedAbstractMethods(program:Array<TypedModule>):Void {
		final typed = program.filter(module -> module.getSourceOrigin().sourceModulePath == "haxe.ds.Map");
		if (typed.length != 1)
			throw "expected the typed haxe.ds.Map module, found " + typed.length;
		final names:Array<String> = [];
		for (owner in typed[0].getTypedClasses())
			for (fn in owner.getFunctions()) {
				final declaration = fn.getDeclaration();
				if (declaration == null || declaration.getIsStatic() || declaration.getSignature().getName() == "new")
					continue;
				if (!backend.ocaml.Stage3OcamlNativeCallPolicy.retain(declaration))
					throw "Map." + declaration.getSignature().getName() + " is not kept for the native map adapter";
				names.push(declaration.getSignature().getName());
			}
		names.sort((left, right) -> left < right ? -1 : 1);
		final expected = "arrayWrite,clear,copy,exists,get,iterator,keyValueIterator,keys,remove,set,toString";
		if (names.join(",") != expected)
			throw "expected Map instance methods <" + expected + ">, got <" + names.join(",") + ">";
		Sys.println("M14_STAGE3_MAP_METHODS_RETAINED_ABSTRACT:PASS");
	}

	/** A key type without a native table is an emit-time error, never a placeholder. */
	static function rejectUnsupportedKey():Void {
		final root = ".tmp/m14_stage3_map_methods_enum_key";
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		final source = "enum Color { Red; Blue; }\nclass Main {\n\tstatic function main() {\n\t\tfinal m = new Map<Color, Int>();\n\t\tm.set(Red, 1);\n\t\tSys.println(m.get(Red));\n\t}\n}\n";
		File.saveContent(path, source);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: source, path: path, root: root});
		final message = try {
			EmitterStage.emitToDir(new MacroExpandedProgram(program, false), root + "/out");
			null;
		} catch (error:haxe.Exception) {
			error.message;
		}
		deleteRecursive(root);
		if (message == null || message.indexOf("Map<Main.Color, Int>.") < 0 || message.indexOf("has no native map storage yet") < 0)
			throw "an enum-keyed Map must be rejected at emit time, got: " + message;
		Sys.println("M14_STAGE3_MAP_METHODS_UNSUPPORTED_KEY:PASS");
	}

	static function main():Void {
		final program = compareWithUpstream("test/fixtures/stage3_map_methods");
		requireAdapterForEveryMapMethod(program);
		requireRetainedAbstractMethods(program);
		rejectUnsupportedKey();
	}
}
