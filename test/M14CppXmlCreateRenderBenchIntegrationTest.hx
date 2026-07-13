import HxDefaultValue.NoDefault;
import HxExpr;
import HxStmt;
import haxe.ds.StringMap;

typedef CppXmlCreateRenderFixture = {
	var owner:HxClassDecl;
	var lookup:backend.cpp.CppClassLookup;
	var methods:StringMap<HxFunctionDecl>;
	var scope:backend.cpp.CppRenderScope;
}

/**
	Repo-owned attribution probe for C++ XML creation rendering.

	The fixture uses original literals and method composition while preserving
	the factory, parse, node-property, and assertion shapes exposed by the
	unfiltered strict TestXML hotspot.
**/
class M14CppXmlCreateRenderBenchIntegrationTest {
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
		final only = Sys.getEnv("HXHX_CPP_XML_CREATE_RENDER_BENCH_ONLY");
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

	static function toStringCall(value:HxExpr):HxExpr {
		return ECall(EField(value, "toString"), []);
	}

	static function eq(actual:HxExpr, expected:HxExpr):HxStmt {
		return SExpr(ECall(EIdent("eq"), [actual, expected]), HxPos.unknown());
	}

	static function factoryBody():Array<HxStmt> {
		return [
			eq(toStringCall(xmlCall("createDocument", [])), EString("")),
			eq(toStringCall(xmlCall("createPCData", [EString("bench text")])), EString("bench text")),
			eq(toStringCall(xmlCall("createCData", [EString("<bench>")])), EString("<![CDATA[<bench>]]>")),
			eq(toStringCall(xmlCall("createComment", [EString("bench note")])), EString("<!--bench note-->")),
			eq(toStringCall(xmlCall("createProcessingInstruction", [EString("BENCH")])), EString("<?BENCH?>")),
			eq(toStringCall(xmlCall("createDocType", [EString("BENCH")])), EString("<!DOCTYPE BENCH>"))
		];
	}

	static function parseBody():Array<HxStmt> {
		return [
			eq(EField(ECall(EField(xmlCall("parse", [EString("<!--parsed note-->")]), "firstChild"), []), "nodeValue"), EString("parsed note")),
			eq(EField(ECall(EField(xmlCall("parse", [EString("<![CDATA[parsed data]]>")]), "firstChild"), []), "nodeValue"), EString("parsed data"))
		];
	}

	static function localFlowBody():Array<HxStmt> {
		return [
			SVar("node", "Xml", xmlCall("createComment", [EString("local note")]), HxPos.unknown()),
			eq(EField(EIdent("node"), "nodeValue"), EString("local note")),
			SExpr(EBinop("=", EField(EIdent("node"), "nodeValue"), EString("updated note")), HxPos.unknown()),
			eq(EField(EIdent("node"), "nodeValue"), EString("updated note")),
			eq(toStringCall(EIdent("node")), EString("<!--updated note-->"))
		];
	}

	static function fixture():CppXmlCreateRenderFixture {
		final methods = new StringMap<HxFunctionDecl>();
		function add(name:String, body:Array<HxStmt>):HxFunctionDecl {
			final fn = new HxFunctionDecl(name, Public, false, [], "Void", body.concat([SReturnVoid(HxPos.unknown())]), "");
			methods.set(name, fn);
			return fn;
		}
		final factory = add("factoryChains", factoryBody());
		final parse = add("parseChains", parseBody());
		final local = add("localPropertyFlow", localFlowBody());
		final complete = add("completeCreate", factoryBody().concat(parseBody()).concat(localFlowBody()));
		final owner = new HxClassDecl("TestXML", false, [factory, parse, local, complete], [], "Test");
		final test = new HxClassDecl("Test", false, [], []);
		final xmlFunctions = [
			new HxFunctionDecl("parse", Public, true, [new HxFunctionArg("value", "String", NoDefault, false, false)], "Xml", [], "")
		];
		for (name in [
			"createElement",
			"createPCData",
			"createCData",
			"createComment",
			"createDocType",
			"createProcessingInstruction"
		])
			xmlFunctions.push(new HxFunctionDecl(name, Public, true, [new HxFunctionArg("value", "String", NoDefault, false, false)], "Xml", [], ""));
		xmlFunctions.push(new HxFunctionDecl("createDocument", Public, true, [], "Xml", [], ""));
		xmlFunctions.push(new HxFunctionDecl("firstChild", Public, false, [], "Xml", [], ""));
		xmlFunctions.push(new HxFunctionDecl("toString", Public, false, [], "String", [], ""));
		final xml = new HxClassDecl("Xml", false, xmlFunctions, [new HxFieldDecl("nodeValue", Public, false, "String", null)]);
		final propertyNode = new HxClassDecl("PropertyNode", false, [
			new HxFunctionDecl("get_prop", Public, false, [], "Int", [SReturn(EInt(7), HxPos.unknown())], "")
		], [
			new HxFieldDecl("prop", Public, false, "Int", null, null, null, null, false, "get", "null")
		]);
		final stringPropertyNode = new HxClassDecl("StringPropertyNode", false, [
			new HxFunctionDecl("get_label", Public, false, [], "String", [SReturn(EString("property label"), HxPos.unknown())], "")
		], [
			new HxFieldDecl("label", Public, false, "String", null, null, null, null, false, "get", "null")
		]);
		final otherFactory = new HxClassDecl("OtherFactory", false, [
			new HxFunctionDecl("create", Public, true, [new HxFunctionArg("value", "String", NoDefault, false, false)], "OtherFactory", [], ""),
			new HxFunctionDecl("toString", Public, false, [], "String", [], "")
		]);
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		final all = [owner, test, xml, propertyNode, stringPropertyNode, otherFactory];
		for (cls in all) {
			final name = HxClassDecl.getName(cls);
			names.set(name, true);
			classes.set(name, cls);
		}
		final lookup = {names: names, byName: classes, all: all};
		return {
			owner: owner,
			lookup: lookup,
			methods: methods,
			scope: @:privateAccess backend.cpp.CppTargetCore.renderScope(owner, lookup, "void")
		};
	}

	static function render(sample:CppXmlCreateRenderFixture, name:String):String {
		@:privateAccess backend.cpp.CppTargetCore.functionScopePrepCache = new StringMap();
		return @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(sample.methods.get(name), sample.owner, sample.lookup).join("\n");
	}

	static function parseValueExpr():HxExpr {
		return EField(ECall(EField(xmlCall("parse", [EString("<!--leaf note-->")]), "firstChild"), []), "nodeValue");
	}

	static function renderOldNodeValuePath(receiver:HxExpr, scope:backend.cpp.CppRenderScope):String {
		final staticEnum = @:privateAccess backend.cpp.CppTargetCore.staticEnumMethodValueExpr(receiver, "nodeValue", scope);
		if (staticEnum != null)
			return staticEnum;
		final staticField = @:privateAccess backend.cpp.CppTargetCore.staticFieldExpr(receiver, "nodeValue", scope);
		if (staticField != null)
			return staticField;
		final fieldExpr = EField(receiver, "nodeValue");
		final classReference = @:privateAccess backend.cpp.CppTargetCore.classReferenceValueExpr(fieldExpr, scope);
		if (classReference != null)
			return classReference;
		final property = @:privateAccess backend.cpp.CppTargetCore.typedPropertyGetReadExpr(receiver, "nodeValue", scope);
		if (property != null)
			return property;
		final json = @:privateAccess backend.cpp.CppTargetCore.jsonAnyFieldReadExpr(receiver, "nodeValue", scope);
		if (json != null)
			return json;
		return "("
			+ @:privateAccess backend.cpp.CppTargetCore.renderExpr(receiver, scope)
			+ @:privateAccess backend.cpp.CppTargetCore.fieldAccessOp(receiver, scope)
			+ "nodeValue)";
	}

	/** Model the former general String path for comparison with the plain-field shortcut. **/
	static function comparableArgWithoutKnownPlainFieldShortcut(arg:HxExpr, argType:String, otherType:String, scope:backend.cpp.CppRenderScope):String {
		if (argType == "std::string") {
			final directSplitJoinConcat = @:privateAccess backend.cpp.CppTargetCore.directTypedLocalERegSplitJoinConcatExpr(arg, scope);
			if (directSplitJoinConcat != null)
				return directSplitJoinConcat;
			return switch (arg) {
				case ECall(_, _):
					@:privateAccess backend.cpp.CppTargetCore.renderExpr(arg, scope);
				case _ if (@:privateAccess backend.cpp.CppTargetCore.isEqStringArgExpr(arg, argType, scope)):
					@:privateAccess backend.cpp.CppTargetCore.stringExpr(arg, scope);
				case _:
					@:privateAccess backend.cpp.CppTargetCore.eqComparableArgExpr(arg, argType, otherType, scope);
			};
		}
		return @:privateAccess backend.cpp.CppTargetCore.eqComparableArgExpr(arg, argType, otherType, scope);
	}

	/** Render benchmark equality arguments as they ran before the plain-field shortcut. **/
	static function renderEqCallArgsWithoutKnownPlainFieldShortcut(args:Array<HxExpr>, scope:backend.cpp.CppRenderScope):Array<String> {
		final out = new Array<String>();
		final firstOptionalStringCode = @:privateAccess backend.cpp.CppTargetCore.stringCodeAccessOptionalExpr(args[0], scope);
		final secondOptionalStringCode = @:privateAccess backend.cpp.CppTargetCore.stringCodeAccessOptionalExpr(args[1], scope);
		if (firstOptionalStringCode != null && @:privateAccess backend.cpp.CppTargetCore.isNullExpr(args[1])) {
			out.push(firstOptionalStringCode);
			out.push("std::optional<int>{}");
			for (i in 2...args.length)
				out.push(@:privateAccess backend.cpp.CppTargetCore.renderExpr(args[i], scope));
			return out;
		}
		if (secondOptionalStringCode != null && @:privateAccess backend.cpp.CppTargetCore.isNullExpr(args[0])) {
			out.push("std::optional<int>{}");
			out.push(secondOptionalStringCode);
			for (i in 2...args.length)
				out.push(@:privateAccess backend.cpp.CppTargetCore.renderExpr(args[i], scope));
			return out;
		}
		final firstType = @:privateAccess backend.cpp.CppTargetCore.inferExprCppType(args[0], scope);
		final secondType = @:privateAccess backend.cpp.CppTargetCore.inferExprCppType(args[1], scope);
		out.push(comparableArgWithoutKnownPlainFieldShortcut(args[0], firstType, secondType, scope));
		out.push(comparableArgWithoutKnownPlainFieldShortcut(args[1], secondType, firstType, scope));
		for (i in 2...args.length)
			out.push(@:privateAccess backend.cpp.CppTargetCore.renderExpr(args[i], scope));
		return out;
	}

	/** Return the exact Xml factory call inside a zero-argument toString call. **/
	static function directXmlFactoryToStringReceiver(expr:HxExpr, scope:backend.cpp.CppRenderScope):Null<HxExpr> {
		return switch (expr) {
			case ECall(EField(factoryCall = ECall(EField(EIdent("Xml"), factoryMethod), factoryArgs), "toString"),
				outerArgs): final arityMatches = switch (factoryMethod) {
					case "createDocument":
						factoryArgs.length == 0;
					case "createElement" | "createPCData" | "createCData" | "createComment" | "createDocType" | "createProcessingInstruction":
						factoryArgs.length == 1;
					case _:
						false;
				}; outerArgs.length == 0 && arityMatches && ! @:privateAccess backend.cpp.CppTargetCore.exprNameHasLocalStorage("Xml",
					scope) ? factoryCall : null;
			case _:
				null;
		};
	}

	/** Model direct rendering after the exact Xml factory/toString shape is known. **/
	static function directXmlFactoryToStringExpr(expr:HxExpr, scope:backend.cpp.CppRenderScope):Null<String> {
		final receiver = directXmlFactoryToStringReceiver(expr, scope);
		return receiver == null ? null : @:privateAccess backend.cpp.CppTargetCore.renderExpr(receiver, scope) + "->toString()";
	}

	/** Model equality rendering when type inference and expression rendering share the exact Xml factory fact. **/
	static function renderEqCallArgsWithDirectXmlFactoryToString(args:Array<HxExpr>, scope:backend.cpp.CppRenderScope):Array<String> {
		final firstOptionalStringCode = @:privateAccess backend.cpp.CppTargetCore.stringCodeAccessOptionalExpr(args[0], scope);
		final secondOptionalStringCode = @:privateAccess backend.cpp.CppTargetCore.stringCodeAccessOptionalExpr(args[1], scope);
		if ((firstOptionalStringCode != null && @:privateAccess backend.cpp.CppTargetCore.isNullExpr(args[1]))
			|| (secondOptionalStringCode != null && @:privateAccess backend.cpp.CppTargetCore.isNullExpr(args[0])))
			return @:privateAccess backend.cpp.CppTargetCore.renderEqCallArgs(args, scope);
		final directFirst = directXmlFactoryToStringExpr(args[0], scope);
		final directSecond = directXmlFactoryToStringExpr(args[1], scope);
		if (directFirst == null && directSecond == null)
			return @:privateAccess backend.cpp.CppTargetCore.renderEqCallArgs(args, scope);
		final firstType = directFirst == null ? @:privateAccess backend.cpp.CppTargetCore.inferExprCppType(args[0], scope) : "std::string";
		final secondType = directSecond == null ? @:privateAccess backend.cpp.CppTargetCore.inferExprCppType(args[1], scope) : "std::string";
		final out = [
			directFirst == null ? @:privateAccess backend.cpp.CppTargetCore.eqComparableArgExpr(args[0], firstType, secondType, scope) : directFirst,
			directSecond == null ? @:privateAccess backend.cpp.CppTargetCore.eqComparableArgExpr(args[1], secondType, firstType, scope) : directSecond
		];
		for (i in 2...args.length)
			out.push(@:privateAccess backend.cpp.CppTargetCore.renderExpr(args[i], scope));
		return out;
	}

	static function main():Void {
		final sample = fixture();
		final factoryOutput = render(sample, "factoryChains");
		assertTrue(factoryOutput.indexOf("Xml::createComment(std::string(\"bench note\"))->toString()") >= 0,
			"XML factory chains should retain direct Xml factory and instance toString calls");
		final parseOutput = render(sample, "parseChains");
		assertTrue(parseOutput.indexOf("Xml::parse(std::string(\"<!--parsed note-->\"))->firstChild()->nodeValue") >= 0,
			"XML parse chains should retain firstChild and nodeValue access");
		final localOutput = render(sample, "localPropertyFlow");
		assertTrue(localOutput.indexOf("(node->nodeValue) = \"updated note\"") >= 0, "XML local property flow should retain nodeValue assignment");
		final completeOutput = render(sample, "completeCreate");
		assertTrue(completeOutput.indexOf("return;") >= 0, "complete XML creation rendering should retain its explicit return");
		sample.scope.localTypes.set("propertyNode", "std::shared_ptr<PropertyNode>");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(EField(EIdent("propertyNode"), "prop"), sample.scope) == "propertyNode->get_prop()",
			"plain-field rendering must not bypass declared property getters");
		sample.scope.localNames.set("stringPropertyNode", "stringPropertyNode");
		sample.scope.localTypes.set("stringPropertyNode", "std::shared_ptr<StringPropertyNode>");
		sample.scope.localTypeHints.set("stringPropertyNode", "StringPropertyNode");
		final stringPropertyEqualityArgs = [EField(EIdent("stringPropertyNode"), "label"), EString("property label")];
		final stringPropertyEqualityOutput = @:privateAccess
			backend.cpp.CppTargetCore.renderEqCallArgs(stringPropertyEqualityArgs, sample.scope).join(", ");
		assertTrue(stringPropertyEqualityOutput == 'stringPropertyNode->get_label(), std::string("property label")',
			"String equality rendering must not bypass a declared property getter, got " + stringPropertyEqualityOutput);
		assertTrue(renderEqCallArgsWithoutKnownPlainFieldShortcut(stringPropertyEqualityArgs, sample.scope).join(", ") == stringPropertyEqualityOutput,
			"plain-field shortcut must keep String property equality on the former getter path");
		sample.scope.localTypes.set("erased", "std::any");
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.renderExpr(EField(EIdent("erased"), "value"), sample.scope) == "__hxhx_json_any_field(erased, std::string(\"value\"))",
			"plain-field rendering must not bypass erased JSON field reads");
		for (name in ["node", "text", "dynamicNode"])
			sample.scope.localNames.set(name, name);
		sample.scope.localTypes.set("node", "std::shared_ptr<Xml>");
		sample.scope.localTypeHints.set("node", "Xml");
		sample.scope.localTypes.set("text", "std::string");
		sample.scope.localTypeHints.set("text", "String");
		sample.scope.localTypes.set("dynamicNode", "std::any");
		sample.scope.localTypeHints.set("dynamicNode", "Dynamic");

		final calls = envInt("HXHX_CPP_XML_CREATE_RENDER_BENCH_CALLS", DEFAULT_CALLS);
		var sink = 0;
		final factoryCall = xmlCall("createComment", [EString("leaf note")]);
		final factoryToString = toStringCall(factoryCall);
		final factoryEqualityArgs = [factoryToString, EString("<!--leaf note-->")];
		final factoryEqualityStmt = eq(factoryEqualityArgs[0], factoryEqualityArgs[1]);
		final documentFactoryEqualityArgs = [toStringCall(xmlCall("createDocument", [])), EString("")];
		final wrongArityFactoryEqualityArgs = [toStringCall(xmlCall("createComment", [])), EString("")];
		final localToString = toStringCall(EIdent("node"));
		final localToStringEqualityArgs = [localToString, EString("<!--leaf note-->")];
		final localEqualityArgs = [EIdent("text"), EString("leaf note")];
		final otherFactoryToString = toStringCall(ECall(EField(EIdent("OtherFactory"), "create"), [EString("other")]));
		final otherFactoryEqualityArgs = [otherFactoryToString, EString("other")];
		final dynamicToStringEqualityArgs = [toStringCall(EIdent("dynamicNode")), EString("dynamic")];
		final parseCall = xmlCall("parse", [EString("<!--leaf note-->")]);
		final firstChildCall = ECall(EField(parseCall, "firstChild"), []);
		final nodeValueAccess = parseValueExpr();
		final parseEqualityArgs = [nodeValueAccess, EString("leaf note")];
		final equalityStmt = eq(parseEqualityArgs[0], parseEqualityArgs[1]);
		final factoryCallOutput = @:privateAccess backend.cpp.CppTargetCore.renderExpr(factoryCall, sample.scope);
		final factoryToStringOutput = @:privateAccess backend.cpp.CppTargetCore.renderExpr(factoryToString, sample.scope);
		final localToStringOutput = @:privateAccess backend.cpp.CppTargetCore.renderExpr(localToString, sample.scope);
		final factoryEqualityOutput = @:privateAccess backend.cpp.CppTargetCore.renderEqCallArgs(factoryEqualityArgs, sample.scope).join(", ");
		final parseEqualityOutput = @:privateAccess backend.cpp.CppTargetCore.renderEqCallArgs(parseEqualityArgs, sample.scope).join(", ");
		final localEqualityOutput = @:privateAccess backend.cpp.CppTargetCore.renderEqCallArgs(localEqualityArgs, sample.scope).join(", ");
		final localToStringEqualityOutput = @:privateAccess
			backend.cpp.CppTargetCore.renderEqCallArgs(localToStringEqualityArgs, sample.scope).join(", ");
		final otherFactoryEqualityOutput = @:privateAccess
			backend.cpp.CppTargetCore.renderEqCallArgs(otherFactoryEqualityArgs, sample.scope).join(", ");
		final dynamicToStringEqualityOutput = @:privateAccess
			backend.cpp.CppTargetCore.renderEqCallArgs(dynamicToStringEqualityArgs, sample.scope).join(", ");
		final directFactoryEqualityOutput = renderEqCallArgsWithDirectXmlFactoryToString(factoryEqualityArgs, sample.scope).join(", ");
		final generalFactoryEqualityOutput = renderEqCallArgsWithoutKnownPlainFieldShortcut(factoryEqualityArgs, sample.scope).join(", ");
		final generalParseEqualityOutput = renderEqCallArgsWithoutKnownPlainFieldShortcut(parseEqualityArgs, sample.scope).join(", ");
		final generalLocalEqualityOutput = renderEqCallArgsWithoutKnownPlainFieldShortcut(localEqualityArgs, sample.scope).join(", ");
		assertTrue(factoryCallOutput == 'Xml::createComment(std::string("leaf note"))',
			"factory leaf should retain the exact Xml static call, got " + factoryCallOutput);
		assertTrue(factoryToStringOutput == factoryCallOutput + "->toString()",
			"factory toString leaf should retain the exact instance call, got " + factoryToStringOutput);
		assertTrue(localToStringOutput == "node->toString()", "typed-local toString control should remain flat, got " + localToStringOutput);
		assertTrue(factoryEqualityOutput == factoryToStringOutput + ', std::string("<!--leaf note-->")',
			"factory equality arguments should retain exact String adaptation, got " + factoryEqualityOutput);
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.renderEqCallArgs(documentFactoryEqualityArgs, sample.scope)
				.join(", ") == 'Xml::createDocument()->toString(), std::string("")',
			"zero-argument Xml.createDocument should use the same direct equality rendering");
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.renderEqCallArgs(wrongArityFactoryEqualityArgs, sample.scope)
				.join(", ") == renderEqCallArgsWithoutKnownPlainFieldShortcut(wrongArityFactoryEqualityArgs, sample.scope)
				.join(", "),
			"an Xml factory call with the wrong arity must stay on the general equality path");
		sample.scope.localNames.set("Xml", "Xml");
		sample.scope.localTypes.set("Xml", "std::shared_ptr<OtherFactory>");
		final shadowedFactoryEqualityOutput = @:privateAccess
			backend.cpp.CppTargetCore.renderEqCallArgs(factoryEqualityArgs, sample.scope).join(", ");
		final shadowedFactoryGeneralOutput = renderEqCallArgsWithoutKnownPlainFieldShortcut(factoryEqualityArgs, sample.scope).join(", ");
		assertTrue(shadowedFactoryEqualityOutput == shadowedFactoryGeneralOutput,
			"a local named Xml must keep factory-shaped calls on the general equality path");
		sample.scope.localNames.remove("Xml");
		sample.scope.localTypes.remove("Xml");
		assertTrue(parseEqualityOutput == '(Xml::parse(std::string("<!--leaf note-->"))->firstChild()->nodeValue), std::string("leaf note")',
			"parse equality arguments should retain the exact chain, got " + parseEqualityOutput);
		assertTrue(localEqualityOutput == 'std::string(text), std::string("leaf note")',
			"typed-local equality control should retain ordinary String adaptation, got " + localEqualityOutput);
		assertTrue(localToStringEqualityOutput == 'node->toString(), std::string("<!--leaf note-->")',
			"typed-local toString equality should retain its instance call, got " + localToStringEqualityOutput);
		assertTrue(otherFactoryEqualityOutput == 'std::make_shared<OtherFactory>("other")->toString(), std::string("other")',
			"unrelated factory equality should retain its instance call, got " + otherFactoryEqualityOutput);
		assertTrue(directFactoryEqualityOutput == factoryEqualityOutput,
			"direct Xml factory/toString equality must preserve exact output, got " + directFactoryEqualityOutput);
		assertTrue(renderEqCallArgsWithDirectXmlFactoryToString(localToStringEqualityArgs, sample.scope).join(", ") == localToStringEqualityOutput,
			"direct Xml factory/toString candidate must decline a typed-local receiver");
		assertTrue(renderEqCallArgsWithDirectXmlFactoryToString(otherFactoryEqualityArgs, sample.scope).join(", ") == otherFactoryEqualityOutput,
			"direct Xml factory/toString candidate must decline an unrelated factory");
		assertTrue(renderEqCallArgsWithDirectXmlFactoryToString(dynamicToStringEqualityArgs, sample.scope).join(", ") == dynamicToStringEqualityOutput,
			"direct Xml factory/toString candidate must decline a Dynamic receiver");
		assertTrue(generalFactoryEqualityOutput == factoryEqualityOutput,
			"plain-field shortcut must not change factory equality output, got " + generalFactoryEqualityOutput);
		assertTrue(generalParseEqualityOutput == parseEqualityOutput,
			"plain-field shortcut must not change parse equality output, got " + generalParseEqualityOutput);
		assertTrue(generalLocalEqualityOutput == localEqualityOutput,
			"plain-field shortcut must not change typed-local equality output, got " + generalLocalEqualityOutput);

		final factoryStaticReceiverSeconds = elapsed("factory_static_receiver", calls, () -> {
			final value = @:privateAccess backend.cpp.CppTargetCore.staticReceiverClassName(EIdent("Xml"), sample.scope);
			sink += value == null ? 0 : value.length;
		});
		final factoryReceiverTypeSeconds = elapsed("factory_receiver_type", calls,
			() -> sink += @:privateAccess backend.cpp.CppTargetCore.exprCppType(EIdent("Xml"), sample.scope).length);
		final factoryArgRenderSeconds = elapsed("factory_arg_render", calls, () -> sink += @:privateAccess
			backend.cpp.CppTargetCore.renderClassMethodCallArgs("Xml", "createComment", true, [EString("leaf note")], sample.scope).join(", ").length);
		final factoryCallSeconds = elapsed("factory_call", calls,
			() -> sink += @:privateAccess backend.cpp.CppTargetCore.renderExpr(factoryCall, sample.scope).length);
		final factoryResultTypeSeconds = elapsed("factory_result_type", calls,
			() -> sink += @:privateAccess backend.cpp.CppTargetCore.exprCppType(factoryCall, sample.scope).length);
		final localToStringSeconds = elapsed("local_to_string", calls,
			() -> sink += @:privateAccess backend.cpp.CppTargetCore.renderExpr(localToString, sample.scope).length);
		final factoryToStringSeconds = elapsed("factory_to_string", calls,
			() -> sink += @:privateAccess backend.cpp.CppTargetCore.renderExpr(factoryToString, sample.scope).length);
		final factoryToStringShapeSeconds = elapsed("factory_to_string_shape", calls, () -> {
			final value = directXmlFactoryToStringReceiver(factoryToString, sample.scope);
			sink += value == null ? 0 : 1;
		});
		final factoryToStringDirectSeconds = elapsed("factory_to_string_direct", calls, () -> {
			final value = directXmlFactoryToStringExpr(factoryToString, sample.scope);
			sink += value == null ? 0 : value.length;
		});
		final factoryEqualityInferSeconds = elapsed("factory_equality_infer", calls,
			() -> sink += @:privateAccess backend.cpp.CppTargetCore.inferExprCppType(factoryToString, sample.scope).length);
		final factoryEqualityComparableSeconds = elapsed("factory_equality_comparable", calls, () -> sink += @:privateAccess
			backend.cpp.CppTargetCore.eqComparableArgExpr(factoryToString, "std::string", "std::string", sample.scope).length);
		final factoryEqualityArgsSeconds = elapsed("factory_equality_args", calls, () -> sink += @:privateAccess
			backend.cpp.CppTargetCore.renderEqCallArgs(factoryEqualityArgs, sample.scope).join(", ").length);
		final factoryEqualityDirectSeconds = elapsed("factory_equality_direct", calls,
			() -> sink += renderEqCallArgsWithDirectXmlFactoryToString(factoryEqualityArgs, sample.scope).join(", ").length);
		final factoryEqualityGeneralSeconds = elapsed("factory_equality_general", calls,
			() -> sink += renderEqCallArgsWithoutKnownPlainFieldShortcut(factoryEqualityArgs, sample.scope).join(", ").length);
		final factoryEqualityCallSeconds = elapsed("factory_equality_call", calls, () -> sink += @:privateAccess
			backend.cpp.CppTargetCore.directCallExpr("eq", factoryEqualityArgs, sample.scope).length);
		final factoryEqualityStmtSeconds = elapsed("factory_equality_stmt", calls, () -> sink += @:privateAccess
			backend.cpp.CppTargetCore.renderStmt(factoryEqualityStmt, "    ", sample.scope).join("\n").length);
		final localEqualityArgsSeconds = elapsed("local_equality_args", calls, () -> sink += @:privateAccess
			backend.cpp.CppTargetCore.renderEqCallArgs(localEqualityArgs, sample.scope).join(", ").length);
		final localEqualityGeneralSeconds = elapsed("local_equality_general", calls,
			() -> sink += renderEqCallArgsWithoutKnownPlainFieldShortcut(localEqualityArgs, sample.scope).join(", ").length);
		final localEqualityCallSeconds = elapsed("local_equality_call", calls, () -> sink += @:privateAccess
			backend.cpp.CppTargetCore.directCallExpr("eq", localEqualityArgs, sample.scope).length);
		final localToStringEqualityArgsSeconds = elapsed("local_to_string_equality_args", calls, () -> sink += @:privateAccess
			backend.cpp.CppTargetCore.renderEqCallArgs(localToStringEqualityArgs, sample.scope).join(", ").length);
		final localToStringEqualityDirectSeconds = elapsed("local_to_string_equality_direct", calls,
			() -> sink += renderEqCallArgsWithDirectXmlFactoryToString(localToStringEqualityArgs, sample.scope).join(", ").length);
		final otherFactoryEqualityArgsSeconds = elapsed("other_factory_equality_args", calls, () -> sink += @:privateAccess
			backend.cpp.CppTargetCore.renderEqCallArgs(otherFactoryEqualityArgs, sample.scope).join(", ").length);
		final otherFactoryEqualityDirectSeconds = elapsed("other_factory_equality_direct", calls,
			() -> sink += renderEqCallArgsWithDirectXmlFactoryToString(otherFactoryEqualityArgs, sample.scope).join(", ").length);
		final dynamicToStringEqualityArgsSeconds = elapsed("dynamic_to_string_equality_args", calls, () -> sink += @:privateAccess
			backend.cpp.CppTargetCore.renderEqCallArgs(dynamicToStringEqualityArgs, sample.scope).join(", ").length);
		final dynamicToStringEqualityDirectSeconds = elapsed("dynamic_to_string_equality_direct", calls,
			() -> sink += renderEqCallArgsWithDirectXmlFactoryToString(dynamicToStringEqualityArgs, sample.scope).join(", ").length);
		final plainFieldFastSeconds = elapsed("plain_field_fast", calls, () -> {
			final value = @:privateAccess backend.cpp.CppTargetCore.knownPlainInstanceFieldReadExpr(nodeValueAccess, sample.scope);
			sink += value == null ? 0 : value.length;
		});
		final oldNodeValueAccessSeconds = elapsed("old_node_value_access", calls, () -> sink += renderOldNodeValuePath(firstChildCall, sample.scope).length);
		final receiverTypeSeconds = elapsed("receiver_type", calls,
			() -> sink += @:privateAccess backend.cpp.CppTargetCore.exprCppType(firstChildCall, sample.scope).length);
		final staticEnumGuardSeconds = elapsed("static_enum_guard", calls, () -> {
			final value = @:privateAccess backend.cpp.CppTargetCore.staticEnumMethodValueExpr(firstChildCall, "nodeValue", sample.scope);
			sink += value == null ? 0 : value.length;
		});
		final staticFieldGuardSeconds = elapsed("static_field_guard", calls, () -> {
			final value = @:privateAccess backend.cpp.CppTargetCore.staticFieldExpr(firstChildCall, "nodeValue", sample.scope);
			sink += value == null ? 0 : value.length;
		});
		final classReferenceGuardSeconds = elapsed("class_reference_guard", calls, () -> {
			final value = @:privateAccess backend.cpp.CppTargetCore.classReferenceValueExpr(nodeValueAccess, sample.scope);
			sink += value == null ? 0 : value.length;
		});
		final propertyGuardSeconds = elapsed("property_guard", calls, () -> {
			final value = @:privateAccess backend.cpp.CppTargetCore.typedPropertyGetReadExpr(firstChildCall, "nodeValue", sample.scope);
			sink += value == null ? 0 : value.length;
		});
		final jsonGuardSeconds = elapsed("json_guard", calls, () -> {
			final value = @:privateAccess backend.cpp.CppTargetCore.jsonAnyFieldReadExpr(firstChildCall, "nodeValue", sample.scope);
			sink += value == null ? 0 : value.length;
		});
		final receiverRenderSeconds = elapsed("receiver_render", calls,
			() -> sink += @:privateAccess backend.cpp.CppTargetCore.renderExpr(firstChildCall, sample.scope).length);
		final accessOpSeconds = elapsed("access_op", calls,
			() -> sink += @:privateAccess backend.cpp.CppTargetCore.fieldAccessOp(firstChildCall, sample.scope).length);
		final parseCallSeconds = elapsed("parse_call", calls,
			() -> sink += @:privateAccess backend.cpp.CppTargetCore.renderExpr(parseCall, sample.scope).length);
		final firstChildCallSeconds = elapsed("first_child_call", calls,
			() -> sink += @:privateAccess backend.cpp.CppTargetCore.renderExpr(firstChildCall, sample.scope).length);
		final nodeValueAccessSeconds = elapsed("node_value_access", calls,
			() -> sink += @:privateAccess backend.cpp.CppTargetCore.renderExpr(nodeValueAccess, sample.scope).length);
		final parseEqualityInferSeconds = elapsed("parse_equality_infer", calls,
			() -> sink += @:privateAccess backend.cpp.CppTargetCore.inferExprCppType(nodeValueAccess, sample.scope).length);
		final parseEqualityComparableSeconds = elapsed("parse_equality_comparable", calls, () -> sink += @:privateAccess
			backend.cpp.CppTargetCore.eqComparableArgExpr(nodeValueAccess, "std::string", "std::string", sample.scope).length);
		final parseEqualityArgsSeconds = elapsed("parse_equality_args", calls, () -> sink += @:privateAccess
			backend.cpp.CppTargetCore.renderEqCallArgs(parseEqualityArgs, sample.scope).join(", ").length);
		final parseEqualityGeneralSeconds = elapsed("parse_equality_general", calls,
			() -> sink += renderEqCallArgsWithoutKnownPlainFieldShortcut(parseEqualityArgs, sample.scope).join(", ").length);
		final parseEqualityCallSeconds = elapsed("parse_equality_call", calls, () -> sink += @:privateAccess
			backend.cpp.CppTargetCore.directCallExpr("eq", parseEqualityArgs, sample.scope).length);
		final equalityStmtSeconds = elapsed("equality_stmt", calls,
			() -> sink += @:privateAccess backend.cpp.CppTargetCore.renderStmt(equalityStmt, "    ", sample.scope).join("\n").length);
		final factorySeconds = elapsed("factory_chains", calls, () -> sink += render(sample, "factoryChains").length);
		final parseSeconds = elapsed("parse_chains", calls, () -> sink += render(sample, "parseChains").length);
		final localSeconds = elapsed("local_property_flow", calls, () -> sink += render(sample, "localPropertyFlow").length);
		final completeSeconds = elapsed("complete", calls, () -> sink += render(sample, "completeCreate").length);
		assertTrue(sink > 0, "XML render attribution should retain generated output");
		Sys.println("cpp_xml_create_render_bench_calls=" + calls);
		Sys.println("factory_static_receiver_seconds=" + factoryStaticReceiverSeconds);
		Sys.println("factory_receiver_type_seconds=" + factoryReceiverTypeSeconds);
		Sys.println("factory_arg_render_seconds=" + factoryArgRenderSeconds);
		Sys.println("factory_call_seconds=" + factoryCallSeconds);
		Sys.println("factory_result_type_seconds=" + factoryResultTypeSeconds);
		Sys.println("local_to_string_seconds=" + localToStringSeconds);
		Sys.println("factory_to_string_seconds=" + factoryToStringSeconds);
		Sys.println("factory_to_string_shape_seconds=" + factoryToStringShapeSeconds);
		Sys.println("factory_to_string_direct_seconds=" + factoryToStringDirectSeconds);
		Sys.println("factory_equality_infer_seconds=" + factoryEqualityInferSeconds);
		Sys.println("factory_equality_comparable_seconds=" + factoryEqualityComparableSeconds);
		Sys.println("factory_equality_args_seconds=" + factoryEqualityArgsSeconds);
		Sys.println("factory_equality_direct_seconds=" + factoryEqualityDirectSeconds);
		Sys.println("factory_equality_general_seconds=" + factoryEqualityGeneralSeconds);
		Sys.println("factory_equality_call_seconds=" + factoryEqualityCallSeconds);
		Sys.println("factory_equality_stmt_seconds=" + factoryEqualityStmtSeconds);
		Sys.println("local_equality_args_seconds=" + localEqualityArgsSeconds);
		Sys.println("local_equality_general_seconds=" + localEqualityGeneralSeconds);
		Sys.println("local_equality_call_seconds=" + localEqualityCallSeconds);
		Sys.println("local_to_string_equality_args_seconds=" + localToStringEqualityArgsSeconds);
		Sys.println("local_to_string_equality_direct_seconds=" + localToStringEqualityDirectSeconds);
		Sys.println("other_factory_equality_args_seconds=" + otherFactoryEqualityArgsSeconds);
		Sys.println("other_factory_equality_direct_seconds=" + otherFactoryEqualityDirectSeconds);
		Sys.println("dynamic_to_string_equality_args_seconds=" + dynamicToStringEqualityArgsSeconds);
		Sys.println("dynamic_to_string_equality_direct_seconds=" + dynamicToStringEqualityDirectSeconds);
		Sys.println("plain_field_fast_seconds=" + plainFieldFastSeconds);
		Sys.println("old_node_value_access_seconds=" + oldNodeValueAccessSeconds);
		Sys.println("receiver_type_seconds=" + receiverTypeSeconds);
		Sys.println("static_enum_guard_seconds=" + staticEnumGuardSeconds);
		Sys.println("static_field_guard_seconds=" + staticFieldGuardSeconds);
		Sys.println("class_reference_guard_seconds=" + classReferenceGuardSeconds);
		Sys.println("property_guard_seconds=" + propertyGuardSeconds);
		Sys.println("json_guard_seconds=" + jsonGuardSeconds);
		Sys.println("receiver_render_seconds=" + receiverRenderSeconds);
		Sys.println("access_op_seconds=" + accessOpSeconds);
		Sys.println("parse_call_seconds=" + parseCallSeconds);
		Sys.println("first_child_call_seconds=" + firstChildCallSeconds);
		Sys.println("node_value_access_seconds=" + nodeValueAccessSeconds);
		Sys.println("parse_equality_infer_seconds=" + parseEqualityInferSeconds);
		Sys.println("parse_equality_comparable_seconds=" + parseEqualityComparableSeconds);
		Sys.println("parse_equality_args_seconds=" + parseEqualityArgsSeconds);
		Sys.println("parse_equality_general_seconds=" + parseEqualityGeneralSeconds);
		Sys.println("parse_equality_call_seconds=" + parseEqualityCallSeconds);
		Sys.println("equality_stmt_seconds=" + equalityStmtSeconds);
		Sys.println("factory_chains_seconds=" + factorySeconds);
		Sys.println("parse_chains_seconds=" + parseSeconds);
		Sys.println("local_property_flow_seconds=" + localSeconds);
		Sys.println("complete_seconds=" + completeSeconds);
	}
}
