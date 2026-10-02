import sys.io.File;

/** Caller bounds must prove forwarded generic calls without erasing the caller's parameter identity. */
class M14GenericForwardingConstraintTest {
	static function main():Void {
		check("object", "forwarded\n");
		check("transitive", "transitive\n");
		check("class_argument", "class\n");
		check("nullable", "nullable\n");
		check("dynamic", "dynamic\n");
		check("nominal", "nominal\n");
		check("unconstrained", null);
		check("scalar", null);
		check("shadowed_bound", null, "S");
		checkCyclicBounds();
		Sys.println("GENERIC_FORWARDING_CONSTRAINT:PASS");
	}

	/** Independent upstream acceptance and output govern each positive or negative source case. */
	static function check(name:String, expected:Null<String>, rejectedParameter:String = "T"):Void {
		final root = "test/oracle/generic_forwarding_seed/" + name;
		final process = new sys.io.Process("haxe", ["-cp", root, "-main", "Main", "--interp"]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (expected == null ? code == 0 : code != 0 || stdout != expected)
			throw "upstream forwarding contract changed: " + stdout + stderr;
		final path = root + "/Main.hx";
		final parsed = ParserStage.parse(File.getContent(path), path);
		final resolved = new ResolvedModule("Main", path, parsed);
		final arguments = hxhx.Stage1Compiler.Stage1Args.parse(["-main", "Main"], true);
		final standardRoot = hxhx.Stage1Compiler.Stage1Args.getStandardLibraryRoot(arguments);
		// Class<T> must use its real standard-library declaration, as it does in the library workload.
		final providers = ResolverStage.parseProjectRootsShallow([standardRoot], ["Class"], new haxe.ds.StringMap<String>());
		var typed:Null<TypedModule> = null;
		try {
			typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved].concat(providers)));
		} catch (error:TyperError) {
			if (expected != null
				|| error.getMessage() != "Constraint check failure for requireObject." + rejectedParameter
				|| error.getFilePath() != path)
				throw error;
		}
		if (expected == null) {
			if (typed != null)
				throw "unproved caller bound was accepted: " + name;
		} else {
			if (typed == null)
				throw "valid forwarding was rejected: " + name;
			var inspected = false;
			for (owner in typed.getTypedClasses())
				for (fn in owner.getFunctions())
					if (fn.getDeclaration().getSignature().getName() == "forward") {
						final expectedType = fn.getDeclaration().getSignature().getReturnType();
						for (statement in fn.getBody().getStatements())
							if (statement.getTag() == Return) {
								final call = statement.getExpressions()[0];
								if (call.getTag() != Call
									|| call.getDeclaration() == null
									|| call.getDeclaration().getSignature().getName() != "requireObject"
									|| call.getType().getSemanticKey() != expectedType.getSemanticKey())
									throw "forwarding lost its selected declaration or exact caller parameter: " + name;
								inspected = true;
							}
					}
			if (!inspected)
				throw "forwarded call was not inspected: " + name;
			JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		}
		Sys.println("GENERIC_FORWARDING_CASE:PASS " + name);
	}

	/** Cyclic evidence cannot prove an unrelated bound or borrow a same-spelled foreign binder. */
	static function checkCyclicBounds():Void {
		final first = new TyTypeParameterId("forwarding-cycle", 0, "T");
		final second = new TyTypeParameterId("forwarding-cycle", 1, "U");
		final bounds = new haxe.ds.StringMap<Array<TyType>>();
		bounds.set(first.getCanonicalKey(), [TyType.typeParameter(second)]);
		bounds.set(second.getCanonicalKey(), [TyType.typeParameter(first)]);
		final integer = TyType.fromHintText("Int");
		function same(expected:TyType, supplied:TyType):Bool
			return expected.getSemanticKey() == supplied.getSemanticKey();
		if (TyCallerConstraintProof.accepts(integer, TyType.typeParameter(first), bounds, same))
			throw "cyclic bounds proved an unrelated constraint";
		bounds.set(second.getCanonicalKey(), [TyType.typeParameter(first), integer]);
		if (!TyCallerConstraintProof.accepts(integer, TyType.typeParameter(first), bounds, same))
			throw "a cyclic path hid independent valid bound evidence";
		final foreign = new TyTypeParameterId("another-forwarder", 0, "T");
		if (TyCallerConstraintProof.accepts(integer, TyType.typeParameter(foreign), bounds, same))
			throw "same-spelled foreign parameter borrowed a caller bound";
	}
}
