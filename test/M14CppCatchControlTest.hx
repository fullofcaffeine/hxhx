/** Execute complete authored carrier handlers through the production function emitter. */
class M14CppCatchControlTest {
	static function main():Void {
		ownership();
		M14SourceMapComprehensionManagedTest.runFixture({
			sourceRoot: "test/oracle/cpp_catch_control_seed",
			module: "CatchControl",
			observer: "test/cpp_managed_heap/CatchControlObserver.cpp",
			output: ".tmp/cpp-catch-control",
			marker: "CPP_CATCH_CONTROL_NATIVE:PASS"
		});
		Sys.println("CPP_CATCH_CONTROL:PASS");
	}

	/** Reject reconstructed statements, another projection, stale bodies, and missing implicit-use facts. */
	static function ownership():Void {
		final fixture = CppResolvedFixture.load({sourceRoot: "test/oracle/cpp_catch_control_seed", mainModule: "CatchControl", requiredModules: []});
		final fn = fixture.main.getTypedClasses()[0].getFunctions().filter(value -> HxFunctionDecl.getName(value.getSourceDeclaration()) == "select")[0];
		final projection = TypedBodySource.functionProjection(fn);
		final plan = new backend.cpp.CppManagedStoragePlan(projection);
		final access = new backend.cpp.CppManagedLocalAccess({
			projection: projection,
			plan: plan,
			owner: Root(projection),
			parameters: ["seed"],
			temporaryPrefix: "hxhx_parameters_catch_negative_"
		});
		final rooted = new backend.cpp.CppManagedRootedExpression({
			owner: CallableBody(access),
			heap: "heap",
			temporaryPrefix: "hxhx_value_catch_negative_",
			resolve: _ -> throw "no closure in select"
		});
		final original = projection.getBody()[0];
		final copied:HxStmt = switch original {
			case STry(body, clauses, position): STry(body, clauses.copy(), position);
			case _: throw "catch ownership fixture lacks its root try";
		};
		reject(() -> rooted.renderTry(Statement(copied), "", _ -> [], (_, _) -> []), "not an exact statement");
		final body = projection.getBody();
		body.push(SExpr(EInt(99), HxPos.unknown()));
		reject(() -> rooted.renderTry(Statement(original), "", _ -> [], (_, _) -> []), "projection was mutated");
		body.pop();
		plan.assertCurrent();
		final path = "test/oracle/cpp_catch_control_seed/CatchControl.hx";
		final module = new ResolvedModule("CatchControl", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final otherFn = TyperStage.typeResolvedModule(module, TyperIndex.build([module]))
			.getTypedClasses()[0].getFunctions().filter(value -> HxFunctionDecl.getName(value.getSourceDeclaration()) == "select")[0];
		final other = TypedBodySource.functionProjection(otherFn);
		reject(() -> rooted.renderTry(Statement(other.getBody()[0]), "", _ -> [], (_, _) -> []), "not an exact statement");
		final otherPlan = new backend.cpp.CppManagedStoragePlan(other);
		final otherAccess = new backend.cpp.CppManagedLocalAccess({
			projection: other,
			plan: otherPlan,
			owner: Root(other),
			parameters: ["seed"],
			temporaryPrefix: "hxhx_parameters_missing_use_"
		});
		final missing = new backend.cpp.CppManagedRootedExpression({
			owner: CallableBody(otherAccess),
			heap: "heap",
			temporaryPrefix: "hxhx_value_missing_use_",
			resolve: _ -> throw "no closure in select"
		});
		reject(() -> missing.renderTry(Statement(other.getBody()[0]), "", _ -> [], (_, _) -> []), "exact typed implicit use");
	}

	static function reject(action:Void->Void, message:String):Void {
		try
			action()
		catch (failure:haxe.Exception) {
			if (failure.message.indexOf(message) >= 0)
				return;
			throw failure;
		}
		throw "catch emission accepted invalid ownership";
	}
}
