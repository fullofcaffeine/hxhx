import HxDefaultValue.NoDefault;
import HxExpr;
import HxStmt;
import haxe.ds.StringMap;

typedef CppXmlNavigationRenderFixture = {
	var owner:HxClassDecl;
	var lookup:backend.cpp.CppClassLookup;
	var methods:StringMap<HxFunctionDecl>;
	var scope:backend.cpp.CppRenderScope;
}

/**
	Repo-owned attribution probe for C++ XML navigation rendering.

	The fixture uses original names and XML text. It separates the compiler work
	for `elementsNamed`, iterator `next`, inferred local declarations, `addChild`,
	and the final String comparison so a small navigation method can be diagnosed
	without copying an upstream test.
**/
class M14CppXmlNavigationRenderBenchIntegrationTest {
	static inline final DEFAULT_CALLS = 50;

	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
	}

	static function envInt(name:String, fallback:Int):Int {
		final raw = Sys.getEnv(name);
		final parsed = raw == null ? null : Std.parseInt(raw);
		return parsed == null || parsed <= 0 ? fallback : parsed;
	}

	static function selected(name:String):Bool {
		final only = Sys.getEnv("HXHX_CPP_XML_NAVIGATION_RENDER_BENCH_ONLY");
		return only == null || StringTools.trim(only).length == 0 || only == name;
	}

	static function elapsed(name:String, calls:Int, action:Void->Void):Float {
		action();
		if (!selected(name))
			return -1.;
		final start = Sys.time();
		for (_ in 0...calls)
			action();
		return Sys.time() - start;
	}

	static function xmlCall(method:String, args:Array<HxExpr>):HxExpr {
		return ECall(EField(EIdent("Xml"), method), args);
	}

	static function fieldCall(receiver:HxExpr, method:String, args:Array<HxExpr>):HxExpr {
		return ECall(EField(receiver, method), args);
	}

	static function namedNext(receiver:HxExpr, name:String):HxExpr {
		return fieldCall(fieldCall(receiver, "elementsNamed", [EString(name)]), "next", []);
	}

	static function parseStmt():HxStmt {
		return SVar("document", "", xmlCall("parse", [EString('<catalog><branch code="west"/><twig/></catalog>')]), HxPos.unknown());
	}

	static function firstNextStmt():HxStmt {
		return SVar("branch", "", namedNext(EIdent("document"), "branch"), HxPos.unknown());
	}

	static function secondNextStmt():HxStmt {
		return SVar("twig", "", namedNext(EIdent("document"), "twig"), HxPos.unknown());
	}

	static function addChildStmt():HxStmt {
		return SExpr(fieldCall(EIdent("branch"), "addChild", [EIdent("twig")]), HxPos.unknown());
	}

	static function equalityStmt():HxStmt {
		return SExpr(ECall(EIdent("eq"), [fieldCall(EIdent("document"), "toString", []), EString("catalog output")]), HxPos.unknown());
	}

	static function fixture():CppXmlNavigationRenderFixture {
		final methods = new StringMap<HxFunctionDecl>();
		function add(name:String, body:Array<HxStmt>):HxFunctionDecl {
			final fn = new HxFunctionDecl(name, Public, false, [], "Void", body.concat([SReturnVoid(HxPos.unknown())]), "");
			methods.set(name, fn);
			return fn;
		}
		final parseOnly = add("parseOnly", [parseStmt()]);
		final oneNext = add("oneNamedNext", [parseStmt(), firstNextStmt()]);
		final twoNext = add("twoNamedNext", [parseStmt(), firstNextStmt(), secondNextStmt()]);
		final withChild = add("withChild", [parseStmt(), firstNextStmt(), secondNextStmt(), addChildStmt()]);
		final withEquality = add("withEquality", [parseStmt(), equalityStmt()]);
		final complete = add("completeNavigation", [parseStmt(), firstNextStmt(), secondNextStmt(), addChildStmt(), equalityStmt()]);
		final owner = new HxClassDecl("XmlNavigationBenchOwner", false, [parseOnly, oneNext, twoNext, withChild, withEquality, complete], [], "Test");
		final test = new HxClassDecl("Test", false, [], []);
		final xml = new HxClassDecl("Xml", false, [
			new HxFunctionDecl("parse", Public, true, [new HxFunctionArg("value", "String", NoDefault, false, false)], "Xml", [], ""),
			new HxFunctionDecl("elementsNamed", Public, false, [new HxFunctionArg("name", "String", NoDefault, false, false)], "Iterator<Xml>", [], ""),
			new HxFunctionDecl("addChild", Public, false, [new HxFunctionArg("child", "Xml", NoDefault, false, false)], "Void", [], ""),
			new HxFunctionDecl("toString", Public, false, [], "String", [], "")
		], []);
		final otherNode = new HxClassDecl("OtherNode", false, [], []);
		final otherNavigator = new HxClassDecl("OtherNavigator", false, [
			new HxFunctionDecl("elementsNamed", Public, false, [new HxFunctionArg("name", "String", NoDefault, false, false)], "Iterator<OtherNode>", [], "")
		], []);
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		final all = [owner, test, xml, otherNode, otherNavigator];
		for (cls in all) {
			final name = HxClassDecl.getName(cls);
			names.set(name, true);
			classes.set(name, cls);
		}
		final lookup = {names: names, byName: classes, all: all};
		final scope = @:privateAccess backend.cpp.CppTargetCore.renderScope(owner, lookup, "void");
		scope.localNames.set("document", "document");
		scope.localTypes.set("document", "std::shared_ptr<Xml>");
		scope.localTypeHints.set("document", "Xml");
		scope.localNames.set("branch", "branch");
		scope.localTypes.set("branch", "std::shared_ptr<Xml>");
		scope.localTypeHints.set("branch", "Xml");
		scope.localNames.set("twig", "twig");
		scope.localTypes.set("twig", "std::shared_ptr<Xml>");
		scope.localTypeHints.set("twig", "Xml");
		scope.localNames.set("xmlIterator", "xmlIterator");
		scope.localTypes.set("xmlIterator", "std::shared_ptr<__hxhx_iterator<std::shared_ptr<Xml>>>");
		scope.localTypeHints.set("xmlIterator", "Iterator<Xml>");
		scope.localNames.set("otherDocument", "otherDocument");
		scope.localTypes.set("otherDocument", "std::shared_ptr<OtherNavigator>");
		scope.localTypeHints.set("otherDocument", "OtherNavigator");
		return {
			owner: owner,
			lookup: lookup,
			methods: methods,
			scope: scope
		};
	}

	static function renderMethod(sample:CppXmlNavigationRenderFixture, name:String):String {
		sample.scope.functionAnalysisMemo.functionPreparations.clear();
		return @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(sample.methods.get(name), sample.owner, sample.lookup).join("\n");
	}

	/** Model a shortcut that reuses the exact typed-local Xml navigation fact. **/
	static function directTypedLocalXmlNamedNextExpr(expr:HxExpr, scope:backend.cpp.CppRenderScope):Null<String> {
		return switch (expr) {
			case ECall(EField(ECall(EField(xmlReceiver = EIdent(_), "elementsNamed"), namedArgs), "next"), nextArgs)
				if (namedArgs.length == 1 && nextArgs.length == 0 && @:privateAccess backend.cpp.CppTargetCore.exprCppType(xmlReceiver,
					scope) == "std::shared_ptr<Xml>"):
				@:privateAccess backend.cpp.CppTargetCore.renderExpr(xmlReceiver, scope)
				+ "->elementsNamed("
				+ @:privateAccess backend.cpp.CppTargetCore.renderFieldCallArgs("std::shared_ptr<Xml>", "elementsNamed", namedArgs, scope).join(", ")
				+ ")->next()";
			case _:
				null;
		};
	}

	/** Model the previous general iterator return-type discovery for comparison. **/
	static function typedLocalXmlNamedNextTypeWithoutShortcut(expr:HxExpr, scope:backend.cpp.CppRenderScope):String {
		return switch (expr) {
			case ECall(EField(receiver, "next"), args) if (args.length == 0):
				@:privateAccess backend.cpp.CppTargetCore.cppIteratorElementType(@:privateAccess backend.cpp.CppTargetCore.exprCppType(receiver, scope));
			case _:
				"";
		};
	}

	/** Model final general field-call assembly after the iterator type is rediscovered. **/
	static function typedLocalXmlNamedNextRenderWithoutShortcut(expr:HxExpr, scope:backend.cpp.CppRenderScope):String {
		return switch (expr) {
			case ECall(EField(receiver, "next"), args) if (args.length == 0):
				final receiverType = @:privateAccess backend.cpp.CppTargetCore.exprCppType(receiver, scope);
				@:privateAccess backend.cpp.CppTargetCore.renderExpr(receiver,
					scope) + @:privateAccess backend.cpp.CppTargetCore.fieldAccessOpForCppType(receiverType) + "next()";
			case _:
				"";
		};
	}

	static function main():Void {
		final calls = envInt("HXHX_CPP_XML_NAVIGATION_RENDER_BENCH_CALLS", DEFAULT_CALLS);
		final sample = fixture();
		final namedCall = fieldCall(EIdent("document"), "elementsNamed", [EString("branch")]);
		final nextCall = fieldCall(namedCall, "next", []);
		final iteratorNext = fieldCall(EIdent("xmlIterator"), "next", []);
		final otherNamedNext = namedNext(EIdent("otherDocument"), "branch");
		final addChildCall = fieldCall(EIdent("branch"), "addChild", [EIdent("twig")]);
		final equalityArgs = [fieldCall(EIdent("document"), "toString", []), EString("catalog output")];
		final wrongNextArity = fieldCall(namedCall, "next", [EInt(0)]);
		final wrongNamedArity = fieldCall(fieldCall(EIdent("document"), "elementsNamed", [EString("branch"), EString("extra")]), "next", []);
		final wrongNamedMethod = fieldCall(fieldCall(EIdent("document"), "elements", []), "next", []);
		final computedXmlNext = namedNext(xmlCall("parse", [EString("<computed/>")]), "computed");
		sample.scope.localNames.set("dynamicDocument", "dynamicDocument");
		sample.scope.localTypes.set("dynamicDocument", "std::any");
		final dynamicNext = namedNext(EIdent("dynamicDocument"), "branch");

		final namedType = @:privateAccess backend.cpp.CppTargetCore.exprCppType(namedCall, sample.scope);
		final nextType = @:privateAccess backend.cpp.CppTargetCore.exprCppType(nextCall, sample.scope);
		final namedOutput = @:privateAccess backend.cpp.CppTargetCore.renderExpr(namedCall, sample.scope);
		final nextOutput = @:privateAccess backend.cpp.CppTargetCore.renderExpr(nextCall, sample.scope);
		final directNextOutput = directTypedLocalXmlNamedNextExpr(nextCall, sample.scope);
		final iteratorNextOutput = @:privateAccess backend.cpp.CppTargetCore.renderExpr(iteratorNext, sample.scope);
		final otherNamedNextOutput = @:privateAccess backend.cpp.CppTargetCore.renderExpr(otherNamedNext, sample.scope);
		final addChildOutput = @:privateAccess backend.cpp.CppTargetCore.renderExpr(addChildCall, sample.scope);
		final equalityOutput = @:privateAccess backend.cpp.CppTargetCore.renderEqCallArgs(equalityArgs, sample.scope).join(", ");
		final completeOutput = renderMethod(sample, "completeNavigation");

		assertTrue(namedType == "std::shared_ptr<__hxhx_iterator<std::shared_ptr<Xml>>>",
			"Xml.elementsNamed should retain Iterator<Xml> typing, got " + namedType);
		assertTrue(nextType == "std::shared_ptr<Xml>", "Iterator<Xml>.next should retain Xml typing, got " + nextType);
		assertTrue(namedOutput == 'document->elementsNamed(std::string("branch"))',
			"Xml.elementsNamed should retain its String argument and pointer call, got " + namedOutput);
		assertTrue(nextOutput == namedOutput + "->next()", "the named Xml iterator should retain its next call, got " + nextOutput);
		assertTrue(directNextOutput == nextOutput, "the modeled typed-local shortcut must preserve exact navigation output");
		assertTrue(typedLocalXmlNamedNextTypeWithoutShortcut(nextCall, sample.scope) == nextType,
			"the shortcut and general iterator discovery must agree on the Xml result type");
		assertTrue(typedLocalXmlNamedNextRenderWithoutShortcut(nextCall, sample.scope) == nextOutput,
			"the shortcut and general field-call assembly must agree on exact C++ output");
		assertTrue(iteratorNextOutput == "xmlIterator->next()", "an already typed Xml iterator should retain its direct next call");
		assertTrue(otherNamedNextOutput == 'otherDocument->elementsNamed("branch")->next()',
			"an unrelated navigation API should remain on the general typed method path, got " + otherNamedNextOutput);
		assertTrue(addChildOutput == "branch->addChild(twig)", "Xml.addChild should retain its typed Xml argument, got " + addChildOutput);
		assertTrue(equalityOutput == 'document->toString(), std::string("catalog output")',
			"Xml.toString equality should retain String arguments, got " + equalityOutput);
		assertTrue(completeOutput.indexOf(namedOutput + "->next()") >= 0 && completeOutput.indexOf("branch->addChild(twig);") >= 0,
			"the complete navigation method should retain both iterator and child-mutation output");
		for (declined in [
			wrongNextArity,
			wrongNamedArity,
			wrongNamedMethod,
			computedXmlNext,
			dynamicNext,
			otherNamedNext
		]) {
			final isDirect = switch (declined) {
				case ECall(EField(receiver, method), args):
					@:privateAccess backend.cpp.CppTargetCore.isTypedLocalXmlElementsNamedNextCall(receiver, method, args, sample.scope);
				case _:
					false;
			};
			assertTrue(!isDirect, "wrong-arity, computed, erased, and unrelated navigation calls must stay on the general path");
		}

		var sink = 0;
		final namedTypeSeconds = elapsed("named_type", calls,
			() -> sink += @:privateAccess backend.cpp.CppTargetCore.exprCppType(namedCall, sample.scope).length);
		final namedRenderSeconds = elapsed("named_render", calls,
			() -> sink += @:privateAccess backend.cpp.CppTargetCore.renderExpr(namedCall, sample.scope).length);
		final nextTypeSeconds = elapsed("next_type", calls, () -> sink += @:privateAccess backend.cpp.CppTargetCore.exprCppType(nextCall, sample.scope)
			.length);
		final nextUnsharedTypeSeconds = elapsed("next_unshared_type", calls,
			() -> sink += typedLocalXmlNamedNextTypeWithoutShortcut(nextCall, sample.scope).length);
		final nextRenderSeconds = elapsed("next_render", calls,
			() -> sink += @:privateAccess backend.cpp.CppTargetCore.renderExpr(nextCall, sample.scope).length);
		final nextUnsharedRenderSeconds = elapsed("next_unshared_render", calls,
			() -> sink += typedLocalXmlNamedNextRenderWithoutShortcut(nextCall, sample.scope).length);
		final nextDirectRenderSeconds = elapsed("next_direct_render", calls, () -> {
			final rendered = directTypedLocalXmlNamedNextExpr(nextCall, sample.scope);
			sink += rendered == null ? 0 : rendered.length;
		});
		final localTypeSeconds = elapsed("next_local_type", calls, () -> sink += @:privateAccess
			backend.cpp.CppTargetCore.cppLocalDeclaredType("branch", "", nextCall, sample.scope, "branch").length);
		final localInitSeconds = elapsed("next_local_init", calls, () -> sink += @:privateAccess
			backend.cpp.CppTargetCore.renderLocalInitExpr(nextCall, "auto", "std::shared_ptr<Xml>", sample.scope).length);
		final iteratorNextTypeSeconds = elapsed("typed_iterator_next_type", calls,
			() -> sink += @:privateAccess backend.cpp.CppTargetCore.exprCppType(iteratorNext, sample.scope).length);
		final iteratorNextRenderSeconds = elapsed("typed_iterator_next_render", calls,
			() -> sink += @:privateAccess backend.cpp.CppTargetCore.renderExpr(iteratorNext, sample.scope).length);
		final otherNextTypeSeconds = elapsed("other_next_type", calls,
			() -> sink += @:privateAccess backend.cpp.CppTargetCore.exprCppType(otherNamedNext, sample.scope).length);
		final otherNextRenderSeconds = elapsed("other_next_render", calls,
			() -> sink += @:privateAccess backend.cpp.CppTargetCore.renderExpr(otherNamedNext, sample.scope).length);
		final addChildSeconds = elapsed("add_child_render", calls,
			() -> sink += @:privateAccess backend.cpp.CppTargetCore.renderExpr(addChildCall, sample.scope).length);
		final equalitySeconds = elapsed("string_equality_args", calls, () -> sink += @:privateAccess
			backend.cpp.CppTargetCore.renderEqCallArgs(equalityArgs, sample.scope).join(", ").length);
		final parseOnlySeconds = elapsed("method_parse_only", calls, () -> sink += renderMethod(sample, "parseOnly").length);
		final oneNextSeconds = elapsed("method_one_next", calls, () -> sink += renderMethod(sample, "oneNamedNext").length);
		final twoNextSeconds = elapsed("method_two_next", calls, () -> sink += renderMethod(sample, "twoNamedNext").length);
		final withChildSeconds = elapsed("method_with_child", calls, () -> sink += renderMethod(sample, "withChild").length);
		final withEqualitySeconds = elapsed("method_with_equality", calls, () -> sink += renderMethod(sample, "withEquality").length);
		final completeSeconds = elapsed("method_complete", calls, () -> sink += renderMethod(sample, "completeNavigation").length);
		assertTrue(sink > 0, "XML navigation attribution should retain generated output");

		Sys.println("cpp_xml_navigation_render_bench_calls=" + calls);
		Sys.println("named_type_seconds=" + namedTypeSeconds);
		Sys.println("named_render_seconds=" + namedRenderSeconds);
		Sys.println("next_type_seconds=" + nextTypeSeconds);
		Sys.println("next_unshared_type_seconds=" + nextUnsharedTypeSeconds);
		Sys.println("next_render_seconds=" + nextRenderSeconds);
		Sys.println("next_unshared_render_seconds=" + nextUnsharedRenderSeconds);
		Sys.println("next_direct_render_seconds=" + nextDirectRenderSeconds);
		Sys.println("next_local_type_seconds=" + localTypeSeconds);
		Sys.println("next_local_init_seconds=" + localInitSeconds);
		Sys.println("typed_iterator_next_type_seconds=" + iteratorNextTypeSeconds);
		Sys.println("typed_iterator_next_render_seconds=" + iteratorNextRenderSeconds);
		Sys.println("other_next_type_seconds=" + otherNextTypeSeconds);
		Sys.println("other_next_render_seconds=" + otherNextRenderSeconds);
		Sys.println("add_child_render_seconds=" + addChildSeconds);
		Sys.println("string_equality_args_seconds=" + equalitySeconds);
		Sys.println("method_parse_only_seconds=" + parseOnlySeconds);
		Sys.println("method_one_next_seconds=" + oneNextSeconds);
		Sys.println("method_two_next_seconds=" + twoNextSeconds);
		Sys.println("method_with_child_seconds=" + withChildSeconds);
		Sys.println("method_with_equality_seconds=" + withEqualitySeconds);
		Sys.println("method_complete_seconds=" + completeSeconds);
		Sys.println("M14_CPP_XML_NAVIGATION_RENDER_BENCH:PASS");
	}
}
