import sys.io.File;

/** Compare descriptor transport and observable evaluation with an independent upstream run. */
class M14Stage3EnumTypeValuePayloadTest {
	/** A copied source marker cannot borrow the original executable's typed call. */
	static function ownership(prepared:TypedModule):Void {
		final classes = new backend.ocaml.Stage3OcamlClassStorage();
		for (owner in prepared.getBackendProjection().getClasses())
			classes.add(owner, false);
		var checked = false;
		for (owner in prepared.getBackendProjection().getClasses())
			for (fn in owner.getFunctions())
				TypedBackendSourceWalk.functionDeclaration(fn.getDeclaration(), expression -> {
					final call = TypedExactStaticCallSource.decode(expression);
					if (checked || call == null || call.owner != "Type" || call.method != "getClass")
						return;
					final copied:HxExpr = switch expression {
						case ECall(callee, arguments): ECall(callee, arguments.copy());
						case _: throw "type query fixture lost its call";
					};
					var rejected = false;
					try
						backend.ocaml.Stage3OcamlTypeQueries.render({
							expression: copied,
							lookup: fn.findCallableExpression,
							classes: classes,
							emit: _ -> throw "unowned operand was rendered"
						})
					catch (error:String)
						rejected = error.indexOf("requires its exact typed call") >= 0;
					if (!rejected)
						throw "copied type query borrowed executable ownership";
					checked = true;
				}, _ -> {});
		if (!checked)
			throw "type query ownership fixture found no selected call";
		Sys.println("M14_STAGE3_TYPE_QUERY_OWNERSHIP:PASS");
	}

	static function main():Void {
		final root = "test/fixtures/ocaml_enum_type_values";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		final prepared = M14Stage3RuntimeFixture.prepareMain({source: File.getContent(path), path: path, root: root});
		ownership(prepared);
		final artifact = EmitterStage.emitToDir(new MacroExpandedProgram([prepared], false), ".tmp/ocaml_enum_type_values", true);
		M14Stage3RuntimeFixture.observe({command: artifact, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_ENUM_TYPE_VALUES:PASS");
	}
}
