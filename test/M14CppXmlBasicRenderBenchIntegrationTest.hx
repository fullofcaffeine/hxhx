import HxDefaultValue.NoDefault;
import HxExpr;
import HxStmt;
import haxe.ds.StringMap;

typedef CppXmlBasicRenderFixture = {
	var owner:HxClassDecl;
	var lookup:backend.cpp.CppClassLookup;
	var methods:StringMap<HxFunctionDecl>;
	var scope:backend.cpp.CppRenderScope;
}

/**
	Repo-owned attribution probe for the small XML operations used together by a
	typical parse-and-inspect method.

	The fixture deliberately uses original XML text and method composition. It
	separates child identity, node-kind comparisons, structural attribute
	iteration, and child field reads, then repeats representative leaves with a
	larger immutable class lookup. This shows whether a slowdown belongs to the
	XML lowering itself or to a whole-program type lookup repeated while rendering.
**/
class M14CppXmlBasicRenderBenchIntegrationTest {
	static inline final DEFAULT_CALLS = 25;
	static inline final DEFAULT_FILLER_CLASSES = 512;

	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
	}

	static function envInt(name:String, fallback:Int):Int {
		final raw = Sys.getEnv(name);
		final parsed = raw == null ? null : Std.parseInt(raw);
		return parsed == null || parsed < 0 ? fallback : parsed;
	}

	static function selected(name:String):Bool {
		final only = Sys.getEnv("HXHX_CPP_XML_BASIC_RENDER_BENCH_ONLY");
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

	static function eq(actual:HxExpr, expected:HxExpr):HxStmt {
		return SExpr(ECall(EIdent("eq"), [actual, expected]), HxPos.unknown());
	}

	static function parseStmt():HxStmt {
		return SVar("node", "Xml", xmlCall("parse", [EString('<bench-root label="value">text<leaf/></bench-root>')]), HxPos.unknown());
	}

	static function rootStmt():HxStmt {
		return SExpr(EBinop("=", EIdent("node"), fieldCall(EIdent("node"), "firstChild", [])), HxPos.unknown());
	}

	static function firstChildIdentityExpr(receiver:HxExpr):HxExpr {
		return EBinop("==", fieldCall(receiver, "firstChild", []), fieldCall(receiver, "firstChild", []));
	}

	static function nodeTypeArgs(receiver:HxExpr, marker:String):Array<HxExpr> {
		return [EField(receiver, "nodeType"), EField(EIdent("Xml"), marker)];
	}

	static function attributeJoinExpr(receiver:HxExpr):HxExpr {
		final iterable = EAnon(["iterator"], [EField(receiver, "attributes")]);
		return fieldCall(ECall(EField(EIdent("Lambda"), "array"), [iterable]), "join", [EString("#")]);
	}

	static function childFieldExpr(receiver:HxExpr, method:String, field:String):HxExpr {
		return EField(fieldCall(receiver, method, []), field);
	}

	static function fixture(fillerCount:Int):CppXmlBasicRenderFixture {
		final methods = new StringMap<HxFunctionDecl>();
		function add(name:String, body:Array<HxStmt>):HxFunctionDecl {
			final fn = new HxFunctionDecl(name, Public, false, [], "Void", body.concat([SReturnVoid(HxPos.unknown())]), "");
			methods.set(name, fn);
			return fn;
		}

		final parseOnly = add("parseOnly", [parseStmt()]);
		final identity = add("childIdentity", [
			parseStmt(),
			SExpr(ECall(EIdent("t"), [firstChildIdentityExpr(EIdent("node"))]), HxPos.unknown())
		]);
		final nodeTypes = add("nodeKinds", [
			parseStmt(),
			eq(EField(EIdent("node"), "nodeType"), EField(EIdent("Xml"), "Document")),
			rootStmt(),
			eq(EField(EIdent("node"), "nodeType"), EField(EIdent("Xml"), "Element"))
		]);
		final attributes = add("attributeIteration", [
			parseStmt(),
			rootStmt(),
			eq(attributeJoinExpr(EIdent("node")), EString("label")),
			SExpr(fieldCall(EIdent("node"), "remove", [EString("label")]), HxPos.unknown()),
			eq(attributeJoinExpr(EIdent("node")), EString(""))
		]);
		final childFields = add("childFields", [
			parseStmt(),
			rootStmt(),
			eq(childFieldExpr(EIdent("node"), "firstChild", "nodeValue"), EString("text")),
			eq(childFieldExpr(EIdent("node"), "firstElement", "nodeName"), EString("leaf"))
		]);
		final complete = add("completeBasic", [
			parseStmt(),
			SExpr(ECall(EIdent("t"), [firstChildIdentityExpr(EIdent("node"))]), HxPos.unknown()),
			eq(EField(EIdent("node"), "nodeType"), EField(EIdent("Xml"), "Document")),
			rootStmt(),
			eq(EField(EIdent("node"), "nodeType"), EField(EIdent("Xml"), "Element")),
			eq(attributeJoinExpr(EIdent("node")), EString("label")),
			eq(childFieldExpr(EIdent("node"), "firstChild", "nodeValue"), EString("text")),
			eq(childFieldExpr(EIdent("node"), "firstElement", "nodeName"), EString("leaf"))
		]);

		final owner = new HxClassDecl("XmlBasicBenchOwner", false, [parseOnly, identity, nodeTypes, attributes, childFields, complete], [], "Test");
		final test = new HxClassDecl("Test", false, [
			new HxFunctionDecl("t", Public, false, [new HxFunctionArg("value", "Bool", NoDefault, false, false)], "Void", [], ""),
			new HxFunctionDecl("eq", Public, false, [
				new HxFunctionArg("actual", "Dynamic", NoDefault, false, false),
				new HxFunctionArg("expected", "Dynamic", NoDefault, false, false)
			], "Void", [], "")
		], []);
		final xmlType = new HxClassDecl("XmlType", false, [], [
			new HxFieldDecl("Element", Public, true, "Dynamic", EInt(0)),
			new HxFieldDecl("Document", Public, true, "Dynamic", EInt(6))
		], "", ["__hxhx_abstract"]);
		final xml = new HxClassDecl("Xml", false, [
			new HxFunctionDecl("parse", Public, true, [new HxFunctionArg("value", "String", NoDefault, false, false)], "Xml", [], ""),
			new HxFunctionDecl("firstChild", Public, false, [], "Xml", [], ""),
			new HxFunctionDecl("firstElement", Public, false, [], "Xml", [], ""),
			new HxFunctionDecl("attributes", Public, false, [], "Iterator<String>", [], ""),
			new HxFunctionDecl("remove", Public, false, [new HxFunctionArg("name", "String", NoDefault, false, false)], "Void", [], "")
		], [
			new HxFieldDecl("Element", Public, true, "Dynamic", EField(EIdent("XmlType"), "Element")),
			new HxFieldDecl("Document", Public, true, "Dynamic", EField(EIdent("XmlType"), "Document")),
			new HxFieldDecl("nodeType", Public, false, "XmlType", null),
			new HxFieldDecl("nodeName", Public, false, "String", null),
			new HxFieldDecl("nodeValue", Public, false, "String", null)
		]);
		final lambda = new HxClassDecl("Lambda", false, [], []);
		final otherNode = new HxClassDecl("OtherNode", false, [
			new HxFunctionDecl("firstChild", Public, false, [], "OtherNode", [], ""),
			new HxFunctionDecl("firstElement", Public, false, [], "OtherNode", [], "")
		], [
			new HxFieldDecl("nodeName", Public, false, "String", null),
			new HxFieldDecl("nodeValue", Public, false, "String", null)
		]);
		final otherMarker = new HxClassDecl("OtherMarker", false, [], [new HxFieldDecl("Document", Public, true, "Int", EInt(9))]);

		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		final all = [owner];
		for (i in 0...fillerCount)
			all.push(new HxClassDecl("XmlBasicFiller" + i, false, [], []));
		for (cls in [test, xmlType, xml, lambda, otherNode, otherMarker])
			all.push(cls);
		for (cls in all) {
			final name = HxClassDecl.getName(cls);
			names.set(name, true);
			classes.set(name, cls);
		}
		final lookup = {names: names, byName: classes, all: all};
		final scope = @:privateAccess backend.cpp.CppTargetCore.renderScope(owner, lookup, "void");
		for (entry in [
			{name: "node", cppType: "std::shared_ptr<Xml>", hint: "Xml"},
			{name: "otherNode", cppType: "std::shared_ptr<OtherNode>", hint: "OtherNode"}
		]) {
			scope.localNames.set(entry.name, entry.name);
			scope.localTypes.set(entry.name, entry.cppType);
			scope.localTypeHints.set(entry.name, entry.hint);
		}
		return {
			owner: owner,
			lookup: lookup,
			methods: methods,
			scope: scope
		};
	}

	static function renderMethod(sample:CppXmlBasicRenderFixture, name:String):String {
		sample.scope.functionAnalysisMemo.functionPreparations.clear();
		return @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(sample.methods.get(name), sample.owner, sample.lookup).join("\n");
	}

	static function renderExpr(expr:HxExpr, sample:CppXmlBasicRenderFixture):String {
		return @:privateAccess backend.cpp.CppTargetCore.renderExpr(expr, sample.scope);
	}

	static function renderEqArgs(args:Array<HxExpr>, sample:CppXmlBasicRenderFixture):String {
		return @:privateAccess backend.cpp.CppTargetCore.renderEqCallArgs(args, sample.scope).join(", ");
	}

	/** Prove that caching preserves the nearest duplicate-name declaration. **/
	static function assertNearestClassCacheSemantics():Void {
		final far = new HxClassDecl("SharedRecord", false, [], []);
		final owner = new HxClassDecl("DuplicateOwner", false, [], []);
		final near = new HxClassDecl("SharedRecord", false, [], [new HxFieldDecl("value", Public, false, "String", null)], "", ["__hxhx_typedef"]);
		final filler = new HxClassDecl("DuplicateFiller", false, [], []);
		final names = new StringMap<Bool>();
		for (name in ["SharedRecord", "DuplicateOwner", "DuplicateFiller"])
			names.set(name, true);
		final classes = new StringMap<HxClassDecl>();
		classes.set("SharedRecord", far);
		classes.set("DuplicateOwner", owner);
		classes.set("DuplicateFiller", filler);
		final lookup = {names: names, byName: classes, all: [far, filler, owner, near]};
		final scope = @:privateAccess backend.cpp.CppTargetCore.renderScope(owner, lookup, "void");
		final first = backend.cpp.CppTypeModel.structuralTypedefValueClassForTypeHint("SharedRecord", scope, lookup);
		final second = backend.cpp.CppTypeModel.structuralTypedefValueClassForTypeHint("SharedRecord", scope, lookup);
		assertTrue(first == near && second == near,
			"cached unqualified lookup should preserve the nearest duplicate-name declaration instead of the short-name fallback");
		assertTrue(scope.nearestClassByBaseNameCache.get("SharedRecord") == near,
			"nearest duplicate-name lookup should be recorded on the immutable render scope");
		final alternateLookup = {names: names, byName: classes, all: [owner, far]};
		assertTrue(backend.cpp.CppTypeModel.structuralTypedefValueClassForTypeHint("SharedRecord", scope, alternateLookup) == null,
			"an explicit alternate class graph must not reuse the render scope's nearest-class result");
		assertTrue(backend.cpp.CppTypeModel.structuralTypedefValueClassForTypeHint("MissingRecord", scope, lookup) == null
			&& scope.missingNearestClassByBaseNameCache.exists("MissingRecord"),
			"missing same-base lookups should be cached without inventing a declaration");
	}

	static function main():Void {
		assertNearestClassCacheSemantics();
		final calls = envInt("HXHX_CPP_XML_BASIC_RENDER_BENCH_CALLS", DEFAULT_CALLS);
		final fillerCount = envInt("HXHX_CPP_XML_BASIC_RENDER_BENCH_FILLER_CLASSES", DEFAULT_FILLER_CLASSES);
		final large = fixture(fillerCount);
		final small = fixture(0);
		final identityExpr = firstChildIdentityExpr(EIdent("node"));
		final documentArgs = nodeTypeArgs(EIdent("node"), "Document");
		final attributeArgs = [attributeJoinExpr(EIdent("node")), EString("label")];
		final childValueArgs = [childFieldExpr(EIdent("node"), "firstChild", "nodeValue"), EString("text")];
		final childNameArgs = [childFieldExpr(EIdent("node"), "firstElement", "nodeName"), EString("leaf")];
		final otherChildNameArgs = [childFieldExpr(EIdent("otherNode"), "firstElement", "nodeName"), EString("leaf")];

		final identityOutput = renderExpr(identityExpr, large);
		final documentOutput = renderEqArgs(documentArgs, large);
		final attributeOutput = renderEqArgs(attributeArgs, large);
		final childValueOutput = renderEqArgs(childValueArgs, large);
		final childNameOutput = renderEqArgs(childNameArgs, large);
		final otherChildNameOutput = renderEqArgs(otherChildNameArgs, large);
		final completeOutput = renderMethod(large, "completeBasic");

		assertTrue(identityOutput == "(node->firstChild() == node->firstChild())",
			"Xml child identity should preserve exact pointer comparison output, got " + identityOutput);
		assertTrue(documentOutput == "(node->nodeType), Xml::Document", "Xml node-kind equality should preserve its static marker, got " + documentOutput);
		assertTrue(attributeOutput.indexOf("node->attributes") >= 0 && attributeOutput.indexOf("label") >= 0,
			"Xml structural attribute iteration should retain the method provider and expected text, got " + attributeOutput);
		assertTrue(childValueOutput == "(node->firstChild()->nodeValue), std::string(\"text\")",
			"Xml child value equality should retain its exact field read, got " + childValueOutput);
		assertTrue(childNameOutput == "(node->firstElement()->nodeName), std::string(\"leaf\")",
			"Xml child name equality should retain its exact field read, got " + childNameOutput);
		assertTrue(otherChildNameOutput == "(otherNode->firstElement()->nodeName), std::string(\"leaf\")",
			"the unrelated child-field control should retain its general output, got " + otherChildNameOutput);
		assertTrue(renderEqArgs([EInt(9), EField(EIdent("OtherMarker"), "Document")], large) == "9, OtherMarker::Document",
			"the unrelated static marker control should retain its general output");
		assertTrue(completeOutput.indexOf(identityOutput) >= 0
			&& completeOutput.indexOf("Xml::Document") >= 0
			&& completeOutput.indexOf("node->attributes") >= 0
			&& completeOutput.indexOf("node->firstElement()->nodeName") >= 0,
			"the complete method should retain every attributed XML behavior shape");

		var sink = 0;
		final xmlTypeHintLargeSeconds = elapsed("xml_type_hint_large", calls,
			() -> sink += @:privateAccess backend.cpp.CppTargetCore.cppTypeHint("Xml", large.scope, large.lookup).length);
		final xmlTypeHintSmallSeconds = elapsed("xml_type_hint_small", calls,
			() -> sink += @:privateAccess backend.cpp.CppTargetCore.cppTypeHint("Xml", small.scope, small.lookup).length);
		final identityLargeSeconds = elapsed("identity_render_large", calls, () -> sink += renderExpr(identityExpr, large).length);
		final identitySmallSeconds = elapsed("identity_render_small", calls, () -> sink += renderExpr(identityExpr, small).length);
		final nodeTypeLargeSeconds = elapsed("node_type_eq_large", calls, () -> sink += renderEqArgs(documentArgs, large).length);
		final nodeTypeSmallSeconds = elapsed("node_type_eq_small", calls, () -> sink += renderEqArgs(documentArgs, small).length);
		final attributesLargeSeconds = elapsed("attributes_eq_large", calls, () -> sink += renderEqArgs(attributeArgs, large).length);
		final attributesSmallSeconds = elapsed("attributes_eq_small", calls, () -> sink += renderEqArgs(attributeArgs, small).length);
		final childValueLargeSeconds = elapsed("child_value_eq_large", calls, () -> sink += renderEqArgs(childValueArgs, large).length);
		final childValueSmallSeconds = elapsed("child_value_eq_small", calls, () -> sink += renderEqArgs(childValueArgs, small).length);
		final childNameLargeSeconds = elapsed("child_name_eq_large", calls, () -> sink += renderEqArgs(childNameArgs, large).length);
		final childNameSmallSeconds = elapsed("child_name_eq_small", calls, () -> sink += renderEqArgs(childNameArgs, small).length);
		final otherChildNameLargeSeconds = elapsed("other_child_name_eq_large", calls, () -> sink += renderEqArgs(otherChildNameArgs, large).length);
		final parseOnlySeconds = elapsed("method_parse_only", calls, () -> sink += renderMethod(large, "parseOnly").length);
		final identityMethodSeconds = elapsed("method_identity", calls, () -> sink += renderMethod(large, "childIdentity").length);
		final nodeTypesMethodSeconds = elapsed("method_node_types", calls, () -> sink += renderMethod(large, "nodeKinds").length);
		final attributesMethodSeconds = elapsed("method_attributes", calls, () -> sink += renderMethod(large, "attributeIteration").length);
		final childFieldsMethodSeconds = elapsed("method_child_fields", calls, () -> sink += renderMethod(large, "childFields").length);
		final completeMethodSeconds = elapsed("method_complete", calls, () -> sink += renderMethod(large, "completeBasic").length);
		assertTrue(sink > 0, "XML basic attribution should retain generated output");

		Sys.println("cpp_xml_basic_render_bench_calls=" + calls);
		Sys.println("cpp_xml_basic_render_bench_filler_classes=" + fillerCount);
		Sys.println("xml_type_hint_large_seconds=" + xmlTypeHintLargeSeconds);
		Sys.println("xml_type_hint_small_seconds=" + xmlTypeHintSmallSeconds);
		Sys.println("identity_render_large_seconds=" + identityLargeSeconds);
		Sys.println("identity_render_small_seconds=" + identitySmallSeconds);
		Sys.println("node_type_eq_large_seconds=" + nodeTypeLargeSeconds);
		Sys.println("node_type_eq_small_seconds=" + nodeTypeSmallSeconds);
		Sys.println("attributes_eq_large_seconds=" + attributesLargeSeconds);
		Sys.println("attributes_eq_small_seconds=" + attributesSmallSeconds);
		Sys.println("child_value_eq_large_seconds=" + childValueLargeSeconds);
		Sys.println("child_value_eq_small_seconds=" + childValueSmallSeconds);
		Sys.println("child_name_eq_large_seconds=" + childNameLargeSeconds);
		Sys.println("child_name_eq_small_seconds=" + childNameSmallSeconds);
		Sys.println("other_child_name_eq_large_seconds=" + otherChildNameLargeSeconds);
		Sys.println("method_parse_only_seconds=" + parseOnlySeconds);
		Sys.println("method_identity_seconds=" + identityMethodSeconds);
		Sys.println("method_node_types_seconds=" + nodeTypesMethodSeconds);
		Sys.println("method_attributes_seconds=" + attributesMethodSeconds);
		Sys.println("method_child_fields_seconds=" + childFieldsMethodSeconds);
		Sys.println("method_complete_seconds=" + completeMethodSeconds);
		Sys.println("M14_CPP_XML_BASIC_RENDER_BENCH:PASS");
	}
}
