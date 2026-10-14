/** Compare JavaScript abstract storage with independently specified upstream behavior. */
class M14JsAbstractValueTest {
	/** Equal printed syntax cannot authorize another executable or a changed typed body. */
	static function ownership():Void {
		final source = 'abstract Key(String) from String to String { public function new(value:String) this=value; public function read():String return this; }'
			+ 'class Main { static var initial:Key=new Key("field");'
			+ 'static function inspect():String { var value:Key=new Key("value"); var converted:String=value; return value.read(); }'
			+ 'static function other():Void {} static function main():Void { inspect(); }}';
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final program = MacroStage.expandProgram([typed], []);
		final plan = new backend.js.JsAbstractValuePlan(program, new backend.js.JsClassInheritancePlan(program));
		final owners = program.getTypedModules()[0].getBackendProjection().getClasses();
		final functions = [for (owner in owners) for (fn in owner.getFunctions()) fn];
		final selected = functions.filter(fn -> HxFunctionDecl.getName(fn.getDeclaration()) == "inspect")[0];
		final other = functions.filter(fn -> HxFunctionDecl.getName(fn.getDeclaration()) == "other")[0];
		final scope = plan.forFunction(selected);
		final expressions = new Array<HxExpr>();
		TypedBackendSourceWalk.functionDeclaration(selected.getDeclaration(), expression -> expressions.push(expression), _ -> {});
		final construction = expressions.filter(expression -> expression.match(ENew(_, _)))[0];
		final call = expressions.filter(expression -> TypedExactCallSource.decodeInstance(expression) != null)[0];
		final conversion = expressions.filter(expression -> selected.findCast(expression) != null)[0];
		if (construction == null || call == null || conversion == null)
			throw "Abstract ownership fixture lost an exact operation: " + Std.string({construction: construction, call: call, conversion: conversion});
		final castFact = selected.findCast(conversion);
		if (!scope.isAbstractOwner("Main.Key") || scope.isAbstractOwner("Main") || scope.isAbstractOwner("Key"))
			throw "Abstract dispatch lost its exact canonical owner classification";
		if (!castFact.isRepresentationPreserving()
			|| castFact.getSourceType().getNominalIdentity().getCanonicalName() != "Main.Key"
			|| castFact.getTargetType().getSemanticKey() != "primitive:String"
			|| scope.constructorReference(construction) == null
			|| scope.methodReference(scope.requireCall(call).getDeclaration()) == null)
			throw "Abstract operations lost their selected declaration or conversion types";
		final copiedConstruction:HxExpr = switch construction {
			case ENew(name, arguments): ENew(name, arguments.copy());
			case _: throw "missing construction";
		};
		final copiedCall:HxExpr = switch call {
			case ECall(callee, arguments): ECall(callee, arguments.copy());
			case _: throw "missing call";
		};
		final copiedCast:HxExpr = switch conversion {
			case ECast(operand, hint): ECast(operand, hint);
			case _: throw "missing conversion";
		};
		reject(() -> scope.constructorReference(copiedConstruction));
		reject(() -> scope.requireCall(copiedCall));
		if (selected.findCast(copiedCast) != null || other.findCast(conversion) != null)
			throw "Shared cast lookup admitted a copied or foreign cast";
		reject(() -> plan.forFunction(other).constructorReference(construction));
		reject(() -> plan.forFunction(other).requireCall(call));
		final foreign = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		for (owner in foreign.getBackendProjection().getClasses())
			for (fn in owner.getFunctions())
				reject(() -> plan.forFunction(fn));
		final fields = [for (owner in owners) for (field in owner.getFieldInitializers()) field];
		if (fields.length != 1 || plan.forInitializer(fields[0]).constructorReference(fields[0].getExpression()) == null)
			throw "Abstract initializer lost its exact construction";
		reject(() -> plan.forInitializer(fields[0]).constructorReference(construction));
		// Equal syntax must not keep an old cast authorized after the projected
		// statement replaces it with a different expression object.
		final body = HxFunctionDecl.getBody(selected.getDeclaration());
		var replaced = false;
		for (i in 0...body.length)
			switch body[i] {
				case SVar(name, hint, init, position, metadata) if (init == conversion):
					final original = body[i];
					body[i] = SVar(name, hint, copiedCast, position, metadata);
					reject(() -> selected.findCast(conversion));
					body[i] = original;
					replaced = true;
				case _:
			}
		if (!replaced)
			throw "Abstract cast replacement control did not run";
		// A changed authored body invalidates all three previously admitted operations.
		for (owner in typed.getTypedClasses())
			for (fn in owner.getFunctions())
				if (HxFunctionDecl.getName(fn.getSourceDeclaration()) == "inspect")
					HxFunctionDecl.getBody(fn.getSourceDeclaration()).push(SExpr(EInt(99), HxPos.unknown()));
		reject(() -> scope.constructorReference(construction));
		reject(() -> scope.requireCall(call));
		reject(() -> selected.findCast(conversion));
		Sys.println("JS_ABSTRACT_OWNERSHIP:PASS");
	}

	static function reject(action:Void->Void):Void {
		try {
			action();
		} catch (_:haxe.Exception) {
			return;
		}
		throw "Abstract plan accepted a copied, foreign, or stale occurrence";
	}

	static function main():Void {
		ownership();
		final root = "test/fixtures/js_abstract_values";
		final expected = sys.io.File.getContent(root + "/expected.stdout");
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != expected)
			throw "Upstream abstract storage differs: " + output + errors;
		Sys.println("UPSTREAM_JS_ABSTRACT_VALUES:PASS");
		final path = root + "/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		Sys.println("JS_ABSTRACT_VALUES:PASS");
	}
}
