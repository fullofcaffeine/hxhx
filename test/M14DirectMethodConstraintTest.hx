import sys.io.File;

/** Direct generic calls check declaration-owned bounds without changing stored-callback acceptance. */
class M14DirectMethodConstraintTest {
	static final root = "test/fixtures/js_feature_intrinsic";

	static function resolve(name:String):ResolvedModule {
		final path = root + "/" + name.split(".").join("/") + ".hx";
		return new ResolvedModule(name, path, ParserStage.parse(File.getContent(path), path));
	}

	/** Upstream decides source acceptance; fixed runtime expectations below are independently retained. */
	static function upstream(name:String, diagnostic:Null<String>):Void {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout",
			["30", "node_modules/.bin/haxe", "-cp", root, "-main", name, "--no-output"]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (diagnostic == null ? code != 0 : code == 0 || stderr.indexOf(diagnostic) < 0)
			throw "upstream constraint contract differs for " + name + ": " + stdout + stderr;
	}

	/** Invalid calls must fail at the source boundary, before typed-body replay or target emission. */
	static function reject(name:String, provider:String, parameter:String = "T", ?upstreamDiagnostic:String):Void {
		final diagnostic = "Constraint check failure for echo." + parameter;
		upstream(name, upstreamDiagnostic == null ? diagnostic : upstreamDiagnostic);
		final modules = [resolve(name), resolve(provider)];
		var rejected = false;
		try {
			TyperStage.typeResolvedModule(modules[0], TyperIndex.build(modules));
		} catch (error:TyperError) {
			if (error.getMessage() != diagnostic || error.getFilePath() != root + "/" + name.split(".").join("/") + ".hx")
				throw error;
			rejected = true;
		}
		if (!rejected)
			throw "invalid direct method constraint was accepted: " + name;
		Sys.println("DIRECT_METHOD_CONSTRAINT_REJECTION:PASS " + name);
	}

	/** Inspect every direct echo call before running the same typed module through the JavaScript backend. */
	static function accept(input:{module:String, results:Array<String>, stdout:String}):Void {
		upstream(input.module, null);
		final resolved = resolve(input.module);
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final results = new Array<String>();
		function inspect(node:TypedExpr):Void {
			final declaration = node.getDeclaration();
			if (node.getTag() == Call && declaration != null && declaration.getSignature().getName() == "echo")
				results.push(node.getType().getSemanticKey());
			for (child in node.getExpressions())
				inspect(child);
		}
		for (owner in typed.getTypedClasses())
			for (fn in owner.getFunctions())
				if (fn.getDeclaration().getSignature().getName() == "main")
					for (statement in fn.getBody().getStatements())
						for (node in statement.getExpressions())
							inspect(node);
		if (results.join("|") != input.results.join("|"))
			throw "direct method results differ for " + input.module + ": " + results.join("|");
		JsRuntimeFixture.assertRuntime(typed, input.module, input.stdout);
		Sys.println("DIRECT_METHOD_CONSTRAINT_RUNTIME:PASS " + input.module);
	}

	static function main():Void {
		reject("FeatureBoundConstraintDirect", "FeatureBoundConstraint");
		reject("foreign.FeatureBoundConstraintForeign", "FeatureBoundConstraint");
		reject("FeatureBoundCompoundMissingInterface", "FeatureBoundCompound");
		reject("FeatureBoundCompoundMissingBase", "FeatureBoundCompound");
		reject("FeatureBoundInterfaceConflict", "FeatureBoundInterface", "T", "Int should be String");
		reject("FeatureBoundInterfaceUndeclared", "FeatureBoundInterface");
		reject("FeatureBoundAppliedConflict", "FeatureBoundApplied", "U");
		accept({module: "FeatureBoundInterface", results: ["nominal:FeatureBoundInterface.InterfaceChild"], stdout: "interface\n"});
		accept({module: "FeatureBoundCompound", results: ["nominal:FeatureBoundCompound.CompoundChild"], stdout: "compound\n"});
		accept({
			module: "FeatureBoundApplied",
			results: [
				"nominal:FeatureBoundApplied.AppliedChild",
				"nominal:FeatureBoundApplied.AppliedChild"
			],
			stdout: "child\nchild\n"
		});
		accept({module: "FeatureBoundConstraint", results: ["nominal:FeatureBoundConstraint.ConstraintChild"], stdout: "child\nchild\n"});
		accept({module: "FeatureBoundConstraintCapture", results: [], stdout: "7\n"});
		accept({
			module: "FeatureBoundEmptyObject",
			results: ["nominal:FeatureBoundEmptyObject.EmptyObjectValue", "primitive:String"],
			stdout: "true\nobject\ntext\n"
		});
		Sys.println("DIRECT_METHOD_CONSTRAINT:PASS");
	}
}
