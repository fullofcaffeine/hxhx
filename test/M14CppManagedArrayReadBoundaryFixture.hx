import backend.cpp.CppManagedArrayRead.elementType;
import backend.cpp.CppManagedLocalAccess;
import backend.cpp.CppManagedProgramEmitter;
import backend.cpp.CppManagedRootedExpression;
import backend.cpp.CppManagedStaticDefault.render as renderDefault;
import backend.cpp.CppManagedStoragePlan;
import backend.cpp.CppTypedProgramProjection;

/**
	Generate the authored callback-indexed read with a stable native observer symbol.
	The same program supplies exact Array facts and default selection. Negative checks
	ensure copied expressions and incomplete types cannot borrow those facts.
 */
function header(program:CppTypedProgramProjection):String {
	final classes = new backend.cpp.CppManagedClassStorage(program);
	final functions = [
		for (module in program.getModules())
			for (owner in module.projection.getClasses())
				if (owner.requireSemanticFacts().getClassIdentity() == "Main")
					for (fn in owner.getFunctions())
						if (HxFunctionDecl.getName(fn.getDeclaration()) == "readWithIndex")
							fn
	];
	if (functions.length != 1)
		throw "array boundary fixture lost its exact source method";
	final fn = functions[0];
	final body = fn.getBody();
	if (body.length != 1)
		throw "array boundary fixture changed its source body";
	final expression = switch body[0] {
		case SReturn(value, _): value;
		case _: throw "array boundary fixture lost its return";
	};
	final access = new CppManagedLocalAccess({
		projection: fn,
		plan: new CppManagedStoragePlan(fn),
		owner: Root(fn),
		parameters: ["values", "index"],
		temporaryPrefix: "hxhx_parameters_array_boundary_"
	});
	final rooted = new CppManagedRootedExpression({
		owner: CallableBody(access),
		heap: "heap",
		temporaryPrefix: "hxhx_value_array_boundary_",
		resolve: _ -> throw "array boundary fixture has no closures",
		defaultValue: type -> renderDefault(program, type)
	});
	if (rooted.valueType(expression).getSemanticKey() != "primitive:Int")
		throw "array read lost its declared element type";
	final copy = switch expression {
		case EArrayAccess(array, index): HxExpr.EArrayAccess(array, index);
		case _: throw "array boundary fixture lost its read";
	};
	rejected(() -> rooted.valueType(copy), "not an exact expression");
	rejected(() -> rooted.render(copy, "result", ""), "not an exact expression");
	final integer = TyType.fromHintText("Int");
	rejected(() -> elementType(TyType.unknown(), integer), "complete semantic types");
	rejected(() -> elementType(TyType.nominal(new TyNominalTypeId("Array"), [TyType.unknown()]), integer), "complete semantic types");
	for (wrong in ["String", "Bool", "Float", "Dynamic", "Null<Bool>"])
		rejected(() -> elementType(TyType.nominal(new TyNominalTypeId("Array"), [integer]), TyType.fromHintText(wrong)), "Int index");
	final entries:Array<backend.cpp.CppManagedProgramEmitter.CppManagedProgramFunction> = [
		{projection: fn, rootSymbol: "observeArrayRead", symbolPrefix: "hxhx_function_array_boundary"}
	];
	final owner = program.requireClass(program.requireClassIdentity("Main"));
	for (name in [
		"recoverBoolean",
		"returnBoolean",
		"readBoolean",
		"writeBoolean",
		"writeInteger",
		"writeWithIndex",
		"pushBoolean",
		"discardPush",
		"pushWithValue",
		"lengthBoolean"
	]) {
		final selected = owner.getFunctions().filter(candidate -> HxFunctionDecl.getName(candidate.getDeclaration()) == name);
		if (selected.length != 1)
			throw "array boundary fixture lost its recovery method: " + name;
		entries.push({projection: selected[0], rootSymbol: "observe_" + name, symbolPrefix: "hxhx_function_" + name});
	}
	for (name in ['pushBoolean', 'shadowPush']) {
		final selected = owner.getFunctions().filter(candidate -> HxFunctionDecl.getName(candidate.getDeclaration()) == name);
		if (selected.length != 1)
			throw 'array boundary lost its push selection control';
		final expression = switch selected[0].getBody()[0] {
			case SReturn(value, _): value;
			case _: throw 'push selection control lost its return';
		};
		final call = selected[0].findInstanceCall(expression);
		if (call == null || backend.cpp.CppManagedArrayPush.selects(call) != (name == 'pushBoolean'))
			throw 'push binding confused standard and user declarations';
		if (name == 'pushBoolean') {
			backend.cpp.CppManagedArrayPush.require(call);
			switch expression {
				case ECall(_, arguments):
					arguments.push(HxExpr.EBool(false));
					rejected(() -> backend.cpp.CppManagedArrayPush.require(call), 'mutated');
					arguments.pop();
				case _:
					throw 'push selection control lost its call marker';
			}
			backend.cpp.CppManagedArrayPush.require(call);
		} else
			rejected(() -> backend.cpp.CppManagedArrayPush.require(call), 'exact standard declaration');
	}
	for (name in ['lengthBoolean', 'shadowLength']) {
		final selected = owner.getFunctions().filter(candidate -> HxFunctionDecl.getName(candidate.getDeclaration()) == name);
		if (selected.length != 1)
			throw 'array boundary lost its length selection control';
		final expression = switch selected[0].getBody()[0] {
			case SReturn(value, _): value;
			case _: throw 'length selection control lost its return';
		};
		final field = selected[0].findField(expression);
		if (field == null || backend.cpp.CppManagedArrayLength.selects(field) != (name == 'lengthBoolean'))
			throw 'length binding confused standard and user fields';
		if (name == 'lengthBoolean') {
			backend.cpp.CppManagedArrayLength.require(field);
			final access = new CppManagedLocalAccess({
				projection: selected[0],
				plan: new CppManagedStoragePlan(selected[0]),
				owner: Root(selected[0]),
				parameters: ['values'],
				temporaryPrefix: 'hxhx_parameters_length_boundary_'
			});
			final reader = new CppManagedRootedExpression({
				owner: CallableBody(access),
				classes: classes,
				heap: 'heap',
				temporaryPrefix: 'hxhx_value_length_boundary_',
				resolve: _ -> throw 'length boundary has no closures'
			});
			if (reader.valueType(expression).getSemanticKey() != 'primitive:Int')
				throw 'array length lost its Int type';
			final copy = switch expression {
				case EField(receiver, name): HxExpr.EField(receiver, name);
				case _: throw 'length selection control lost its field';
			};
			rejected(() -> reader.valueType(copy), 'not an exact expression');
			rejected(() -> reader.render(copy, 'result', ''), 'not an exact expression');
		} else
			rejected(() -> backend.cpp.CppManagedArrayLength.require(field), 'exact standard field');
	}
	return new CppManagedProgramEmitter({
		functions: entries,
		output: [],
		classes: classes,
		defaultValue: type -> renderDefault(program, type)
	}).render();
}

/** Require the intended diagnostic so an unrelated failure cannot satisfy a negative case. */
private function rejected(action:Void->Void, message:String):Void {
	try
		action()
	catch (error:haxe.Exception) {
		if (error.message.indexOf(message) < 0)
			throw error;
		return;
	}
	throw "array boundary accepted invalid facts: " + message;
}
