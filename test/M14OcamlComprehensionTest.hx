import sys.io.File;

/** Compare shared comprehension lowering through real OCaml execution and upstream Haxe. */
class M14OcamlComprehensionTest {
	/** Require a deliberate ownership rejection, not an incidental native build failure. */
	static function rejection(action:Void->Void):String {
		try {
			action();
		} catch (error:haxe.Exception) {
			return error.message;
		} catch (error:String) {
			return error;
		}
		return "";
	}

	static function ownership(typed:TypedModule):Void {
		var checked = 0;
		for (owner in typed.getTypedClasses())
			for (fn in owner.getFunctions())
				if (HxFunctionDecl.getName(fn.getSourceDeclaration()) == "values") {
					final projection = TypedBodySource.functionProjection(fn);
					final foreign = TypedBodySource.functionProjection(fn);
					TypedBackendSourceWalk.functionDeclaration(projection.getDeclaration(), value -> {
						switch value {
							case ELoweredControl(operation = For(_), destination, children, position):
								projection.requireCollectionControl(value);
								final copied:HxExpr = ELoweredControl(operation, destination, children.copy(), position);
								if (rejection(() -> projection.requireCollectionControl(copied)).indexOf("exact function projection") < 0
									|| rejection(() -> foreign.requireCollectionControl(value)).indexOf("exact function projection") < 0)
									throw "collection operation accepted a copy or another projection";
								final original = children[0];
								children[0] = switch original {
									case EArrayDecl(elements): EArrayDecl(elements.copy());
									case _: throw "ownership fixture requires its authored literal iterable";
								};
								final changed = rejection(() -> projection.requireCollectionControl(value));
								children[0] = original;
								if (changed.indexOf("operands were replaced") < 0)
									throw "collection operation accepted replaced operand objects: " + changed;
								projection.requireCollectionControl(value);
								checked++;
							case _:
						}
					}, _ -> {});
				}
		if (checked != 1)
			throw "collection ownership fixture did not observe its exact loop";
	}

	static function main():Void {
		final root = "test/fixtures/stage3_array_comprehension";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		final path = root + "/Main.hx";
		final typed = M14Stage3RuntimeFixture.typeMain({source: File.getContent(path), path: path, root: root});
		ownership(typed);
		final functions = [for (owner in typed.getTypedClasses()) for (fn in owner.getFunctions()) fn];
		final revisions = [for (fn in functions) CompilerTypedTreeRevision.functionBody(fn)];
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), ".tmp/stage3-array-comprehension", true);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		for (index in 0...functions.length)
			if (CompilerTypedTreeRevision.functionBody(functions[index]) != revisions[index])
				throw "native comprehension emission changed the authored typed source";
		Sys.println("OCAML_COMPREHENSION:PASS");
	}
}
