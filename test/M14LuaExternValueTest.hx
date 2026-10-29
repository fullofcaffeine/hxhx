/** Execute the same extern-value contract with upstream Haxe/Lua and the candidate. */
class M14LuaExternValueTest {
	static function main():Void {
		final root = "test/fixtures/lua_extern_value";
		final output = ".tmp/lua_extern_value";
		final expected = "3\n3\n13\n";
		// The host observer supplies and replaces a library table. Both compilers
		// execute the same Haxe calls against that external API without output edits.
		final host = "nativeLibrary = {len = string.len, length = string.len, replace = function() nativeLibrary = {len = function(value) return #value + 10 end} end}";
		sys.FileSystem.createDirectory(output);
		M14Stage3RuntimeFixture.observe({
			command: "node_modules/.bin/haxe",
			arguments: [
				"-D",
				"lua_vanilla",
				"-cp",
				root,
				"-main",
				"Main",
				"-lua",
				output + "/upstream.lua"
			],
			expected: ""
		});
		M14Stage3RuntimeFixture.observe({command: "lua", arguments: ["-e", host, output + "/upstream.lua"], expected: expected});
		Sys.println("LUA_EXTERN_VALUE_UPSTREAM:PASS");
		final path = root + "/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = MacroStage.expandProgram([typed], []);
		final emitted = backend.source.SourceTargetCommon.emitTarget(Lua, program,
			new backend.BackendContext(output + "/candidate", null, "Main", false, new haxe.ds.StringMap<String>()));
		M14Stage3RuntimeFixture.observe({command: "lua", arguments: ["-e", host, emitted.entryPath], expected: expected});
		ownership(program, resolved);
		publication(output);
		Sys.println("LUA_EXTERN_VALUE:PASS");
	}

	/** Look-alike source and foreign projections cannot borrow this program's occurrence authority. */
	static function ownership(program:backend.GenIrProgram, resolved:ResolvedModule):Void {
		final plan = new backend.source.LuaExternValues(program);
		final entry = backend.source.LuaProgramEntry.find(program, "Main");
		final fn = entry.main;
		final occurrence = fn.getRuntimeTypeCatalog().getEntries()[0];
		plan.functionValue(fn, occurrence.getExpression());
		final copy:HxExpr = switch occurrence.getExpression() {
			case ECall(callee, arguments): ECall(callee, arguments.copy());
			case _: throw "extern fixture lost its type marker";
		};
		reject(() -> plan.functionValue(fn, copy), "absent from the current function projection");
		final foreign = MacroStage.expandProgram([TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]))], []);
		final other = backend.source.LuaProgramEntry.find(foreign, "Main").main;
		reject(() -> plan.functionValue(other, other.getRuntimeTypeCatalog().getEntries()[0].getExpression()), "exact program function");
		switch occurrence.getExpression() {
			case ECall(_, arguments):
				arguments.push(ENull);
				reject(() -> plan.functionValue(fn, occurrence.getExpression()), "marker was mutated");
				arguments.pop();
			case _:
				throw "extern fixture lost its type marker";
		}
	}

	static function reject(action:Void->Void, diagnostic:String):Void {
		var observed = "";
		try
			action()
		catch (error:String)
			observed = error;
		if (observed.indexOf(diagnostic) < 0)
			throw "expected " + diagnostic + ", received " + observed;
	}

	/** Invalid native spellings cannot become target source or replace an existing artifact. */
	static function publication(output:String):Void {
		final retained = output + "/retained.lua";
		for (name in ["_G.invalid-name", "_G.end", "_G.string()"]) {
			final source = '@:native("' + name + '") extern class Host {} class Main {static function main():Void {var value = Host;}}';
			final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
			final program = MacroStage.expandProgram([TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]))], []);
			sys.io.File.saveContent(retained, "unchanged");
			reject(() -> backend.source.SourceTargetCommon.emitTarget(Lua, program,
				new backend.BackendContext(output, retained, "Main", false, new haxe.ds.StringMap<String>())),
				"unsupported Lua extern native identifier");
			if (sys.io.File.getContent(retained) != "unchanged")
				throw "rejected extern operation replaced published output";
		}
	}
}
