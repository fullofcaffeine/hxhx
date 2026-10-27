import sys.io.File;

/** Compare record identity and typed storage through ordinary native enum payloads. */
class M14Stage3EnumRecordPayloadTest {
	/** A record destination cannot borrow a missing, differently typed, or copied operand fact. */
	static function ownership(prepared:TypedModule):Void {
		final catalog = new backend.ocaml.Stage3OcamlEnums(name -> name.toLowerCase(), value -> '"' + value + '"');
		final classes = prepared.getBackendProjection().getClasses();
		for (owner in classes)
			catalog.add(owner, "Main_" + HxClassDecl.getName(owner.getDeclaration()), "");
		catalog.validate();
		final names = new backend.ocaml.Stage3OcamlLocalNames(new TypedBackendLocalCatalog([]), false, name -> name);
		var checked = false;
		for (owner in classes) {
			final facts = owner.requireSemanticFacts();
			for (constructor in facts.copyEnumConstructors())
				switch constructor.member {
					case Callable(method) if (constructor.name == "Record"):
						final operand:HxExpr = EIdent("record");
						final target = method.arguments[0].semanticType;
						final source = TypedExpr.localRead("record", target, null);
						final selected:TypedExactEnumConstructorSource.TypedExactEnumConstructorCall = {
							owner: facts.getClassIdentity(),
							modulePath: facts.getModuleIdentity(),
							declaration: method.canonicalIdentity,
							constructor: constructor.name,
							callee: EIdent("ignored"),
							arguments: [operand]
						};
						reject(() -> catalog.call(selected, _ -> "record", names, _ -> null));
						final wrongDestination = new TypedBackendCallArgument("owner", "revision", source, operand, TyType.fromHintText("Int"));
						reject(() -> catalog.call(selected, _ -> "record", names, _ -> wrongDestination));
						final copied = new TypedBackendCallArgument("owner", "revision", source, EIdent("record"), target);
						reject(() -> catalog.call(selected, _ -> "record", names, _ -> copied));
						final wrongSource = new TypedBackendCallArgument("owner", "revision", TypedExpr.intLiteral(1, TyType.fromHintText("Int"), null),
							operand, target);
						reject(() -> catalog.call(selected, _ -> "record", names, _ -> wrongSource));
						checked = true;
					case _:
				}
		}
		if (!checked)
			throw "record payload ownership controls found no constructor";
	}

	static function reject(action:Void->String):Void {
		var diagnostic = "";
		try
			action()
		catch (error:String)
			diagnostic = error;
		if (diagnostic != "OCaml record enum argument requires its exact typed record operand and destination")
			throw "record payload accepted an unowned crossing: " + diagnostic;
	}

	static function main():Void {
		final root = "test/fixtures/stage3_enum_records";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		final prepared = M14Stage3RuntimeFixture.prepareMain({source: File.getContent(path), path: path, root: root});
		ownership(prepared);
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([prepared], false), ".tmp/stage3-enum-records", true);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_ENUM_RECORDS:PASS");
	}
}
