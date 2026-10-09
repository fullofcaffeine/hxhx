import backend.cpp.CppTargetCore;
import backend.cpp.CppTypedProgramProjection;
import backend.cpp.CppEmittedCallableContract.CppCallableParameterKind;
import backend.cpp.CppEmittedCallableContract.CppCallablePassingMode;

/**
	Calls must use the parameter representations that their selected declaration emits.
	These source declarations differ only in the existing specialized renderer's
	eligibility. Ordinary Dynamic retains its current string representation; the
	specialized declaration independently deduces each complete argument carrier.
	Private access observes the backend boundary without replacing its analysis.
 */
class M14CppEmittedCallableContractTest {
	public static function run():Void {
		final source = 'class Main {
 static function ordinary(value:Dynamic, other:Dynamic):Bool return false;
 static function isOfType(value:Dynamic, other:Dynamic):Bool return value == null && other != null;
}';
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
		final owner = program.getModules()[0].projection.getClasses()[0];
		final lookup = @:privateAccess CppTargetCore.collectClassLookup(program);
		final ordinary = owner.getFunctions()[0].getDeclaration();
		final specialized = owner.getFunctions()[1].getDeclaration();
		final ordinaryTypes = @:privateAccess CppTargetCore.inferredFunctionArgCppTypes(ordinary, owner.getDeclaration(), lookup);
		if (ordinaryTypes.join(",") != "std::string,std::string")
			throw "Ordinary Dynamic parameter representation changed: " + ordinaryTypes.join(",");
		final emitted = @:privateAccess CppTargetCore.renderHelperMethod(specialized, owner.getDeclaration(), lookup).join("\n");
		if (emitted.indexOf("const TValue&") < 0 || emitted.indexOf("const TType&") < 0)
			throw "The specialized declaration lost its independent const-reference signature";
		final specializedTypes = @:privateAccess CppTargetCore.inferredFunctionArgCppTypes(specialized, owner.getDeclaration(), lookup);
		if (specializedTypes.join(",") != "TValue,TType")
			throw "Call analysis disagrees with the emitted carrier parameters: " + specializedTypes.join(",");
		final repeated = @:privateAccess CppTargetCore.inferredFunctionArgCppTypes(specialized, owner.getDeclaration(), lookup);
		if (repeated.join(",") != specializedTypes.join(","))
			throw "Warm callable parameter facts changed";
		assertQueryOrders(program, owner, ordinary, specialized);
		assertGenericNamesAndPlacement();
		assertRecordParameterQueryOrders();
		Sys.println("CPP_EMITTED_CALLABLE_CONTRACT:PASS");
	}

	/** A cached aggregate name must retain the field types needed by a later inference scope. */
	static function assertRecordParameterQueryOrders():Void {
		final arg = new HxFunctionArg("record", "{ amount:Float, count:Int }", NoDefault, false, false);
		final fn = new HxFunctionDecl("sum", Public, true, [arg], "", [
			HxStmt.SReturn(HxExpr.EBinop("+", HxExpr.EField(HxExpr.EIdent("record"), "amount"), HxExpr.EField(HxExpr.EIdent("record"), "count")),
				HxPos.unknown())
		], "");
		final owner = new HxClassDecl("RecordOwner", false, [fn], []);
		for (order in 0...3) {
			final names = new haxe.ds.StringMap<Bool>();
			final classes = new haxe.ds.StringMap<HxClassDecl>();
			names.set("RecordOwner", true);
			classes.set("RecordOwner", owner);
			final lookup = {names: names, byName: classes};
			final freshScope = @:privateAccess CppTargetCore.renderScope(owner, lookup, "auto");
			if (freshScope.anonStructs.iterator().hasNext())
				throw "Record definitions escaped their request lifetime";
			switch (order) {
				case 0:
					final scope = @:privateAccess CppTargetCore.renderScope(owner, lookup, "auto");
					@:privateAccess CppTargetCore.cppFunctionArgType(arg, scope);
				case 1:
					@:privateAccess CppTargetCore.inferredFunctionReturnCppType(fn, owner, lookup);
				case 2:
					@:privateAccess CppTargetCore.inferredFunctionArgCppTypes(fn, owner, lookup);
			}
			final contract = @:privateAccess CppTargetCore.emittedCallableContract(fn, owner, lookup);
			if (contract.returnType != "double")
				throw "Record field types disappeared after query order " + order + ": " + contract.returnType;
			final laterScope = @:privateAccess CppTargetCore.renderScope(owner, lookup, "auto");
			final recordType = contract.getParameterTypes()[0];
			if ((@:privateAccess CppTargetCore.anonStructFieldCppType(recordType, "amount",
				laterScope)) != "double" || (@:privateAccess CppTargetCore.anonStructFieldCppType(recordType, "count", laterScope)) != "int")
				throw "A later scope cannot interpret cached record fields";
		}
	}

	/** Fresh request memos must not select a different signature after another analysis runs first. */
	static function assertQueryOrders(program:CppTypedProgramProjection, owner:TypedBackendClassProjection, ordinary:HxFunctionDecl,
			specialized:HxFunctionDecl):Void {
		for (order in 0...3) {
			final lookup = @:privateAccess CppTargetCore.collectClassLookup(program);
			switch (order) {
				case 0:
					@:privateAccess CppTargetCore.renderHelperMethod(specialized, owner.getDeclaration(), lookup);
				case 1:
					@:privateAccess CppTargetCore.inferredFunctionArgCppTypes(specialized, owner.getDeclaration(), lookup);
				case 2:
					@:privateAccess CppTargetCore.cppMethodSignatureReturnType(specialized, owner.getDeclaration(), lookup);
			}
			final contract = @:privateAccess CppTargetCore.emittedCallableContract(specialized, owner.getDeclaration(), lookup);
			final parameters = contract.getParameters();
			final projected = owner.getFunctions()[1].getParameters();
			if (parameters.length != 2 || contract.getParameterTypes().join(",") != "TValue,TType")
				throw "Callable query order changed its parameter facts";
			for (index in 0...parameters.length) {
				final parameter = parameters[index];
				if (parameter.binding != projected[index]
					|| parameter.slot != index
					|| parameter.kind != IndependentDeduced
					|| parameter.passing != ConstReference)
					throw "Callable contract lost exact binding order or carrier passing mode";
			}
			parameters.pop();
			contract.getTemplates().pop();
			contract.getFixedSymbols().pop();
			if (contract.getParameters().length != 2
				|| contract.getTemplates().length != 2
				|| (@:privateAccess CppTargetCore.emittedCallableContract(specialized, owner.getDeclaration(), lookup)) != contract)
				throw "Callable inventory or repeated lookup changed immutable facts";
			reject(() -> contract.requireParameter(HxFunctionDecl.getArgs(ordinary)[0]), "another declaration's parameter");
			reject(() -> contract.requireParameter(new HxFunctionArg("value", "Dynamic", NoDefault, false, false)), "a same-shaped foreign parameter");
			reject(() -> contract.assertOwner(owner.getDeclaration(), ordinary, owner.getFunctions()[0]), "another exact function");
			if (lookup.functionAnalysisMemo.emittedCallableSelectionsInProgress.iterator().hasNext())
				throw "Callable selection retained an in-progress entry after success";
		}
	}

	/** Generic output names must avoid real declaration generics; optional placement uses the contract. */
	static function assertGenericNamesAndPlacement():Void {
		final source = 'class Generic<TValue> {
 static function isOfType<TType>(value:Dynamic, other:Dynamic):Bool return value == null && other != null;
}
class Main {
 static function target(?value:Int, enabled:Bool):Int return value == null ? 0 : value;
}';
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
		final classes = program.getModules()[0].projection.getClasses();
		final generic = classes[0];
		final main = classes[1];
		final lookup = @:privateAccess CppTargetCore.collectClassLookup(program);
		final fn = generic.getFunctions()[0].getDeclaration();
		final contract = @:privateAccess CppTargetCore.emittedCallableContract(fn, generic.getDeclaration(), lookup);
		if (contract.getParameterTypes().join(",") != "TValue_2,TType_2")
			throw "Synthetic callable generics captured class or function generic names";
		reject(() -> @:privateAccess CppTargetCore.emittedCallableContract(fn, main.getDeclaration(), lookup), "another class owner");
		final target = main.getFunctions()[0].getDeclaration();
		final scope = @:privateAccess CppTargetCore.renderScope(main.getDeclaration(), lookup, "void");
		final rendered = @:privateAccess CppTargetCore.renderFunctionCallArgs(HxFunctionDecl.getArgs(target), [HxExpr.EBool(false)], scope);
		if (rendered.join(",") != "std::nullopt,false")
			throw "Callable optional placement or its inserted default changed: " + rendered.join(",");
	}

	static function reject(action:Void->Void, label:String):Void {
		try {
			action();
		} catch (_:haxe.Exception) {
			return;
		}
		throw "Callable contract accepted " + label;
	}

	static function main():Void
		run();
}
