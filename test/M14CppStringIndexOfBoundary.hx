/** Exercise source identity independently of generated text and expose the authored callback boundary. */
function header(program:backend.cpp.CppTypedProgramProjection):String {
	final owner = program.requireClass(program.requireClassIdentity("Main"));
	final classes = new backend.cpp.CppManagedClassStorage(program);
	final boundary = owner.getFunctions().filter(fn -> HxFunctionDecl.getName(fn.getDeclaration()) == "boundary")[0];
	for (name in ["boundary", "shadow"]) {
		final fn = owner.getFunctions().filter(fn -> HxFunctionDecl.getName(fn.getDeclaration()) == name)[0];
		final expression = switch fn.getBody()[0] {
			case SReturn(value, _): value;
			case _: throw "indexOf boundary lost its return";
		};
		final call = fn.findInstanceCall(expression);
		if (call == null || backend.cpp.CppManagedStringIndexOf.selects(call) != (name == "boundary"))
			throw "indexOf selected the wrong declaration";
		if (name == "shadow") {
			reject(() -> backend.cpp.CppManagedStringIndexOf.require(call), "exact standard declaration");
			continue;
		}
		backend.cpp.CppManagedStringIndexOf.require(call);
		reject(() -> call.assertCurrent("different-owner", "different-revision"), "another executable or revision");
		final args = call.getDeclaration().getSignature().getArgs();
		final original = args[0];
		args[0] = TyType.fromHintText("Int");
		reject(() -> backend.cpp.CppManagedStringIndexOf.require(call), "a String needle");
		args[0] = original;
		switch expression {
			case ECall(_, values):
				values.push(HxExpr.EInt(99));
				reject(() -> backend.cpp.CppManagedStringIndexOf.require(call), "marker was mutated");
				values.pop();
			case _:
				throw "indexOf boundary lost its call";
		}
		final access = new backend.cpp.CppManagedLocalAccess({
			projection: fn,
			plan: new backend.cpp.CppManagedStoragePlan(fn),
			owner: Root(fn),
			parameters: ["value", "needle", "start"],
			temporaryPrefix: "hxhx_parameters_indexOf_"
		});
		final rooted = new backend.cpp.CppManagedRootedExpression({
			owner: CallableBody(access),
			classes: classes,
			heap: "heap",
			temporaryPrefix: "hxhx_value_indexOf_",
			resolve: _ -> throw "indexOf boundary has no nested closures"
		});
		final copy = switch expression {
			case ECall(target, values): HxExpr.ECall(target, values.copy());
			case _: throw "indexOf boundary lost its call";
		};
		reject(() -> rooted.valueType(copy), "not an exact expression");
		reject(() -> rooted.render(copy, "result", ""), "not an exact expression");
		backend.cpp.CppManagedStringIndexOf.require(call);
	}
	program.assertCurrent();
	return new backend.cpp.CppManagedProgramEmitter({
		functions: [
			{projection: boundary, rootSymbol: "observeStringIndexOf", symbolPrefix: "hxhx_function_indexOf_boundary_"}
		],
		output: [],
		classes: classes
	}).render();
}

/** Require the intended guard, so an unrelated failure cannot satisfy an ownership test. */
private function reject(action:Void->Void, expected:String):Void {
	try
		action()
	catch (error:haxe.Exception) {
		if (error.message.indexOf(expected) < 0)
			throw error;
		return;
	}
	throw "indexOf accepted invalid facts: " + expected;
}
