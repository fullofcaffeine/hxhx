import haxe.io.Path;
import sys.io.File;

/** Prove local storage conversions with an independent upstream and native output observer. */
class M14Stage3DynamicLocalStorageTest {
	static final root = "test/fixtures/stage3_dynamic_local_seed";

	static function observe(command:String, arguments:Array<String>):Void {
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, ["60", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != File.getContent(Path.join([root, "expected.stdout"])))
			throw "Dynamic local observer failed for " + command + ": " + stdout + stderr;
	}

	/** Equal source text cannot borrow facts from a distinct projection or a changed operand. */
	static function checkOwnership(functionValue:TypedFunction):Void {
		function calls(projection:TypedBackendFunctionProjection):Array<{name:String, value:HxExpr}> {
			final values = new Array<{name:String, value:HxExpr}>();
			for (statement in projection.getBody())
				TypedBackendSourceWalk.statement(statement, _ -> {}, node -> {
					switch node {
						case SVar(name, _, value, _):
							switch value {
								case ECall(_, _): values.push({name: name, value: value});
								case _:
							}
						case _:
					}
				});
			return values;
		}
		final projection = TypedBodySource.functionProjection(functionValue);
		final values = calls(projection);
		if (values.length == 0)
			throw "Dynamic local ownership fixture lost its call initializer";
		final selected = values[0];
		final write = projection.requireLocalWrite(selected.name, selected.value);
		if (!write.binding.getType().isDynamic() || write.sourceType.getSemanticKey() != "primitive:Bool")
			throw "local write lost its distinct source and destination types";
		final foreign = calls(TypedBodySource.functionProjection(functionValue))[0];
		reject(() -> projection.requireLocalWrite(foreign.name, foreign.value), "absent from this exact function projection");
		switch selected.value {
			case ECall(_, arguments):
				arguments.push(ENull);
			case _:
				throw "local write ownership fixture lost its call";
		}
		reject(() -> projection.requireLocalWrite(selected.name, selected.value), "changed after projection");
	}

	/** A static initializer owns its locals even when lowering introduces temporary writes. */
	static function checkInitializerOwnership(cls:TypedClass):Void {
		function select():TypedBackendFieldInitializerProjection {
			for (initializer in TypedBodySource.classProjection(cls).getFieldInitializers())
				if (HxFieldDecl.getName(initializer.getDeclaration()) == "initialized")
					return initializer;
			throw "missing static initializer storage fixture";
		}
		function callWrite(projection:TypedBackendFieldInitializerProjection):{name:String, value:HxExpr} {
			final values = new Array<{name:String, value:HxExpr}>();
			TypedBackendSourceWalk.expression(projection.getExpression(), node -> {
				switch node {
					case EVariableDeclaration(name, _, value, _, _, _) if (value != null && value.match(ECall(_, _))):
						values.push({name: name, value: value});
					case _:
				}
			});
			if (values.length != 1)
				throw "initializer lost its unique call-backed local";
			return values[0];
		}
		final projection = select();
		final selected = callWrite(projection);
		final write = projection.requireLocalWrite(selected.name, selected.value);
		if (write.binding.getIdentity().getOwnerIdentity() != projection.getStableIdentity()
			|| !write.binding.getType().isDynamic()
			|| write.sourceType.getSemanticKey() != "primitive:Bool")
			throw "initializer storage lost its field owner or source/destination types";
		final foreign = callWrite(select());
		reject(() -> projection.requireLocalWrite(foreign.name, foreign.value), "absent from this exact initializer projection");
		reject(() -> projection.requireLocalWrite("missing", selected.value), "absent from this exact initializer projection");
		switch selected.value {
			case ECall(_, arguments):
				arguments.push(ENull);
			case _:
				throw "initializer ownership fixture lost its call";
		}
		reject(() -> projection.requireLocalWrite(selected.name, selected.value), "initializer projection was mutated");
	}

	static function reject(action:Void->TypedBackendLocalWrite, diagnostic:String):Void {
		try {
			action();
		} catch (failure:haxe.Exception) {
			if (failure.message.indexOf(diagnostic) >= 0)
				return;
			throw failure;
		}
		throw "local write accepted invalid ownership";
	}

	static function main():Void {
		observe("haxe", ["-cp", root, "--run", "Main"]);
		final path = Path.join([root, "Main.hx"]);
		final parsed = ParserStage.parse(File.getContent(path), path);
		final resolved = new ResolvedModule("Main", path, parsed);
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		checkInitializerOwnership(typed.getTypedClasses()[0]);
		final functions = typed.getTypedClasses()[0].getFunctions();
		final revisions = [for (fn in functions) CompilerTypedTreeRevision.functionBody(fn)];
		for (fn in functions)
			if (HxFunctionDecl.getName(fn.getSourceDeclaration()) == "main")
				checkOwnership(fn);
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), ".tmp/stage3-dynamic-local-seed", true);
		observe(executable, []);
		for (index in 0...functions.length)
			if (revisions[index] != CompilerTypedTreeRevision.functionBody(functions[index]))
				throw "local storage emission changed typed source";
		Sys.println("M14_STAGE3_DYNAMIC_LOCAL_STORAGE:PASS");
	}
}
