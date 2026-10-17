/** Match Haxe's brace-terminated function declarations without accepting unrelated missing semicolons. */
class M14SourceGroupTerminatorTest {
	static function observe(process:sys.io.Process):{code:Int, output:String, errors:String} {
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, output: output, errors: errors};
	}

	/** The native executable must return through the local function before evaluating the next declaration. */
	static function main():Void {
		final root = ".tmp/source-group-terminator";
		sys.FileSystem.createDirectory(root);
		for (entry in [
			{body: 'return { "ok"; }', accepted: true},
			{body: 'return "ok"', accepted: false},
			{body: 'return ({ "ok"; })', accepted: false}
		]) {
			final group = '{ function pick():String ' + entry.body + ' var value = pick(); value; }';
			final source = 'class Main { static function main():Void { var result = ' + group + '; Sys.println(result); } }';
			final path = root + "/Main.hx";
			sys.io.File.saveContent(path, source);
			final upstream = observe(new sys.io.Process("haxe", ["-cp", root, "--run", "Main"]));
			if ((upstream.code == 0) != entry.accepted || (entry.accepted && upstream.output != "ok\n"))
				throw "upstream terminator contract differs: " + upstream.output + upstream.errors;
			if (!entry.accepted && upstream.errors.indexOf("Missing ;") < 0)
				throw "negative source failed for an unrelated upstream reason: " + upstream.errors;
			var parsed:Null<HxExpr> = null;
			try {
				parsed = HxParser.parseCompleteExprText(group);
			} catch (error:HxParseError) {
				if (entry.accepted || error.message != "Expected ';' after source group expression")
					throw error;
			}
			if ((parsed != null) != entry.accepted)
				throw "local parser changed the semicolon requirement";
			if (!entry.accepted)
				continue;
			switch parsed {
				case ESourceGroup([
					ESourceFunction(facts, EReturn(ESourceGroup([EString("ok")], _)), [], _),
					EVars([EVariableDeclaration("value", "", ECall(EIdent("pick"), []), _, false, false)]),
					EIdent("value")
				], _):
					if (!facts.getKind().match(Named("pick", false)) || facts.getPlacement() != Declaration)
						throw "function declaration lost its lexical placement";
				case _:
					throw "function return or following declaration changed structure";
			}
			final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
			final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), root + "/ocaml", true);
			final native = observe(new sys.io.Process(executable, []));
			if (native.code != 0 || native.output != "ok\n")
				throw "native function terminator behavior differs: " + native.output + native.errors;
		}
		Sys.println("SOURCE_GROUP_TERMINATOR:PASS");
	}
}
