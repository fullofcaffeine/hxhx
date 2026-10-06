import backend.cpp.CppTargetCore;
import backend.cpp.CppTypedProgramProjection;
import backend.cpp.CppExecutableLocals;

/** Observe actual symbol-plan construction without changing production factories. */
private class ObservedCppProgram extends CppTypedProgramProjection {
	public var functionPlans(default, null):Int = 0;
	public var observedMemo:Null<backend.cpp.CppFunctionAnalysisMemo> = null;
	public var rejectPublishedHeader:Bool = false;
	public var rejectedPublishedHeader(default, null):Bool = false;

	public override function requireFunction(owner:HxClassDecl, declaration:HxFunctionDecl):TypedBackendFunctionProjection {
		if (rejectPublishedHeader && observedMemo != null && observedMemo.emittedCallableSelectionsInProgress.exists(declaration)) {
			rejectedPublishedHeader = true;
			throw new haxe.Exception("Injected declaration lookup failure");
		}
		return super.requireFunction(owner, declaration);
	}

	public override function functionLocals(owner:HxClassDecl, declaration:HxFunctionDecl, ?fixedSymbols:Array<String>):CppExecutableLocals {
		functionPlans++;
		return super.functionLocals(owner, declaration, fixedSymbols);
	}
}

/** Signature queries must preserve recursive results without allocating output symbols. */
class M14CppCallableAnalysisBoundaryTest {
	public static function run():Void {
		for (spec in [
			{source: "Dynamic->Dynamic", expected: "std::function<std::any(std::any)>"},
			{source: "Any->Void", expected: "std::function<void(std::any)>"},
			{source: "(?value:Dynamic)->Void", expected: "std::function<void(std::optional<std::any>)>"},
			{source: "Int->String", expected: "std::function<std::string(int)>"}
		])
			if (backend.cpp.CppTypeModel.cppFunctionTypeHint(spec.source) != spec.expected)
				throw "Callable storage changed the declared carrier: " + spec.source;
		final source = 'class Main {
 static function first(n:Int) return second(n);
 static function second(n:Int) return n <= 0 ? 1 : first(n - 1);
 static function self(n:Int) return n <= 0 ? 1 : self(n - 1);
}
class Box { public function new(value:Int) {} }
class Text { public static function echo(value:String):String return value; }
class Hooks {
 public function new() {}
 public dynamic function echo(int:Int, int_:Int):Int return int + int_;
 public static dynamic function sum(int:Int, int_:Int):Int return int + int_;
}';
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		for (mode in 0...3)
			for (order in 0...3) {
				final program = new ObservedCppProgram(new MacroExpandedProgram([typed], false));
				final owner = program.getModules()[0].projection.getClasses()[0];
				final functions = owner.getFunctions();
				final lookup = @:privateAccess CppTargetCore.collectClassLookup(program);
				final first = functions[order].getDeclaration();
				switch (mode) {
					case 0:
						@:privateAccess CppTargetCore.inferredFunctionArgCppTypes(first, owner.getDeclaration(), lookup);
					case 1:
						@:privateAccess CppTargetCore.inferredFunctionReturnCppType(first, owner.getDeclaration(), lookup);
					case 2:
						@:privateAccess CppTargetCore.renderHelperMethod(first, owner.getDeclaration(), lookup);
				}
				final initialPlans = program.functionPlans;
				if (mode != 2 && initialPlans != 0)
					throw "The initial type-only query allocated executable symbols";
				for (projection in functions) {
					final fn = projection.getDeclaration();
					final contract = @:privateAccess CppTargetCore.emittedCallableContract(fn, owner.getDeclaration(), lookup);
					if (contract.returnType != "int" || contract.getParameterTypes().join(",") != "int")
						throw "Recursive query mode/order "
							+ mode
							+ "/"
							+ order
							+ " changed "
							+ HxFunctionDecl.getName(fn)
							+ " to "
							+ contract.returnType;
					if ((@:privateAccess CppTargetCore.emittedCallableContract(fn, owner.getDeclaration(), lookup)) != contract)
						throw "A completed callable was selected again";
				}
				if (lookup.functionAnalysisMemo.emittedCallableSelectionsInProgress.iterator().hasNext())
					throw "Recursive selection left an active header";
				final queryScope = @:privateAccess CppTargetCore.renderScope(owner.getDeclaration(), lookup, "auto");
				final constructorTypes = @:privateAccess CppTargetCore.constructorArgCppTypes("Box", queryScope);
				if (constructorTypes.join(",") != "int")
					throw "Constructor type discovery lost its parameter representation";
				final textOwner = program.getModules()[0].projection.getClasses()[2];
				if (!(@:privateAccess CppTargetCore.isStaticStringExtensionMethod(textOwner.getFunctions()[0].getDeclaration(), textOwner.getDeclaration(),
					queryScope)))
					throw "String-extension type discovery changed eligibility";
				final hook = HxExpr.EField(HxExpr.ENew("Hooks", []), "echo");
				final stored = @:privateAccess CppTargetCore.assignmentDynamicFunctionSlotCppType(hook, queryScope);
				final bound = @:privateAccess CppTargetCore.boundFunctionReceiverCppType(hook, queryScope);
				if (stored != "std::function<int(int, int)>" || bound != stored)
					throw "Stored and bound dynamic callback queries disagree on the declaration";
				final staticHook = HxExpr.EField(HxExpr.EIdent("Hooks"), "sum");
				if ((@:privateAccess CppTargetCore.assignmentDynamicFunctionSlotCppType(staticHook, queryScope)) != stored)
					throw "Static dynamic callback storage lost its exact declaration";
				if (program.functionPlans != initialPlans)
					throw "Type-only callable queries allocated " + (program.functionPlans - initialPlans) + " executable symbol plans";
				@:privateAccess CppTargetCore.renderHelperMethod(first, owner.getDeclaration(), lookup);
				if (program.functionPlans == initialPlans)
					throw "Rendering did not request its executable symbol plan";
			}
		assertFailedSelectionCanRetry(typed);
		Sys.println("CPP_CALLABLE_ANALYSIS_BOUNDARY:PASS");
	}

	/** A dependency failure after header publication must not poison the same request's retry. */
	static function assertFailedSelectionCanRetry(typed:TypedModule):Void {
		final program = new ObservedCppProgram(new MacroExpandedProgram([typed], false));
		final owner = program.getModules()[0].projection.getClasses()[0];
		final fn = owner.getFunctions()[0].getDeclaration();
		final lookup = @:privateAccess CppTargetCore.collectClassLookup(program);
		program.observedMemo = lookup.functionAnalysisMemo;
		program.rejectPublishedHeader = true;
		var rejected = false;
		try {
			@:privateAccess CppTargetCore.emittedCallableContract(fn, owner.getDeclaration(), lookup);
		} catch (error:haxe.Exception) {
			if (error.message != "Injected declaration lookup failure")
				throw error;
			rejected = true;
		}
		if (!rejected || !program.rejectedPublishedHeader)
			throw "The cleanup probe never reached its injected failure";
		final memo = lookup.functionAnalysisMemo;
		if (memo.emittedCallableContracts.exists(fn)
			|| memo.emittedCallableSelectionsInProgress.iterator().hasNext()
			|| memo.inferredSignaturesInProgress.iterator().hasNext()
			|| memo.functionPreparationsInProgress.iterator().hasNext())
			throw "Failed callable selection retained completed or active state";
		program.rejectPublishedHeader = false;
		final retried = @:privateAccess CppTargetCore.emittedCallableContract(fn, owner.getDeclaration(), lookup);
		if (retried.returnType != "int" || program.functionPlans != 0)
			throw "A clean retry changed its result or allocated output symbols";
	}

	static function main():Void
		run();
}
