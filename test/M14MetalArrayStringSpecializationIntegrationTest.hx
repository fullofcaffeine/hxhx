import backend.OcamlProfile;

private typedef TypeHintSpec = {
	final name:String;
	final hint:String;
}

class M14MetalArrayStringSpecializationIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0)
			throw label + " (missing `" + needle + "`)";
	}

	static function makeTypeHints(specs:Array<TypeHintSpec>):Map<String, TyType> {
		final tyByIdent = new Map<String, TyType>();
		if (specs == null)
			return tyByIdent;
		for (spec in specs) {
			tyByIdent.set(spec.name, TyType.fromHintText(spec.hint));
		}
		return tyByIdent;
	}

	static function emitExpr(expr:HxExpr, profile:OcamlProfile, ?typeHints:Array<TypeHintSpec>):String {
		final previousProfile = @:privateAccess EmitterStage.currentOcamlProfile;
		@:privateAccess EmitterStage.currentOcamlProfile = profile;
		var rendered:Null<String> = null;
		var failure:Null<String> = null;
		try {
			rendered = @:privateAccess EmitterStage.exprToOcaml(expr, null, makeTypeHints(typeHints), null, null, null, null);
		} catch (message:String) {
			failure = message;
		} catch (error:haxe.Exception) {
			failure = error.message;
		}
		@:privateAccess EmitterStage.currentOcamlProfile = previousProfile;
		if (failure != null)
			throw failure;
		assertTrue(rendered != null, "emitter returned null expression text");
		return rendered;
	}

	static function expectEmitFailure(expr:HxExpr, profile:OcamlProfile, expectedSnippet:String, ?typeHints:Array<TypeHintSpec>):Void {
		var failure:Null<String> = null;
		try {
			emitExpr(expr, profile, typeHints);
		} catch (message:String) {
			failure = message;
		} catch (error:haxe.Exception) {
			failure = error.message;
		}
		assertTrue(failure != null, "expected emitter failure");
		assertContains(failure, expectedSnippet, "unexpected emitter failure message");
	}

	static function main():Void {
		final stringArrayHints:Array<TypeHintSpec> = [{name: "words", hint: "Array<String>"}];
		final intArrayHints:Array<TypeHintSpec> = [{name: "numbers", hint: "Array<Int>"}];
		final dynamicStringKeyHints:Array<TypeHintSpec> = [{name: "payload", hint: "Dynamic"}, {name: "key", hint: "String"}];

		final portableMap = emitExpr(ECall(EField(EIdent("words"), "map"), [EIdent("transform")]), OcamlProfile.Portable, stringArrayHints);
		assertContains(portableMap, "HxBootArray.map_dyn", "portable profile should keep dynamic map fallback");

		final metalMap = emitExpr(ECall(EField(EIdent("words"), "map"), [EIdent("transform")]), OcamlProfile.Metal, stringArrayHints);
		assertContains(metalMap, "HxBootArray.map (", "metal profile should emit typed map");
		assertTrue(metalMap.indexOf("map_dyn") < 0, "metal profile should avoid dynamic map fallback");

		final portableJoin = emitExpr(ECall(EField(EIdent("words"), "join"), [EString(",")]), OcamlProfile.Portable, stringArrayHints);
		assertContains(portableJoin, "HxBootArray.join (", "portable profile should use string join helper");
		assertTrue(portableJoin.indexOf("join_dyn") < 0, "portable profile should avoid dynamic join fallback for Array<String>");

		final metalJoin = emitExpr(ECall(EField(EIdent("words"), "join"), [EString(",")]), OcamlProfile.Metal, stringArrayHints);
		assertContains(metalJoin, "HxBootArray.join_strict (", "metal profile should emit strict Array<String>.join");
		assertTrue(metalJoin.indexOf("join_dyn") < 0, "metal profile should avoid dynamic join fallback");

		final metalStringArrayLiteral = emitExpr(EArrayDecl([EString("a"), EString("b"), EString("c")]), OcamlProfile.Metal);
		assertContains(metalStringArrayLiteral, "HxBootArray.of_list [\"a\"; \"b\"; \"c\"]", "metal profile should emit typed string array literals");
		assertTrue(metalStringArrayLiteral.indexOf("Obj.magic") < 0, "metal profile should avoid Obj.magic array literal wrapping");

		final portableMixedArrayLiteral = emitExpr(EArrayDecl([EInt(1), EString("x")]), OcamlProfile.Portable);
		assertContains(portableMixedArrayLiteral, "Obj.magic", "portable profile should keep mixed-array fallback wrapping");

		final portableCastStringKey = emitExpr(EArrayAccess(EIdent("payload"), ECast(EIdent("key"), "")), OcamlProfile.Portable, dynamicStringKeyHints);
		assertContains(portableCastStringKey, "HxAnon.get", "cast-wrapped String keys should use Dynamic field access");
		assertTrue(portableCastStringKey.indexOf("HxBootArray.get") < 0, "cast-wrapped String keys should not use integer array access");

		final portableUntypedStringKey = emitExpr(EArrayAccess(EIdent("payload"), EUntyped(EIdent("key"))), OcamlProfile.Portable, dynamicStringKeyHints);
		assertContains(portableUntypedStringKey, "HxAnon.get", "untyped-wrapped String keys should use Dynamic field access");
		assertTrue(portableUntypedStringKey.indexOf("HxBootArray.get") < 0, "untyped-wrapped String keys should not use integer array access");

		expectEmitFailure(EArrayDecl([EInt(1), EString("x")]), OcamlProfile.Metal, "mixed-type array literals are not allowed");
		expectEmitFailure(ECall(EField(EIdent("numbers"), "join"), [EString(",")]), OcamlProfile.Metal, "Array.join requires Array<String> receiver",
			intArrayHints);
		expectEmitFailure(EArrayAccess(EIdent("payload"), EString("key")), OcamlProfile.Metal, "string-key indexing is not supported");
	}
}
