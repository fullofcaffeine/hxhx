/** Emit ordinary instance updates and observe their values and receiver lifetime under collection. */
class M14CppInstanceUpdateTest {
	static function rejected(action:Void->Void, diagnostic:String):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(diagnostic) >= 0)
				return;
			throw error;
		}
		throw "instance update accepted an invalid field: " + diagnostic;
	}

	/** A valid field read does not authorize mutation, scalar conversion, or use in another compilation. */
	static function boundaries():Void {
		function project():backend.cpp.CppTypedProgramProjection {
			final source = 'class Main { public final fixed:Int = 7; public var optional:Null<Int>;'
				+ ' public var floating:Float = 1.5; public var erased:Dynamic; public var flag:Bool = false;'
				+ ' public function new() {} public function readFixed():Int return fixed;'
				+ ' public function readOptional():Null<Int> return optional; public function readFloating():Float return floating;'
				+ ' public function readErased():Dynamic return erased; public function readFlag():Bool return flag; }';
			final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
			return new backend.cpp.CppTypedProgramProjection(new MacroExpandedProgram([TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]))],
				false));
		}
		final program = project();
		final storage = new backend.cpp.CppManagedClassStorage(program);
		final foreign = new backend.cpp.CppManagedClassStorage(project());
		final owner = program.requireClass(program.requireClassIdentity("Main"));
		var checked = 0;
		for (fn in owner.getFunctions()) {
			if (HxFunctionDecl.getName(fn.getDeclaration()) == "new")
				continue;
			storage.assertFunction(fn);
			rejected(() -> foreign.assertFunction(fn), "foreign function owner");
			final expression = switch fn.getBody()[0] {
				case SReturn(value, _): value;
				case _: throw "instance update boundary lost its read";
			};
			final occurrence = fn.findField(expression);
			if (occurrence == null)
				throw "instance update boundary lost its field";
			final receiver = TyType.nominal(occurrence.getField().getOwner(), []);
			final member = storage.member(occurrence, receiver, occurrence.getType());
			rejected(() -> {
				backend.cpp.CppManagedInstanceField.update({
					occurrence: occurrence,
					member: member,
					op: Increment,
					fixity: Postfix,
					heap: "heap",
					prefix: "boundary_",
					destination: "result",
					renderReceiver: (_, _, _) -> throw "invalid update evaluated its receiver"
				}, "");
			}, member.fact.isFinal ? "mutable field" : "exact non-nullable Int field");
			checked++;
		}
		if (checked != 5)
			throw "instance update boundary coverage changed";
		Sys.println("CPP_INSTANCE_UPDATE_BOUNDARY:PASS");
	}

	static function main():Void {
		boundaries();
		final path = "test/oracle/cpp_instance_update_seed/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final output = ".tmp/cpp-instance-update";
		final result = backend.cpp.CppTargetCore.emit(new MacroExpandedProgram([typed], false),
			new backend.BackendContext(output, null, "Main", true, true, new haxe.ds.StringMap()));
		if (!result.builtExecutable || Sys.command(result.entryPath, []) != 0)
			throw "instance update assertions failed";
		CppManagedAssertionFixture.sanitizers(output, "CPP_INSTANCE_UPDATE");
		Sys.println("CPP_INSTANCE_UPDATE:PASS");
	}
}
