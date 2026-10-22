import backend.cpp.CppTargetCore;
import backend.cpp.CppTypedProgramProjection;
import backend.cpp.CppEmittedCallableContract.CppCallableParameterKind;
import backend.cpp.CppEmittedCallableContract.CppCallablePassingMode;

/** Specialized declaration renderers and calls must agree on whole-carrier deduction. */
class M14CppSpecialCallableContractTest {
	public static function run():Void {
		final source = 'class Main {}
class Assert { public static function q(T:Dynamic):String return ""; }
class Meta {
 public static function getMeta(T:Dynamic):String return "";
 public static function getFields(T:Dynamic):String return "";
 public static function getStatics(T:Dynamic):String return "";
 public static function getType(T:Dynamic):String return "";
}';
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
		final lookup = @:privateAccess CppTargetCore.collectClassLookup(program);
		for (owner in program.getModules()[0].projection.getClasses()) {
			if (HxClassDecl.getName(owner.getDeclaration()) == "Main")
				continue;
			for (projection in owner.getFunctions()) {
				final fn = projection.getDeclaration();
				final rendered = @:privateAccess CppTargetCore.renderHelperMethod(fn, owner.getDeclaration(), lookup).join("\n");
				if (rendered.indexOf("const T&") < 0)
					throw "Specialized declaration lost its const-reference parameter";
				final contract = @:privateAccess CppTargetCore.emittedCallableContract(fn, owner.getDeclaration(), lookup);
				final parameter = contract.getParameters()[0];
				if (parameter.cppType != "T" || parameter.kind != IndependentDeduced || parameter.passing != ConstReference)
					throw HxClassDecl.getName(owner.getDeclaration()) + "." + HxFunctionDecl.getName(fn) + " call facts disagree with const T&: "
						+ parameter.cppType;
				if (rendered.indexOf("const T& T_2") < 0)
					throw "The parameter captured its template's output name";
				final caller = @:privateAccess CppTargetCore.renderScope(owner.getDeclaration(), lookup, "void");
				caller.localTypes.set("probe", "std::optional<int>");
				final argument = @:privateAccess CppTargetCore.callArgExprForParam(HxExpr.EIdent("probe"), parameter.declaration, caller);
				if (argument != "probe")
					throw "A deduced argument lost its optional carrier: " + argument;
			}
		}
		assertValueAndErasedFamilies();
		assertDependentIterableFamily();
		Sys.println("CPP_SPECIAL_CALLABLE_CONTRACT:PASS");
	}

	/** By-value carriers and helper-owned aliases must survive the same declaration contract. */
	static function assertValueAndErasedFamilies():Void {
		final source = 'class Main {}
class Serializer { public static function run<T>(s:Dynamic):String return ""; }
class Type {
 public static function getClass<TValue>(__hxhx_class_type:Dynamic):Dynamic return null;
 public static function getEnum(__hxhx_enum_type:Dynamic):Dynamic return null;
}';
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
		final lookup = @:privateAccess CppTargetCore.collectClassLookup(program);
		for (owner in program.getModules()[0].projection.getClasses()) {
			final serializer = HxClassDecl.getName(owner.getDeclaration()) == "Serializer";
			if (!serializer && HxClassDecl.getName(owner.getDeclaration()) != "Type")
				continue;
			for (projection in owner.getFunctions()) {
				final fn = projection.getDeclaration();
				final expected = serializer ? "T_2" : HxFunctionDecl.getName(fn) == "getClass" ? "TValue_2" : "TValue";
				final passing = serializer ? Value : ConstReference;
				final contract = @:privateAccess CppTargetCore.emittedCallableContract(fn, owner.getDeclaration(), lookup);
				final parameter = contract.getParameters()[0];
				if (parameter.cppType != expected || parameter.passing != passing || parameter.kind != IndependentDeduced)
					throw "Specialized value/erased call contract disagrees: " + HxFunctionDecl.getName(fn) + " " + parameter.cppType;
				final rendered = @:privateAccess CppTargetCore.renderHelperMethod(fn, owner.getDeclaration(), lookup).join("\n");
				final sourceName = HxFunctionArg.getName(parameter.declaration);
				if (rendered.indexOf(parameter.signatureType() + " " + sourceName + "_2") < 0)
					throw "A source argument captured a helper-owned output symbol";
				if (serializer && rendered.indexOf("s->serialize(s_2)") < 0)
					throw "Serializer body did not consume its exact parameter";
				if (!serializer && rendered.indexOf("std::decay_t<" + expected + ">") < 0)
					throw "Erased helper body retained a different template name";
			}
		}
	}

	/** The iterable selects the element type; the element must not independently deduce another generic. */
	static function assertDependentIterableFamily():Void {
		final source = 'class Main {}
class Lambda { public static function has<A>(values:Iterable<A>, x:A):Bool return false; }';
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
		final lookup = @:privateAccess CppTargetCore.collectClassLookup(program);
		for (owner in program.getModules()[0].projection.getClasses()) {
			if (HxClassDecl.getName(owner.getDeclaration()) != "Lambda")
				continue;
			final fn = owner.getFunctions()[0].getDeclaration();
			final contract = @:privateAccess CppTargetCore.emittedCallableContract(fn, owner.getDeclaration(), lookup);
			final parameters = contract.getParameters();
			final templates = contract.getTemplates();
			if (templates.length != 1 || parameters[0].kind != Dependent || parameters[1].kind != Dependent)
				throw "Iterable and element must share one dependent callable generic";
			final generic = templates[0];
			switch (generic.owner) {
				case FunctionParameter(declaration) if (declaration == fn && generic.slot == 0):
				case _:
					throw "Iterable inference must retain the exact source generic owner";
			}
			if (parameters[0].getGenerics()[0] != generic
				|| parameters[1].getGenerics()[0] != generic
				|| parameters[0].passing != ConstReference
				|| parameters[1].passing != Value)
				throw "Iterable callable lost its shared generic identity or passing modes";
			if (parameters[0].cppType != "std::vector<" + generic.cppName + ">"
				|| parameters[1].cppType != "typename std::vector<" + generic.cppName + ">::value_type")
				throw "The element type must be selected from the iterable";
			final rendered = @:privateAccess CppTargetCore.renderHelperMethod(fn, owner.getDeclaration(), lookup).join("\n");
			if (rendered.indexOf(parameters[0].signatureType() + " values") < 0
				|| rendered.indexOf(parameters[1].signatureType() + " x_2") < 0
				|| rendered.indexOf("if (x == x_2)") < 0)
				throw "Iterable helper lost parameter ownership or captured the generated loop variable";
			final caller = @:privateAccess CppTargetCore.renderScope(owner.getDeclaration(), lookup, "void");
			final call = @:privateAccess CppTargetCore.renderClassMethodCallArgs("Lambda", "has", true, [HxExpr.EArrayDecl([]), HxExpr.EString("unused")],
				caller);
			if (call[0] != "std::vector<std::string>{}")
				throw "An empty iterable must use element evidence from the other argument: " + call[0];
		}
	}

	static function main():Void
		run();
}
