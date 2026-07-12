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
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		final all = [owner, test, xml, propertyNode];
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
		sample.scope.localTypes.set("erased", "std::any");
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.renderExpr(EField(EIdent("erased"), "value"), sample.scope) == "__hxhx_json_any_field(erased, std::string(\"value\"))",
			"plain-field rendering must not bypass erased JSON field reads");

		final calls = envInt("HXHX_CPP_XML_CREATE_RENDER_BENCH_CALLS", DEFAULT_CALLS);
		var sink = 0;
		final parseCall = xmlCall("parse", [EString("<!--leaf note-->")]);
		final firstChildCall = ECall(EField(parseCall, "firstChild"), []);
		final nodeValueAccess = parseValueExpr();
		final equalityStmt = eq(nodeValueAccess, EString("leaf note"));
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
		final equalityStmtSeconds = elapsed("equality_stmt", calls,
			() -> sink += @:privateAccess backend.cpp.CppTargetCore.renderStmt(equalityStmt, "    ", sample.scope).join("\n").length);
		final factorySeconds = elapsed("factory_chains", calls, () -> sink += render(sample, "factoryChains").length);
		final parseSeconds = elapsed("parse_chains", calls, () -> sink += render(sample, "parseChains").length);
		final localSeconds = elapsed("local_property_flow", calls, () -> sink += render(sample, "localPropertyFlow").length);
		final completeSeconds = elapsed("complete", calls, () -> sink += render(sample, "completeCreate").length);
		assertTrue(sink > 0, "XML render attribution should retain generated output");
		Sys.println("cpp_xml_create_render_bench_calls=" + calls);
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
		Sys.println("equality_stmt_seconds=" + equalityStmtSeconds);
		Sys.println("factory_chains_seconds=" + factorySeconds);
		Sys.println("parse_chains_seconds=" + parseSeconds);
		Sys.println("local_property_flow_seconds=" + localSeconds);
		Sys.println("complete_seconds=" + completeSeconds);
	}
}
