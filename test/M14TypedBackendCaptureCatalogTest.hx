/** Backend capture facts must belong to the actual published closure objects and both typed revisions. */
class M14TypedBackendCaptureCatalogTest {
	static function projection(source:String):TypedBackendFunctionProjection {
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final fn = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved])).getTypedClasses()[0].getFunctions()[0];
		return TypedBodySource.functionProjection(fn);
	}

	static function check(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function rejected(action:Void->Void, diagnostic:String):Void {
		var observed = "";
		try {
			action();
		} catch (error:String) {
			observed = error;
		}
		check(observed.indexOf(diagnostic) >= 0, "expected " + diagnostic + ", received " + observed);
	}

	/** Equal compact hashes must not let edited parsed syntax retain an older capture plan. */
	static function parsedCollision():Void {
		final projected = projection("class Main { static function make():Void->Int { var Aa = 11; var BB = 22; return function():Int { return Aa; }; } }");
		final catalog = projected.requireCaptureCatalog();
		final source = @:privateAccess projected.source;
		final body = HxFunctionDecl.getBody(source.getSourceDeclaration());
		final before = TypedBodyFingerprint.forStatements(body);
		var changed = false;
		for (statement in body)
			TypedBackendSourceWalk.statement(statement, node -> {
				switch node {
					case ESourceGroup(values, _):
						for (index in 0...values.length)
							switch values[index] {
								case EReturn(EIdent("Aa")):
									values[index] = EReturn(EIdent("BB"));
									changed = true;
								case EReturn(EEnumValue("Aa")):
									values[index] = EReturn(EEnumValue("BB"));
									changed = true;
								case _:
							}
					case _:
				}
			}, _ -> {});
		check(changed && before == TypedBodyFingerprint.forStatements(body), "parsed-source hash collision was not exercised");
		rejected(() -> catalog.getPlan(), "typed body revision mismatch");
		rejected(() -> source.withBody(source.getBody()), "typed body revision mismatch");
	}

	/** Capture plans and expression revisions must distinguish exact Float payloads. */
	static function floatRevision(first:Float, second:Float):Void {
		final firstBits = haxe.io.FPHelper.doubleToI64(first);
		final firstHigh = firstBits.high;
		final firstLow = firstBits.low;
		final secondBits = haxe.io.FPHelper.doubleToI64(second);
		check(firstHigh != secondBits.high || firstLow != secondBits.low, "distinct input Float payloads were not exercised");
		final projected = projection("class Main { static function make():Float { return 1.0; } }");
		final source = @:privateAccess projected.source;
		final firstExpr = TypedExpr.floatLiteral(first, TyType.fromHintText("Float"), null);
		final secondExpr = TypedExpr.floatLiteral(second, TyType.fromHintText("Float"), null);
		final firstFunction = source.withBody(new TypedFunctionBody([TypedStmt.returnValue(firstExpr, null)], source.getBody().getSourceFingerprint()));
		final secondFunction = source.withBody(new TypedFunctionBody([TypedStmt.returnValue(secondExpr, null)], source.getBody().getSourceFingerprint()));
		final plan = TypedCapturePlan.analyze(firstFunction);
		rejected(() -> plan.assertCurrent(secondFunction), "another typed function revision");
		check(CompilerTypedTreeRevision.expression(source.getStableIdentity(),
			firstExpr) != CompilerTypedTreeRevision.expression(source.getStableIdentity(), secondExpr),
			"typed expression revision rounded a Float payload");
	}

	public static function run():Void {
		callableAnnotations();
		final source = "class Main { static function make():Int->Int { var calls = 0; function count(n:Int):Int { calls++; return n == 0 ? calls : count(n-1); } return count; } }";
		final projected = projection(source);
		final catalog = projected.requireCaptureCatalog();
		check(catalog == projected.requireCaptureCatalog(), "function projection rebuilt its capture catalog");
		final plan = catalog.getPlan();
		check(plan.sourceBodyRevision == projected.getBodyRevision(), "catalog lost the original typed revision");
		final closure = catalog.getExpressions()[0];
		check([for (binding in catalog.require(closure).getCaptures()) binding.getSourceName()].join(",") == "calls,count",
			"projected recursion lost its exact captured bindings");
		catalog.getExpressions().pop();
		check(catalog.getExpressions().length == 1, "catalog exposed a mutable occurrence array");
		final other = projection(source).requireCaptureCatalog();
		rejected(() -> catalog.require(other.getExpressions()[0]), "not an exact occurrence");
		check(catalog.requireCallableType(closure).getSemanticKey() == "function:(primitive:Int)->primitive:Int", "catalog lost the typed closure signature");
		rejected(() -> catalog.requireCallableType(other.getExpressions()[0]), "not an exact occurrence");
		rejected(() -> catalog.assertOwner(projected.getStableIdentity(), "stale"), "another function or source revision");
		switch closure {
			case ELambda(_, ELoweredControl(FunctionBody, _, values, _)):
				values.push(EInt(73));
			case _:
				throw "expected projected function body";
		}
		rejected(() -> catalog.require(closure), "projection was mutated");
		rejected(() -> catalog.requireCallableType(closure), "projection was mutated");

		final quoted = projection("class Main { static function make():Void { var syntax = macro function(quoted:Int):Int { return quoted; }; } }");
		check(quoted.requireCaptureCatalog().getExpressions().length == 0, "quotation entered the executable closure catalog");
		final pending = projection(source);
		var changed = false;
		for (statement in pending.getBody())
			TypedBackendSourceWalk.statement(statement, expression -> {
				switch expression {
					case ELoweredControl(FunctionBody, _, values, _) if (!changed):
						values.push(EInt(42));
						changed = true;
					case _:
				}
			}, _ -> {});
		check(changed, "test did not find the mutable projected function body");
		rejected(() -> pending.requireCaptureCatalog(), "exact lowered function projection");

		// A body can replace a child with an equal-shaped copy without changing its
		// fingerprint. The old object must lose authority even in that case.
		final nested = projection("class Main { static function make(seed:Int):Void->(Void->Int) { return function():Void->Int { return function():Int { return seed; }; }; } }");
		final nestedCatalog = nested.requireCaptureCatalog();
		final inner = nestedCatalog.getExpressions()[1];
		final outer = nestedCatalog.getExpressions()[0];
		final copy:HxExpr = switch inner {
			case ELambda(args, body, signature): ELambda(args.copy(), body, signature);
			case _: throw "expected inner lambda";
		};
		final before = TypedBodyFingerprint.forStatements(nested.getBody());
		var replaced = false;
		TypedBackendSourceWalk.expression(outer, node -> {
			switch node {
				case ELoweredControl(Return, _, values, _):
					for (index in 0...values.length)
						switch values[index] {
							case ECast(value, hint) if (value == inner):
								values[index] = ECast(copy, hint);
								replaced = true;
							case _ if (values[index] == inner):
								values[index] = copy;
								replaced = true;
							case _:
						}
				case _:
			}
		});
		check(replaced
			&& before == TypedBodyFingerprint.forStatements(nested.getBody()), "equal-shaped closure replacement was not exercised");
		rejected(() -> nestedCatalog.require(inner), "closure occurrences changed");

		final colliding = projection("class Main { static function make():Void->Int { var Aa = 11; var BB = 22; return function():Int { return Aa; }; } }");
		final collisionCatalog = colliding.requireCaptureCatalog();
		final collisionClosure = collisionCatalog.getExpressions()[0];
		final compactBefore = TypedBodyFingerprint.forStatements(colliding.getBody());
		var collisionChanged = false;
		TypedBackendSourceWalk.expression(collisionClosure, node -> {
			switch node {
				case ELoweredControl(Return, _, values, _):
					for (index in 0...values.length)
						switch values[index] {
							case EIdent("Aa"):
								values[index] = EIdent("BB");
								collisionChanged = true;
							case _:
						}
				case _:
			}
		});
		check(collisionChanged && compactBefore == TypedBodyFingerprint.forStatements(colliding.getBody()),
			"the polynomial collision must be demonstrated independently of exact capture validation");
		rejected(() -> collisionCatalog.require(collisionClosure), "projection was mutated");

		final patternA:Array<HxStmt> = [SExpr(ELoweredControl(Switch([PString("Aa")]), "", [EInt(1)], null), null)];
		final patternB:Array<HxStmt> = [SExpr(ELoweredControl(Switch([PString("BB")]), "", [EInt(1)], null), null)];
		check(TypedBodyFingerprint.forStatements(patternA) == TypedBodyFingerprint.forStatements(patternB), "lowered switch collision was not exercised");
		check(TypedBodyFingerprint.exactStatements(patternA) != TypedBodyFingerprint.exactStatements(patternB), "exact identity reused a pattern hash");
		final zero:Array<HxStmt> = [SExpr(EFloat(0.0), null)];
		final negativeZero:Array<HxStmt> = [SExpr(EFloat(haxe.io.FPHelper.i64ToDouble(0, 0x80000000)), null)];
		check(TypedBodyFingerprint.exactStatements(zero) != TypedBodyFingerprint.exactStatements(negativeZero), "exact metadata lost the zero sign bit");
		final one:Array<HxStmt> = [SExpr(EFloat(1.0), null)];
		final adjacent:Array<HxStmt> = [SExpr(EFloat(haxe.io.FPHelper.i64ToDouble(1, 0x3ff00000)), null)];
		check(TypedBodyFingerprint.exactStatements(one) != TypedBodyFingerprint.exactStatements(adjacent), "exact metadata rounded adjacent finite values");
		parsedCollision();
		floatRevision(0.0, haxe.io.FPHelper.i64ToDouble(0, 0x80000000));
		floatRevision(1.0, haxe.io.FPHelper.i64ToDouble(1, 0x3ff00000));
		floatRevision(haxe.io.FPHelper.i64ToDouble(1, 0x7ff80000), haxe.io.FPHelper.i64ToDouble(2, 0x7ff80000));
		Sys.println("TYPED_BACKEND_CAPTURE_CATALOG:PASS");
	}

	/** Authored casts, equal-shaped copies, and stale wrapper objects cannot authorize elision. */
	static function callableAnnotations():Void {
		final projected = projection("class Main { static function make():Void->(Void->Int) { return function():Void->Int { return cast(function():Int { return 1; }); }; } }");
		final catalog = projected.requireCaptureCatalog();
		final casts = new Array<HxExpr>();
		for (statement in projected.getBody())
			TypedBackendSourceWalk.statement(statement, value -> {
				switch value {
					case ECast(_, _): casts.push(value);
					case _:
				}
			}, _ -> {});
		check(casts.length == 3, "fixture must retain authored cast and compiler annotations separately");
		final closure = catalog.getExpressions()[1];
		check(catalog.requireAscribedClosure(casts[2]) == closure, "compiler annotation lost its exact closure");
		rejected(() -> catalog.requireAscribedClosure(casts[1]), "not an exact compiler-added");
		final copy:HxExpr = switch casts[2] {
			case ECast(value, hint): ECast(value, hint);
			case _: throw "expected callable annotation";
		};
		rejected(() -> catalog.requireAscribedClosure(copy), "not an exact compiler-added");
		var replaced = false;
		for (statement in projected.getBody())
			TypedBackendSourceWalk.statement(statement, value -> {
				switch value {
					case ELoweredControl(Return, _, values, _):
						for (index in 0...values.length)
							switch values[index] {
								case ECast(inner, hint) if (inner == casts[2]):
									values[index] = ECast(copy, hint);
									replaced = true;
								case _:
							}
					case _:
				}
			}, _ -> {});
		check(replaced, "fixture did not replace the callable annotation");
		rejected(() -> catalog.requireAscribedClosure(casts[2]), "annotation occurrences changed");
	}

	static function main():Void
		run();
}
