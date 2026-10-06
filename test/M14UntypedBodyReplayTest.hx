import backend.BackendContext;
import backend.vm.NekoTargetCore;

/** Recovered untyped blocks must replay the inferred occurrences and preserve executable behavior. */
class M14UntypedBodyReplayTest {
	static function main():Void {
		@:privateAccess M14TypedBodyBoundaryIntegrationTest.assertStructuralUntypedStatementBlock();
		final root = ".tmp/untyped_body_replay";
		sys.FileSystem.createDirectory(root);
		final body = 'var total:Dynamic=1; if (true) total=total+2; return total;';
		final source = 'class Main { static function decode():Dynamic { untyped {' + body + '} } static function main():Void { Sys.println(decode()); } }';
		final path = root + '/Main.hx';
		sys.io.File.saveContent(path, source);
		final expected = '3\n';
		if (run('haxe', ['-cp', root, '-main', 'Main', '--interp']) != expected)
			throw 'upstream untyped block differs';
		final ordinary = ParserStage.parse(source, path);
		final position = new HxPos(0, 1, 1);
		final recovered = new HxFunctionDecl('decode', HxVisibility.Public, true, [], 'Dynamic',
			[SExpr(EUntyped(ETryCatchRaw('opaque_block_expr:{' + body + '}')), position)], '', [], position);
		final main = HxClassDecl.getFunctions(HxModuleDecl.getMainClass(ordinary.getDecl()))[1];
		final owner = new HxClassDecl('Main', true, [recovered, main], []);
		final parsed = new ParsedModule('', new HxModuleDecl('', [], owner, [owner], false, false), path);
		final resolved = new ResolvedModule('Main', path, parsed);
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		JsRuntimeFixture.assertRuntime(typed, 'Main', expected);
		final program = MacroStage.expandProgram([typed], []);
		final context = new BackendContext(root, root + '/main.n', 'Main', true, false, HxDefineMap.fromRawDefines(['neko=1']));
		final split = @:privateAccess NekoTargetCore.renderSplitProgram(program, context, root + '/main.neko');
		sys.io.File.saveContent(split.entryPath, split.entrySource);
		for (part in split.support)
			sys.io.File.saveContent(part.path, part.source);
		sys.io.File.saveContent(root + '/single.neko', @:privateAccess NekoTargetCore.renderProgram(program, context));
		for (file in sys.FileSystem.readDirectory(root))
			if (StringTools.endsWith(file, '.neko'))
				run('nekoc', [root + '/' + file]);
		for (layout in ['main', 'single']) {
			if (run('neko', [root + '/' + layout + '.n']) != expected)
				throw 'recovered untyped block differs in ' + layout;
			Sys.println('UNTYPED_BODY_REPLAY:PASS ' + layout);
		}
		// A later source edit must not reuse the retained inferred occurrences.
		final environment = new TyFunctionEnv('decode', [], [], TyType.fromHintText('Dynamic'), TyType.unknown());
		environment.retainFunctionBody(recovered, TypedBodyBuilder.expandStructuralStatements(HxFunctionDecl.getBody(recovered)));
		HxFunctionDecl.getBody(recovered).push(SReturn(EInt(9), position));
		var rejected = false;
		try
			environment.functionBodyForReplay(recovered)
		catch (error:haxe.Exception)
			rejected = error.message.indexOf('unchanged inferred source') >= 0;
		if (!rejected)
			throw 'changed source reused its old inference body';
		Sys.println('UNTYPED_BODY_REPLAY:PASS stale-source');
	}

	/** Observe process success and output; compilation alone does not prove runtime behavior. */
	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw command + ' failed: ' + errors;
		return output;
	}
}
