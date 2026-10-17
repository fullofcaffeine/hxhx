/** Compare real guarded control with upstream, then force collection under native sanitizers. */
class M14CppGuardedSwitchTest {
	static function main():Void {
		final root = "test/oracle/cpp_guarded_switch_seed";
		final upstream = new sys.io.Process("haxe", ["-cp", root, "-main", "Main", "--interp"]);
		final stdout = upstream.stdout.readAll();
		final stderr = upstream.stderr.readAll().toString();
		final exit = upstream.exitCode();
		upstream.close();
		if (exit != 0 || stderr.length != 0 || stdout.compare(sys.io.File.getBytes(root + "/expected.stdout")) != 0)
			throw "upstream guarded switch differs from its independent expectation: " + stdout.toString() + stderr;
		Sys.println("CPP_GUARDED_SWITCH_UPSTREAM:PASS");
		final fixture = CppResolvedFixture.load({sourceRoot: root, mainModule: "GuardedSwitch", requiredModules: ["Array"]});
		final program = new backend.cpp.CppTypedProgramProjection(CppResolvedFixture.prepare(fixture));
		final owner = program.requireClass(program.requireClassIdentity("GuardedSwitch"));
		final classes = new backend.cpp.CppManagedClassStorage(program);
		final enums = new backend.cpp.CppManagedEnumDescriptors(program);
		final entries:Array<backend.cpp.CppManagedProgramEmitter.CppManagedProgramFunction> = [
			for (projection in owner.getFunctions()) {
				final name = projection.requireSemanticDeclaration().getSignature().getName();
				{projection: projection, rootSymbol: "generated_" + name, symbolPrefix: "hxhx_function_" + name};
			}
		];
		final emitter = new backend.cpp.CppManagedProgramEmitter({
			functions: entries,
			output: [],
			classes: classes,
			casts: classes.casts,
			enums: enums,
			defaultValue: type -> backend.cpp.CppManagedStaticDefault.render(program, type)
		});
		final header = emitter.render();
		if (header != emitter.render())
			throw "guarded switch emission is not deterministic";
		program.assertCurrent();
		ownership(owner);
		dynamicOwnership(owner);
		final output = ".tmp/cpp-guarded-switch";
		sys.FileSystem.createDirectory(output);
		new backend.cpp.CppManagedRuntime().publish(output);
		sys.io.File.saveContent(output + "/Generated.hpp", '#include "ManagedCallable.hpp"\n' + classes.render() + "\n" + enums.render() + "\n" + header);
		final compiler = Sys.getEnv("CXX") == null ? "clang++" : Sys.getEnv("CXX");
		if (Sys.command(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", [
			"90",
			compiler,
			"-std=c++17",
			"-Werror=return-type",
			"-fsyntax-only",
			"-I",
			output,
			"test/cpp_managed_heap/GuardedSwitchObserver.cpp"
		]) != 0)
			throw "guarded native functions lost a required return path";
		Sys.println("CPP_GUARDED_SWITCH_RETURN_PATHS:PASS");
		CppManagedAssertionFixture.sanitizers(output, "CPP_GUARDED_SWITCH", "test/cpp_managed_heap/GuardedSwitchObserver.cpp", "Generated.hpp");
		Sys.println("CPP_GUARDED_SWITCH:PASS");
	}

	/** Equal-looking source and stale projections cannot authorize new pattern storage. */
	static function ownership(owner:TypedBackendClassProjection):Void {
		final projection = owner.getFunctions().filter(fn -> HxFunctionDecl.getName(fn.getDeclaration()) == "scalar")[0];
		final plan = new backend.cpp.CppManagedStoragePlan(projection);
		final access = new backend.cpp.CppManagedLocalAccess({
			projection: projection,
			plan: plan,
			owner: Root(projection),
			parameters: ["seed"],
			temporaryPrefix: "hxhx_parameters_pattern_negative_"
		});
		final emitter = new backend.cpp.CppManagedRootedExpression({
			owner: CallableBody(access),
			heap: "heap",
			temporaryPrefix: "hxhx_value_pattern_negative_",
			resolve: _ -> throw "scalar has no closure"
		});
		var original:Null<HxExpr> = null;
		function visit(expression:HxExpr):Void {
			if (expression.match(ELoweredControl(PatternAttempts(_), _, _, _)))
				original = expression;
			TypedBackendSourceWalk.expressionChildren(expression, visit);
		}
		function statement(node:HxStmt):Void
			TypedBackendSourceWalk.statementChildren(node, visit, statement);
		for (node in projection.getBody())
			statement(node);
		if (original == null)
			throw "guarded ownership fixture lost its control occurrence";
		final copied:HxExpr = switch original {
			case ELoweredControl(kind, target, children, position): ELoweredControl(kind, target, children.copy(), position);
			case _: throw "guarded ownership fixture lost its lowered control";
		};
		reject(() -> emitter.renderPatternAttempts(copied, "", (_, _) -> []), "not an exact expression");
		final body = projection.getBody();
		body.push(SExpr(EInt(99), HxPos.unknown()));
		reject(() -> emitter.renderPatternAttempts(original, "", (_, _) -> []), "projection was mutated");
		body.pop();
		plan.assertCurrent();
		Sys.println("CPP_GUARDED_SWITCH_OWNERSHIP:PASS");
	}

	/** A Dynamic value requires an exact current condition; equal syntax cannot borrow that permission. */
	static function dynamicOwnership(owner:TypedBackendClassProjection):Void {
		final fn = owner.getFunctions().filter(fn -> fn.requireSemanticDeclaration().getSignature().getName() == "dynamicGuard")[0];
		final plan = new backend.cpp.CppManagedStoragePlan(fn);
		final access = new backend.cpp.CppManagedLocalAccess({
			projection: fn,
			plan: plan,
			owner: Root(fn),
			parameters: ["value"],
			temporaryPrefix: "hxhx_parameters_dynamic_negative_"
		});
		final emitter = new backend.cpp.CppManagedRootedExpression({
			owner: CallableBody(access),
			heap: "heap",
			temporaryPrefix: "hxhx_value_dynamic_negative_",
			resolve: _ -> throw "guard has no closure"
		});
		var original:Null<HxExpr> = null;
		TypedBackendSourceWalk.functionDeclaration(fn.getDeclaration(), value -> {
			final condition = fn.findCondition(value);
			if (condition != null && condition.type.isDynamic())
				original = value;
		}, _ -> {});
		if (original == null)
			throw "Dynamic guard lost its checked condition";
		emitter.renderControlValue(original, "bool");
		final copy:HxExpr = switch original {
			case EIdent(name): EIdent(name);
			case _: throw "Dynamic guard fixture changed its local condition";
		};
		reject(() -> emitter.renderControlValue(copy, "bool"), "not an exact expression");
		final body = fn.getBody();
		body.push(SExpr(EInt(99), HxPos.unknown()));
		reject(() -> emitter.renderControlValue(original, "bool"), "projection was mutated");
		body.pop();
		emitter.renderControlValue(original, "bool");
		Sys.println("CPP_DYNAMIC_GUARD_OWNERSHIP:PASS");
	}

	static function reject(action:Void->Void, diagnostic:String):Void {
		try
			action()
		catch (error:haxe.Exception) {
			if (error.message.indexOf(diagnostic) >= 0)
				return;
			throw error;
		}
		throw "guarded switch accepted foreign or stale ownership";
	}
}
