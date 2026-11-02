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
		// A null `T` is a wildcard inside another bound, never a reason to skip that bound.
		reject("InvalidNullArrayBound", "Constraint check failure for pick.S");
		reject("InvalidNullBoundedArrayBound", "Constraint check failure for pick.S");
		reject("InvalidNullRecordBound", "Constraint check failure for pick.S", "{ y : Int } should be { x : Null<Unknown<0>> }");
		reject("InvalidNullClassBound", "Constraint check failure for pick.S");
		// Bounds share what a null `T` matched, so one call cannot read it as Int and as String.
		reject("InvalidNullSharedBound", "Constraint check failure for pick.U", "String should be Int");
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
		// Count each result so repeated calls with the same type cannot hide a missing one.
		final counts = new haxe.ds.StringMap<Int>();
		function inspect(node:TypedExpr):Void {
			final declaration = node.getDeclaration();
			if (node.getTag() == Call && declaration != null) {
				final name = declaration.getSignature().getName();
				if (name == "downcast" || name == "open" || name == "arrayOf") {
					final key = node.getType().getSemanticKey();
					// A `cast null` class argument leaves the result as this call's own open `S`.
					final entry = name + "=" + (StringTools.startsWith(key, "open-method-parameter:") ? "open-method-parameter" : key);
					counts.set(entry, (counts.exists(entry) ? counts.get(entry) : 0) + 1);
				}
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
			"downcast=nominal:Shapes.Sub" => 5,
			"downcast=open-method-parameter" => 2,
			"downcast=nominal:Shapes.Base" => 1,
			"open=primitive:String" => 1,
			"arrayOf=nominal:Array<primitive:Int>" => 1,
			"arrayOf=nominal:Array<dynamic>" => 1,
			"arrayOf=nominal:Array<nullable:dynamic>" => 1,
			"arrayOf=nominal:Any" => 1
		];
		final actual = [for (entry in counts.keys()) entry + "*" + counts.get(entry)];
		actual.sort(Reflect.compare);
		final wanted = [for (entry in expected.keys()) entry + "*" + expected.get(entry)];
		wanted.sort(Reflect.compare);
		if (actual.join("|") != wanted.join("|"))
			throw "valid dependent-bound calls lost their result types: " + actual.join("|");
		Sys.println("DOWNCAST_DYNAMIC_CONSTRAINT_ACCEPT:PASS");
	}

	/** A dependent bound that upstream rejects must still fail; hxhx names the failing parameter. */
	static function reject(module:String, diagnostic:String, ?upstreamDiagnostic:String):Void {
		upstream(module, upstreamDiagnostic == null ? diagnostic : upstreamDiagnostic);
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
