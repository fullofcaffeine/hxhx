import sys.io.File;

/** Preserve an exact typed array through native enum construction and extraction. */
class M14Stage3EnumArrayPayloadTest {
	/** A constructor may retain only its own operand with the same complete element storage type. */
	static function ownership(prepared:TypedModule):Void {
		final catalog = new backend.ocaml.Stage3OcamlEnums(name -> name.toLowerCase(), value -> '"' + value + '"');
		final classes = prepared.getBackendProjection().getClasses();
		for (owner in classes)
			catalog.add(owner, "Main_" + HxClassDecl.getName(owner.getDeclaration()), "");
		catalog.validate();
		final names = new backend.ocaml.Stage3OcamlLocalNames(new TypedBackendLocalCatalog([]), false, name -> name);
		var otherArray:Null<TyType> = null;
		for (owner in classes)
			for (constructor in owner.requireSemanticFacts().copyEnumConstructors())
				switch constructor.member {
					case Callable(method) if (constructor.name == "Texts"):
						otherArray = method.arguments[0].semanticType;
					case _:
				}
		if (otherArray == null)
			throw "array payload controls found no distinct element type";
		var checked = false;
		for (owner in classes) {
			final facts = owner.requireSemanticFacts();
			for (constructor in facts.copyEnumConstructors())
				switch constructor.member {
					case Callable(method) if (constructor.name == "Values"):
						final operand:HxExpr = EIdent("values");
						final target = method.arguments[0].semanticType;
						final source = TypedExpr.localRead("values", target, null);
						final selected:TypedExactEnumConstructorSource.TypedExactEnumConstructorCall = {
							owner: facts.getClassIdentity(),
							modulePath: facts.getModuleIdentity(),
							declaration: method.canonicalIdentity,
							constructor: constructor.name,
							callee: EIdent("ignored"),
							arguments: [operand]
						};
						reject(() -> catalog.call(selected, _ -> "values", names, _ -> null));
						final absentDestination = new TypedBackendCallArgument("owner", "revision", source, operand);
						reject(() -> catalog.call(selected, _ -> "values", names, _ -> absentDestination));
						final wrongDestination = new TypedBackendCallArgument("owner", "revision", source, operand, TyType.fromHintText("Int"));
						reject(() -> catalog.call(selected, _ -> "values", names, _ -> wrongDestination));
						final copied = new TypedBackendCallArgument("owner", "revision", source, EIdent("values"), target);
						reject(() -> catalog.call(selected, _ -> "values", names, _ -> copied));
						final wrongSource = new TypedBackendCallArgument("owner", "revision", TypedExpr.intLiteral(1, TyType.fromHintText("Int"), null),
							operand, target);
						reject(() -> catalog.call(selected, _ -> "values", names, _ -> wrongSource));
						final wrongElements = new TypedBackendCallArgument("owner", "revision", TypedExpr.localRead("values", otherArray, null), operand,
							target);
						reject(() -> catalog.call(selected, _ -> "values", names, _ -> wrongElements));
						final wrongArrayDestination = new TypedBackendCallArgument("owner", "revision", source, operand, otherArray);
						reject(() -> catalog.call(selected, _ -> "values", names, _ -> wrongArrayDestination));
						final unknownSource = new TypedBackendCallArgument("owner", "revision", TypedExpr.localRead("values", TyType.unknown(), null),
							operand, target);
						reject(() -> catalog.call(selected, _ -> "values", names, _ -> unknownSource));
						var emissions = 0;
						final exact = new TypedBackendCallArgument("owner", "revision", source, operand, target);
						catalog.call(selected, _ -> {
							emissions++;
							return "values";
						}, names, _ -> exact);
						if (emissions != 1)
							throw "array payload operand was not emitted exactly once";
						checked = true;
					case _:
				}
		}
		if (!checked)
			throw "array payload ownership controls found no constructor";
	}

	static function reject(action:Void->String):Void {
		var diagnostic = "";
		try
			action()
		catch (error:String)
			diagnostic = error;
		if (diagnostic != "OCaml array enum argument requires its exact typed array operand and destination")
			throw "array payload accepted an unowned crossing: " + diagnostic;
	}

	static function main():Void {
		final root = "test/fixtures/stage3_enum_arrays";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		final prepared = M14Stage3RuntimeFixture.prepareMain({source: File.getContent(path), path: path, root: root});
		ownership(prepared);
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([prepared], false), ".tmp/stage3-enum-arrays", true);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_ENUM_ARRAYS:PASS");
	}
}
