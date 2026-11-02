/**
	Dependent method bounds such as `Std.downcast<T:{}, S:T>` must follow upstream when
	an argument leaves `T` open.

	A Dynamic value, `null`, or an unchecked `cast null` does not fix `T`. Upstream then
	lets the `S:T` check close `T` from `S`, and checks `T`'s own bounds against that
	type. So `Std.downcast(dynamicValue, Sub)` is accepted, while a user method
	`pick<T:String, S:T>(dynamicValue, 5)` fails on `pick.T` because `T` becomes Int.
 */
class M14DowncastDynamicConstraintTest {
	static final root = "test/oracle/downcast_dynamic_seed";

	static function main():Void {
		accept();
		reject("InvalidSibling", "Constraint check failure for downcast.S");
		reject("InvalidDynamicBound", "Constraint check failure for pick.T");
		reject("InvalidCastBound", "Constraint check failure for pick.T");
		Sys.println("DOWNCAST_DYNAMIC_CONSTRAINT:PASS");
	}

	/** Run upstream Haxe on the same module so the fixture cannot drift from the reference compiler. */
	static function upstream(module:String, diagnostic:Null<String>):Void {
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", module, "--no-output"]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (diagnostic == null ? code != 0 : code == 0 || stderr.indexOf(diagnostic) < 0)
			throw "upstream constraint contract differs for " + module + ": " + stdout + stderr;
	}

	static function load(module:String):CppResolvedFixture.CppResolvedFixtureProgram {
		return CppResolvedFixture.load({sourceRoot: root, mainModule: module, requiredModules: ["Std"]});
	}

	/** Valid calls type with the class argument's type as their result, not an unknown fallback. */
	static function accept():Void {
		upstream("Main", null);
		final typed = load("Main").main;
		final results = new Array<String>();
		function inspect(node:TypedExpr):Void {
			final declaration = node.getDeclaration();
			if (node.getTag() == Call && declaration != null) {
				final name = declaration.getSignature().getName();
				if (name == "downcast" || name == "open")
					results.push(name + "=" + node.getType().getSemanticKey());
			}
			for (child in node.getExpressions())
				inspect(child);
		}
		for (owner in typed.getTypedClasses())
			for (fn in owner.getFunctions())
				if (fn.getDeclaration().getSignature().getName() == "main")
					for (statement in fn.getBody().getStatements())
						for (node in statement.getExpressions())
							inspect(node);
		final expected = [
			"downcast=nominal:Shapes.Sub",
			"downcast=nominal:Shapes.Sub",
			"downcast=nominal:Shapes.Sub",
			"downcast=nominal:Shapes.Sub",
			"downcast=nominal:Shapes.Base",
			"open=primitive:String"
		];
		for (entry in expected)
			if (results.indexOf(entry) < 0)
				throw "valid dependent-bound call lost its result type " + entry + ": " + results.join("|");
		if (results.filter(entry -> StringTools.startsWith(entry, "downcast=")).length != 7)
			throw "every downcast call must type: " + results.join("|");
		Sys.println("DOWNCAST_DYNAMIC_CONSTRAINT_ACCEPT:PASS");
	}

	/** A dependent bound that upstream rejects must still fail with the same parameter name. */
	static function reject(module:String, diagnostic:String):Void {
		upstream(module, diagnostic);
		var rejected = false;
		try
			load(module)
		catch (error:TyperError) {
			if (error.getMessage() != diagnostic || !StringTools.endsWith(error.getFilePath(), root + "/" + module + ".hx"))
				throw error;
			rejected = true;
		}
		if (!rejected)
			throw "invalid dependent bound was accepted: " + module;
		Sys.println("DOWNCAST_DYNAMIC_CONSTRAINT_REJECT:PASS " + module);
	}
}
