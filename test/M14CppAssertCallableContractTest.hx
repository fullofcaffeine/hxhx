import backend.cpp.CppTargetCore;
import backend.cpp.CppTypedProgramProjection;
import backend.cpp.CppEmittedCallableContract.CppCallableParameterKind;
import backend.cpp.CppEmittedCallableContract.CppCallablePassingMode;

/** Assertion calls must preserve independent carriers and mutate the caller's status object. */
class M14CppAssertCallableContractTest {
	public static function run():Void {
		for (approximation in ["", "Float", "Int"])
			assertSameAsContract(approximation);
		assertSameAsContract("Int", true);
		for (count in 2...8)
			assertSameContract(count);
		for (count in 2...5)
			assertEqContract(count);
		assertNeutralContract(false);
		assertNeutralContract(true);
		for (count in 0...4)
			assertFunctionWrapperContract(count);
		for (method in ["t", "f"])
			for (count in 0...4)
				assertValueWrapperContract(method, count);
		for (count in 0...5)
			assertAllowContract(count, true);
		assertAllowContract(2, false);
		for (event in [false, true])
			for (extra in [false, true])
				assertHookContract(event, extra);
		Sys.println("CPP_ASSERT_CALLABLE_CONTRACT:PASS");
	}

	/** Rebindable hooks keep their erased callback carrier and every exact source parameter. */
	static function assertHookContract(event:Bool, extra:Bool):Void {
		final method = event ? "createEvent" : "createAsync";
		final callback = event ? "EventArg->Void" : "Void->Void";
		final source = 'package utest; class Assert { public static dynamic function '
			+ method
			+ (event ? '<EventArg>' : '')
			+ '('
			+ (event ? '' : '?')
			+ 'int:'
			+ callback
			+ ', ?int_:Int'
			+ (extra ? ', extra:String = "tail"' : '')
			+ '):'
			+ callback
			+ ' return null; }';
		final resolved = new ResolvedModule("utest.Assert", "utest/Assert.hx", ParserStage.parse(source, "utest/Assert.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
		final lookup = @:privateAccess CppTargetCore.collectClassLookup(program);
		final owner = program.getModules()[0].projection.getClasses()[0];
		final fn = owner.getFunctions()[0].getDeclaration();
		final contract = @:privateAccess CppTargetCore.emittedCallableContract(fn, owner.getDeclaration(), lookup);
		final returned = event ? "std::function<void(std::any)>" : "std::function<void()>";
		final input = event ? returned : "std::optional<" + returned + ">";
		if (contract.returnType != returned
			|| contract.getTemplates().length != 0
			|| contract.getParameterTypes().join(",") != input + ",std::optional<int>" + (extra ? ",std::string" : ""))
			throw "Callable hook queries must describe its erased assignable signature";
		final rendered = @:privateAccess CppTargetCore.renderUtestAssertSupportClass(owner.getDeclaration(), lookup).join("\n");
		if (rendered.indexOf("std::function<" + returned + "(" + contract.getParameterTypes().join(", ") + ")> " + method) < 0)
			throw "Callable hook storage disagrees with its selected signature";
		if (rendered.indexOf(input + " int__2") < 0 || rendered.indexOf("(void)int__2;") < 0 || rendered.indexOf("(void)int_;") < 0)
			throw "Callable hook initializer lost exact renamed source parameters";
		if (extra && rendered.indexOf("std::string extra") < 0)
			throw "Callable hook dropped a trailing source parameter";
	}

	/** The value and collection share one generic identity, not merely the same emitted spelling. */
	static function assertAllowContract(count:Int, declared:Bool):Void {
		final item = declared ? "A" : "Dynamic";
		final source = 'package utest; class Test { public function allow' + (declared ? '<A>' : '') + '(' + (count > 0 ? 'value:' + item : '')
			+ (count > 1 ? ', values:Array<' + item + '>' : '') + (count > 2 ? ', ?position:haxe.PosInfos' : '')
			+ (count > 3 ? ', extra:String = "tail"' : '') + '):Void {} }';
		final resolved = new ResolvedModule("utest.Test", "utest/Test.hx", ParserStage.parse(source, "utest/Test.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
		final lookup = @:privateAccess CppTargetCore.collectClassLookup(program);
		final owner = program.getModules()[0].projection.getClasses()[0];
		final fn = owner.getFunctions()[0].getDeclaration();
		final contract = @:privateAccess CppTargetCore.emittedCallableContract(fn, owner.getDeclaration(), lookup);
		final params = contract.getParameters();
		if (params.length != count || contract.getTemplates().length != (count == 0 ? 0 : 1))
			throw "allow must retain source arity and its one shared carrier";
		if (count > 0 && (params[0].kind != IndependentDeduced || params[0].passing != ConstReference))
			throw "allow value must preserve independently deduced storage";
		if (count > 1
			&& (params[1].kind != Dependent
				|| params[1].passing != Value
				|| params[1].getGenerics()[0] != params[0].getGenerics()[0]
				|| params[1].cppType != "std::vector<" + params[0].cppType + ">"))
			throw "allow collection lost its dependency on the value carrier";
		if (count > 1 && declared && params[0].cppType != "A")
			throw "allow replaced the shared source generic with a private renderer generic";
		if (count > 1) {
			if (!contract.hasIndependentDeductionFor(params[1]))
				throw "allow collection cannot use the value's exact deduction";
			if (declared)
				switch (params[0].getGenerics()[0].owner) {
					case FunctionParameter(owner) if (owner == fn):
					case _:
						throw "allow lost the exact source generic owner";
				}
		}
		if (contract.getTrailingParameters().length != (count < 3 ? 1 : 0))
			throw "allow must distinguish added and source position parameters";
		final rendered = @:privateAccess CppTargetCore.renderUnitTestBaseSupportClass(owner.getDeclaration(), lookup).join("\n");
		if (count > 3 && rendered.indexOf('std::string extra = "tail"') < 0)
			throw "allow dropped a trailing source argument";
	}

	/** Deduced values and exact trailing source arguments must survive the support-class route. */
	static function assertValueWrapperContract(method:String, count:Int):Void {
		final source = 'package utest; class Test { public function ' + method + '<TValue>(' + (count > 0 ? 'TValue:TValue' : '')
			+ (count > 1 ? ', ?where:haxe.PosInfos' : '') + (count > 2 ? ', extra:String = "tail"' : '') + '):Void {} }';
		final resolved = new ResolvedModule("utest.Test", "utest/Test.hx", ParserStage.parse(source, "utest/Test.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
		final lookup = @:privateAccess CppTargetCore.collectClassLookup(program);
		final owner = program.getModules()[0].projection.getClasses()[0];
		final fn = owner.getFunctions()[0].getDeclaration();
		final contract = @:privateAccess CppTargetCore.emittedCallableContract(fn, owner.getDeclaration(), lookup);
		final params = contract.getParameters();
		if (params.length != count || contract.returnType != "void" || contract.getTemplates().length != (count == 0 ? 0 : 1))
			throw "Value wrapper must retain source arity and only the required carrier template";
		if (count > 0 && (params[0].passing != ConstReference || params[0].kind != IndependentDeduced))
			throw "Value wrapper lost its independent const-reference carrier";
		if (contract.getTrailingParameters().length != (count < 2 ? 1 : 0))
			throw "Value wrapper must separate target-added position from source parameters";
		final rendered = @:privateAccess CppTargetCore.renderUnitTestBaseSupportClass(owner.getDeclaration(), lookup).join("\n");
		if (count > 0 && rendered.indexOf(params[0].signatureType() + " TValue_3") < 0)
			throw "Value wrapper's parameter collided with its source or synthetic generic";
		if (count > 2 && rendered.indexOf('std::string extra = "tail"') < 0)
			throw "Value wrapper dropped a trailing source argument";
	}

	/** Callback wrappers retain all source parameters and keep added positions outside source arity. */
	static function assertFunctionWrapperContract(count:Int):Void {
		final source = 'package utest; class Test {
 public function exc('
			+ (count > 0 ? 'pos:Void->Void' : '')
			+ (count > 1 ? ', ?where:haxe.PosInfos' : '')
			+ (count > 2 ? ', extra:String = "tail"' : '')
			+ '):Void {}
}';
		final resolved = new ResolvedModule("utest.Test", "utest/Test.hx", ParserStage.parse(source, "utest/Test.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
		final lookup = @:privateAccess CppTargetCore.collectClassLookup(program);
		final owner = program.getModules()[0].projection.getClasses()[0];
		final fn = owner.getFunctions()[0].getDeclaration();
		final contract = @:privateAccess CppTargetCore.emittedCallableContract(fn, owner.getDeclaration(), lookup);
		final params = contract.getParameters();
		if (params.length != count || (count > 0 && (params[0].cppType != "std::function<void()>" || params[0].passing != Value)))
			throw "Callback wrapper must retain its fixed callback and complete source argument list";
		if (contract.getTrailingParameters().length != (count < 2 ? 1 : 0))
			throw "Callback wrapper must distinguish source and target-added positions";
		if (count > 1 && params[1].cppType != "std::optional<PosInfos>")
			throw "Callback wrapper position differs from its emitted signature";
		final rendered = @:privateAccess CppTargetCore.renderUnitTestBaseSupportClass(owner.getDeclaration(), lookup).join("\n");
		if (count > 2 && rendered.indexOf('std::string extra = "tail"') < 0)
			throw "Callback wrapper dropped a trailing source argument";
	}

	/** The class-selected fast and generic fallback signatures must also own caller adaptation. */
	static function assertNeutralContract(generic:Bool):Void {
		final source = 'package utest; class Assert {
 public static function probe'
			+ (generic ? '<T>' : '')
			+ '(value:'
			+ (generic ? 'T' : 'Dynamic')
			+ ', ?pos:haxe.PosInfos, message:String = "kept"):Bool return false;
}';
		final resolved = new ResolvedModule("utest.Assert", "utest/Assert.hx", ParserStage.parse(source, "utest/Assert.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
		final lookup = @:privateAccess CppTargetCore.collectClassLookup(program);
		final owner = program.getModules()[0].projection.getClasses()[0];
		final fn = owner.getFunctions()[0].getDeclaration();
		final contract = @:privateAccess CppTargetCore.emittedCallableContract(fn, owner.getDeclaration(), lookup);
		final params = contract.getParameters();
		if (params[0].cppType != (generic ? "T" : "std::any")
			|| params[1].cppType != (generic ? "std::shared_ptr<PosInfos>" : "std::optional<PosInfos>"))
			throw "Neutral assertion contract differs from the class-selected parameter storage";
		if (contract.getTemplates().length != (generic ? 1 : 0))
			throw "Neutral assertion lost its source generic template";
		final rendered = @:privateAccess CppTargetCore.renderUtestAssertSupportClass(owner.getDeclaration(), lookup).join("\n");
		for (parameter in params)
			if (rendered.indexOf(parameter.signatureType() + " " + HxFunctionArg.getName(parameter.declaration)) < 0)
				throw "Neutral class renderer does not consume the selected signature";
		if (rendered.indexOf(generic ? 'message = "kept"' : 'message = std::string("kept")') < 0)
			throw "Neutral signature changed its selected default expression";
	}

	/** Added target arguments must not replace or drop exact source parameters. */
	static function assertEqContract(count:Int):Void {
		final source = 'class Main {} class Test {
 public function eq<TExpected,TValue>(pos:Dynamic, TValue:Dynamic'
			+ (count > 2 ? ", ?where:haxe.PosInfos" : "")
			+ (count > 3 ? ', extra:String = "tail"' : "")
			+ '):Void {}
}';
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
		final lookup = @:privateAccess CppTargetCore.collectClassLookup(program);
		for (owner in program.getModules()[0].projection.getClasses()) {
			if (HxClassDecl.getName(owner.getDeclaration()) != "Test")
				continue;
			final fn = owner.getFunctions()[0].getDeclaration();
			final contract = @:privateAccess CppTargetCore.emittedCallableContract(fn, owner.getDeclaration(), lookup);
			final params = contract.getParameters();
			if (contract.getTemplates().length != 2 || params.length != count || contract.returnType != "void")
				throw "eq requires two independent carriers and every source parameter";
			final trailing = contract.getTrailingParameters();
			if (trailing.length != (count == 2 ? 1 : 0))
				throw "eq must keep its added position distinct from source arity";
			if (count == 2 && (trailing[0].slot != 2 || trailing[0].cppType != "std::optional<PosInfos>"))
				throw "eq added position has the wrong order or storage";
			for (i in 0...2)
				if (params[i].kind != IndependentDeduced || params[i].passing != ConstReference)
					throw "eq lost its independent reference carrier";
			final rendered = @:privateAccess CppTargetCore.renderHelperMethod(fn, owner.getDeclaration(), lookup).join("\n");
			if (count > 2 && params[2].cppType != "std::optional<PosInfos>")
				throw "eq position storage differs between its contract and declaration";
			if (count > 3 && rendered.indexOf('std::string extra = "tail"') < 0)
				throw "eq dropped a trailing source argument";
			if (rendered.indexOf(".value()") >= 0)
				throw "eq must forward an absent optional position without unwrapping it";
		}
	}

	/** Six optional parameters use the fast signature; a seventh retains ordinary source defaults. */
	static function assertSameContract(count:Int):Void {
		final tail = [
			"?recursive:Bool",
			"?msg:String",
			"?approx:Float",
			"?pos:haxe.PosInfos",
			"extra:String = \"tail\""
		];
		final source = 'class Main {} class Assert {
 public static function same<TExpected,TValue>(__hxhx_status:Dynamic, TValue:Dynamic'
			+ (count == 2 ? "" : ", " + tail.slice(0, count - 2).join(", "))
			+ '):Bool return true;
}';
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
		final lookup = @:privateAccess CppTargetCore.collectClassLookup(program);
		for (owner in program.getModules()[0].projection.getClasses()) {
			if (HxClassDecl.getName(owner.getDeclaration()) != "Assert")
				continue;
			final fn = owner.getFunctions()[0].getDeclaration();
			final contract = @:privateAccess CppTargetCore.emittedCallableContract(fn, owner.getDeclaration(), lookup);
			final params = contract.getParameters();
			if (contract.getTemplates().length != 2 || params.length != count || contract.returnType != "bool")
				throw "same requires two independent carriers and all source parameters";
			for (i in 0...2)
				if (params[i].kind != IndependentDeduced || params[i].passing != ConstReference)
					throw "same lost its independent reference parameter";
			final rendered = @:privateAccess CppTargetCore.renderHelperMethod(fn, owner.getDeclaration(), lookup).join("\n");
			if (rendered.indexOf(params[0].signatureType() + " __hxhx_status_2") < 0)
				throw "same parameter collides with generated status storage";
			if (count > 2 && rendered.indexOf("std::optional<bool> recursive = std::nullopt") < 0)
				throw "same lost its optional recursive argument";
			if (count == 7 && rendered.indexOf("std::string extra = \"tail\"") < 0)
				throw "ordinary same lost its source default: " + rendered;
			final classRoute = @:privateAccess CppTargetCore.renderUtestAssertPolymorphicMethod(fn, owner.getDeclaration(), lookup);
			if (classRoute == null || classRoute.join("\n") != rendered)
				throw "Assertion class and method routes disagree for same";
		}
	}

	/** Float selects the fast renderer; Int selects the ordinary renderer with the same reference contract. */
	static function assertSameAsContract(approximation:String, extra:Bool = false):Void {
		final source = 'class Main {}
class Assert {
 public static function sameAs<TExpected,TValue,TStatus>(TExpected:Dynamic, TValue:Dynamic, __hxhx_status:Dynamic'
			+ (approximation.length == 0 ? "" : ", approx:" + approximation)
			+ (extra ? ", extra:String" : "")
			+ '):Bool return true;
}';
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
		final lookup = @:privateAccess CppTargetCore.collectClassLookup(program);
		for (owner in program.getModules()[0].projection.getClasses()) {
			if (HxClassDecl.getName(owner.getDeclaration()) != "Assert")
				continue;
			final fn = owner.getFunctions()[0].getDeclaration();
			final contract = @:privateAccess CppTargetCore.emittedCallableContract(fn, owner.getDeclaration(), lookup);
			final parameters = contract.getParameters();
			final count = 3 + (approximation.length > 0 ? 1 : 0) + (extra ? 1 : 0);
			if (contract.getTemplates().length != 3 || parameters.length != count || contract.returnType != "bool")
				throw "sameAs requires three independent generic carriers and its complete source argument list";
			for (index in 0...3) {
				final passing = index == 2 ? MutableReference : ConstReference;
				if (parameters[index].kind != IndependentDeduced || parameters[index].passing != passing)
					throw "sameAs lost its emitted passing contract at parameter " + index;
			}
			if (approximation.length > 0
				&& (parameters[3].kind != Fixed
					|| parameters[3].passing != Value
					|| parameters[3].cppType != (approximation == "Float" ? "double" : "int")))
				throw "sameAs approximation type differs from its selected renderer";
			if (approximation.length > 0 && parameters[3].emitDefault != (approximation == "Int"))
				throw "sameAs lost the selected renderer's default-publication policy";
			final rendered = @:privateAccess CppTargetCore.renderHelperMethod(fn, owner.getDeclaration(), lookup).join("\n");
			if (rendered.indexOf(parameters[2].signatureType() + " __hxhx_status_2") < 0
				|| rendered.indexOf("__hxhx_status_ref(__hxhx_status_2)") < 0)
				throw "sameAs status parameter captured the generated status reference";
			if (extra && rendered.indexOf(", std::string extra)") < 0)
				throw "sameAs silently dropped a trailing source parameter";
			final classRoute = @:privateAccess CppTargetCore.renderUtestAssertPolymorphicMethod(fn, owner.getDeclaration(), lookup);
			if (classRoute == null || classRoute.join("\n") != rendered)
				throw "Assertion class and method routes disagree on the same exact declaration";
		}
	}

	static function main():Void
		run();
}
