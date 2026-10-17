import reflaxe.ocaml.target.OcamlTargetDeclarationRequest;
import reflaxe.ocaml.target.OcamlTargetDeclarationRequest.OcamlTargetClassInput;

/** Verifies stable, copied, fail-closed declaration requests. **/
class TargetDeclarationFixture {
	static function main():Void {
		final source = classes(false, false);
		final first = new OcamlTargetDeclarationRequest("stock-host-revision", source);
		final second = new OcamlTargetDeclarationRequest("native-host-revision", classes(true, false));
		assertEquals(first.getCanonicalIdentity(), second.getCanonicalIdentity(), "host or traversal order changed target facts");

		source[0].typeParameters.push("LeakedMutation");
		assertEquals(first.getCanonicalIdentity(), new OcamlTargetDeclarationRequest("third-host", classes(false, false)).getCanonicalIdentity(),
			"request retained a caller-owned array");
		final exposed = first.copyClasses();
		exposed.resize(0);
		assertTrue(first.copyClasses().length == 1, "request exposed its class array");

		final changed = new OcamlTargetDeclarationRequest("stock-host-revision", classes(false, true));
		assertTrue(first.getCanonicalIdentity() != changed.getCanonicalIdentity(), "optional argument change did not change target facts");

		assertThrows(() -> new OcamlTargetDeclarationRequest("host", [
			{
				canonicalIdentity: "unit.Child",
				moduleIdentity: "unit.Child",
				isInterface: false,
				isExtern: false,
				interfaceTypeDisplays: [],
				typeParameters: [],
				superClassIdentity: "unit.Base",
				fields: [],
				methods: []
			}
		]), "partial superclass facts were accepted");
		final repeated = new OcamlTargetDeclarationRequest("host", classes(false, false).concat(classes(false, false)));
		assertTrue(repeated.copyClasses().length == 1, "equivalent repeated class facts were not collapsed");
		final conflictingClasses = classes(false, false).concat(classes(false, false, "unit.Other"));
		assertThrows(() -> new OcamlTargetDeclarationRequest("host", conflictingClasses), "conflicting class facts were accepted");
		assertClassHeaders();
		Sys.println("OCAML_TARGET_DECLARATION_REQUEST:PASS");
	}

	/** A changed construction or dispatch contract must invalidate declaration identity. **/
	static function assertClassHeaders():Void {
		final plain = new OcamlTargetDeclarationRequest("host", [header(false, false, [])]);
		for (input in [
			header(true, false, []),
			header(false, true, []),
			header(false, false, ["Contract<Int>"])
		]) {
			final changed = new OcamlTargetDeclarationRequest("host", [input]);
			assertTrue(plain.getCanonicalIdentity() != changed.getCanonicalIdentity(), "class header change did not affect identity");
			assertThrows(() -> new OcamlTargetDeclarationRequest("host", [header(false, false, []), input]), "conflicting class headers were collapsed");
			assertThrowsMessage(() -> new reflaxe.ocaml.target.OcamlTargetProgramRequest("host", "Main", changed, [], []),
				"OCaml target program requires a generated class without interface relationships");
		}
		final interfaces = ["Contract<Int>"];
		final applied = new OcamlTargetDeclarationRequest("host", [header(false, false, interfaces)]);
		final before = applied.getCanonicalIdentity();
		interfaces[0] = "Contract<String>";
		applied.copyClasses()[0].copyInterfaceTypeDisplays().resize(0);
		assertEquals(before, applied.getCanonicalIdentity(), "class retained mutable interface storage");
		assertEquals("Contract<Int>", applied.copyClasses()[0].copyInterfaceTypeDisplays()[0], "interface copy mutation leaked");
		assertTrue(before != new OcamlTargetDeclarationRequest("host", [header(false, false, interfaces)]).getCanonicalIdentity(),
			"applied interface argument did not affect identity");
		assertThrows(() -> new OcamlTargetDeclarationRequest("host", [header(false, false, [""])]), "empty interface type was accepted");
	}

	static function header(isInterface:Bool, isExtern:Bool, interfaces:Array<String>):OcamlTargetClassInput {
		return {
			canonicalIdentity: "Main",
			moduleIdentity: "Main",
			isInterface: isInterface,
			isExtern: isExtern,
			interfaceTypeDisplays: interfaces,
			typeParameters: [],
			fields: [],
			methods: []
		};
	}

	static function classes(reverse:Bool, optional:Bool, moduleIdentity:String = "unit.Sample"):Array<OcamlTargetClassInput> {
		final owner = "unit.Sample";
		final field = {
			canonicalIdentity: OcamlTargetDeclarationRequest.fieldIdentity(owner, "count", false),
			name: "count",
			typeIdentity: "Int",
			typeDisplay: "Int",
			isStatic: false,
			isPublic: true,
			isFinal: false,
			isInline: false,
			hasInitializer: true,
			propertyGet: "normal",
			propertySet: "normal",
			noImportGlobal: false
		};
		final arguments = [
			{
				name: "value",
				typeIdentity: "String",
				typeDisplay: "String",
				isOptional: optional,
				isRest: false
			}
		];
		final method = {
			canonicalIdentity: OcamlTargetDeclarationRequest.methodIdentity(owner, "render", false, ['String:optional=${optional ? "1" : "0"}:rest=0'],
				"String"),
			name: "render",
			typeParameters: ["T"],
			arguments: arguments,
			returnTypeIdentity: "String",
			returnTypeDisplay: "String",
			isStatic: false,
			isPublic: true,
			isInline: false,
			isDynamic: false,
			hasBody: true,
			isEnumConstructor: false,
			noImportGlobal: false
		};
		final fields = [field];
		final methods = [method];
		if (reverse) {
			fields.reverse();
			methods.reverse();
		}
		return [
			{
				canonicalIdentity: owner,
				moduleIdentity: moduleIdentity,
				isInterface: false,
				isExtern: false,
				interfaceTypeDisplays: [],
				typeParameters: ["T"],
				fields: fields,
				methods: methods
			}
		];
	}

	static function assertThrows(run:Void->Void, message:String):Void {
		var threw = false;
		try {
			run();
		} catch (_:String) {
			threw = true;
		}
		assertTrue(threw, message);
	}

	static function assertThrowsMessage(run:Void->Void, expected:String):Void {
		try {
			run();
		} catch (message:String) {
			assertEquals(expected, message, "unexpected class admission failure");
			return;
		}
		throw "missing class admission failure: " + expected;
	}

	static function assertEquals(expected:String, actual:String, message:String):Void
		assertTrue(expected == actual, message + ': expected ${expected}, received ${actual}');

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}
}
