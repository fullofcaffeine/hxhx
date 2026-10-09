#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.macros.OcamlNativeSurfaceQuery;
import reflaxe.ocaml.macros.OcamlNativeSurfaceQuery.NativeSurfaceCapture;
import reflaxe.ocaml.macros.OcamlNativeSurfaceScan;

/** Compares whole decoded bodies in fresh processes and tests every cache invalidation boundary. */
class NativeSurfaceBodyFixture {
	public static function run():Void {
		final owners = [classRef("BodySurfaceCases"), classRef("BodySurfaceCases.SurfaceOwner")];
		final classValue = Context.typeExpr(macro OwnedSurfaceCases.EnumStatics);
		final pureValue = Context.typeExpr(macro OwnedSurfaceCases.PureEnumStatics);
		final abstractValue = Context.typeExpr(macro OwnedSurfaceCases.PureAbstractStatics);
		final nullValue = Context.typeExpr(macro(null : Null<String>));
		final nativeNullValue = Context.typeExpr(macro(null : Null<ocaml.SurfaceMarker>));
		var declarations:Array<ModuleType> = [];
		Context.onGenerate(types -> {
			for (type in types)
				switch type {
					case TInst(r, _): declarations.push(TClassDecl(r));
					case TEnum(r, _): declarations.push(TEnumDecl(r));
					case TType(r, _): declarations.push(TTypeDecl(r));
					case TAbstract(r, _): declarations.push(TAbstract(r));
					case _: throw new haxe.Exception("Expected declaration");
				}
		});
		Context.onAfterGenerate(() -> {
			final capture = OcamlNativeSurfaceQuery.captureDeclarations(declarations);
			final reference = Context.defined("native_surface_reference");
			var hits = 0;
			var enumValues = 0;
			for (owner in owners) {
				for (field in owner.get().statics.get()) {
					final body = field.expr();
					if (body == null)
						continue;
					final scan = new OcamlNativeSurfaceScan(() -> capture, true);
					var index = 0;
					function visit(expression:TypedExpr):Void {
						final mask = reference ? referenceMask(expression, 3) : scan.find(expression, 3);
						Sys.println('BODY_SURFACE:${field.name}:${index++}:$mask');
						TypedExprTools.iter(expression, visit);
					}
					visit(body);
					hits += scan.classHits;
					// This separate walk starts after the body scan has finished using its cache.
					if (!reference) {
						final query = new OcamlNativeSurfaceQuery(capture);
						function checkEnumValue(expression:TypedExpr):Void {
							switch expression.t {
								case TEnum(_, _):
									final expected = NativeSurfaceReference.find(expression.t, 16, 3);
									check(query.findExpression(expression, 16, 3) == expected && query.enumPathReads > 0,
										"compiler enum values avoid constructor encoding");
									check(query.find(expression.t, 16, 3) == expected && query.enumPathReads == 0,
										"raw type queries retain the original enum reads");
									enumValues++;
								case _:
							}
							TypedExprTools.iter(expression, checkEnumValue);
						}
						checkEnumValue(body);
					}
				}
			}
			if (!reference) {
				check(hits >= 4, "real decoded bodies must reuse repeated class references");
				check(enumValues >= 4, "real enum values must exercise compiler-origin reads");
				checkNamedBodies(capture, nullValue, nativeNullValue);
				checkBarriers(capture, classValue, nullValue);
				checkZeroAndModule(capture, classValue, pureValue, abstractValue);
			}
			Sys.println("NATIVE_SURFACE_BODY:PASS");
		});
	}

	/** Named-body reuse skips completed work, never actual arguments, masks, or depth charges. */
	static function checkNamedBodies(capture:NativeSurfaceCapture, nullValue:TypedExpr, nativeNullValue:TypedExpr):Void {
		final scan = new OcamlNativeSurfaceScan(() -> capture, true);
		check(scan.find(nullValue, 3) == 0, "pure nullable value");
		check(@:privateAccess scan.query.bodyExpansions > 0, "first nullable body must expand");
		check(scan.find(nullValue, 3) == 0 && @:privateAccess scan.query.bodyExpansions == 0, "repeat nullable body must reuse completed result");
		check(scan.find(nativeNullValue, 3) == 1, "different actual argument must remain visible");
		check(scan.find(nullValue, 1) == 0 && @:privateAccess scan.query.bodyExpansions > 0, "named-body mask must be exact");
		scan.invalidate();
		check(scan.find(nullValue, 3) == 0 && @:privateAccess scan.query.bodyExpansions > 0, "callback must clear named results");
		final strict = new OcamlNativeSurfaceScan(() -> capture, false);
		strict.find(nullValue, 3);
		check(strict.find(nullValue, 3) == 0 && @:privateAccess strict.query.bodyExpansions > 0, "strict scan must recompute named bodies");
		final nextBody = new OcamlNativeSurfaceScan(() -> capture, true);
		check(nextBody.find(nullValue, 3) == 0 && @:privateAccess nextBody.query.bodyExpansions > 0, "next body must recompute named results");
		final query = new OcamlNativeSurfaceQuery(capture);
		query.find(nullValue.t, 16, 3);
		check(query.find(nullValue.t, 16, 3) == 0 && query.bodyExpansions > 0, "ordinary query must remain independent");
		final results:Map<String, Int> = [];
		@:privateAccess query.findBodyType(nullValue.t, 3, 3, results);
		check(@:privateAccess query.findBodyType(nullValue.t, 16, 3, results) == 0
			&& query.bodyExpansions > 0, "named-body depth must be exact");
		check(@:privateAccess query.findBodyType(nativeNullValue.t, 1, 3, results) == 0, "depth one cannot see nullable argument");
		check(@:privateAccess query.findBodyType(nativeNullValue.t, 2, 3, results) == 1, "depth two sees nullable argument");
		var effects = 0;
		final lazyArgument:Type = switch nativeNullValue.t {
			case TAbstract(reference, arguments): TAbstract(reference, [
					TLazy(() -> {
						effects++;
						check(! @:privateAccess scan.completedBodies.keys().hasNext(), "actual argument invalidates before body lookup");
						return arguments[0];
					})
				]);
			case _: throw new haxe.Exception("Expected nullable abstract");
		};
		check(scan.find({expr: TConst(TNull), t: lazyArgument, pos: nullValue.pos}, 3) == 1 && effects == 1,
			"cached nullable body must not hide argument effects");
	}

	/** Zero is a completed result; an unknown module getter still invalidates earlier class results. */
	static function checkZeroAndModule(capture:NativeSurfaceCapture, classValue:TypedExpr, pureValue:TypedExpr, abstractValue:TypedExpr):Void {
		final pure = new OcamlNativeSurfaceScan(() -> capture, true);
		check(pure.find(pureValue, 3) == 0 && pure.find(pureValue, 3) == 0 && pure.classHits == 1, "zero class results must be reusable");
		final declarations:Map<String, Bool> = [];
		for (key => value in capture.declarations)
			declarations.set(key, value);
		check(declarations.remove("abstract:OwnedSurfaceCases:PureAbstractStatics"), "expected captured abstract owner");
		final partial:NativeSurfaceCapture = {declarations: declarations, parameters: capture.parameters};
		final scan = new OcamlNativeSurfaceScan(() -> partial, true);
		scan.find(classValue, 3);
		check(scan.find(abstractValue, 3) == 0, "unknown pure module preserves mask");
		check(scan.find(classValue, 3) == 3 && scan.classQueries == 2 && scan.classHits == 0, "module read must invalidate earlier class results");
	}

	/** The prior ordered expression contract remains the independent comparison source. */
	static function referenceMask(expression:TypedExpr, requested:Int):Int {
		var found = NativeSurfaceReference.find(expression.t, 16, requested);
		final remaining = requested & ~found;
		if (remaining == 0)
			return found;
		return found | switch expression.expr {
			case TTypeExpr(module):
				final pack = switch module {
					case TClassDecl(r): r.get().pack;
					case TEnumDecl(r): r.get().pack;
					case TTypeDecl(r): r.get().pack;
					case TAbstract(r): r.get().pack;
				};
				((pack[0] == "ocaml" ? 1 : 0) | (pack[0] == "haxe" && pack[1] == "atomic" ? 2 : 0)) & remaining;
			case TVar(variable, _): NativeSurfaceReference.find(variable.t, 16, remaining);
			case TFunction(fn):
				var arguments = 0;
				for (argument in fn.args) {
					arguments |= NativeSurfaceReference.find(argument.v.t, 16, remaining & ~arguments);
					if (arguments == remaining)
						break;
				}
				arguments;
			case _: 0;
		};
	}

	/** Explicit state assertions distinguish invalidation from coincidentally equal masks. */
	static function checkBarriers(capture:NativeSurfaceCapture, classValue:TypedExpr, nullValue:TypedExpr):Void {
		var captures = 0;
		final dormant = new OcamlNativeSurfaceScan(() -> {
			captures++;
			return capture;
		}, true);
		check(dormant.find(classValue, 0) == 0 && captures == 0, "zero mask must not read inventory");
		for (kind in ["lazy", "mono", "unknown", "throwing"]) {
			final scan = new OcamlNativeSurfaceScan(() -> capture, true);
			scan.find(nullValue, 3);
			check(scan.find(classValue, 3) == 3 && scan.find(classValue, 3) == 3 && scan.classHits == 1, "warm class result");
			var effects = 0;
			function effect():Void {
				effects++;
				if (kind != "unknown") {
					check(! @:privateAccess scan.completedClasses.keys().hasNext(), "invalidate before callback");
					check(! @:privateAccess scan.completedBodies.keys().hasNext(), "invalidate named bodies before callback");
				}
			}
			final type:Type = switch kind {
				case "lazy": TLazy(() -> {
						effect();
						return TDynamic(null);
					});
				case "throwing": TLazy(() -> {
						effect();
						throw new haxe.Exception("expected body barrier");
					});
				case "mono": TMono({
						get: () -> {
							effect();
							return null;
						},
						toString: () -> "unresolved"
					});
				case _:
					final definition = classRef("String").get();
					definition.name = "UncapturedBodyBarrier";
					TInst({
						get: () -> {
							effect();
							return definition;
						},
						toString: () -> definition.name
					}, []);
			};
			final expression:TypedExpr = {expr: TConst(TNull), t: type, pos: classValue.pos};
			try {
				scan.find(expression, 3);
				check(kind != "throwing", "expected barrier failure");
			} catch (error:haxe.Exception) {
				if (kind != "throwing")
					throw error;
				check(kind == "throwing" && error.message == "expected body barrier", "preserve barrier exception");
			}
			check(! @:privateAccess scan.completedBodies.keys().hasNext(), "barrier must leave no named results");
			check(effects == 1 && scan.find(classValue, 3) == 3 && scan.classQueries == 2 && scan.classHits == 1, kind
				+ " must discard earlier class results");
		}
		final masks = new OcamlNativeSurfaceScan(() -> capture, true);
		check(masks.find(classValue, 1) == 1 && masks.find(classValue, 3) == 3 && masks.classQueries == 2, "requested mask is part of the key");
		check(masks.find(classValue, 1) == 1 && masks.classHits == 1, "reuse exact requested mask");
		masks.invalidate();
		check(masks.find(classValue, 1) == 1 && masks.classQueries == 3 && masks.classHits == 1,
			"caller callback boundary must discard completed class results");
		final strict = new OcamlNativeSurfaceScan(() -> capture, false);
		strict.find(classValue, 3);
		strict.find(classValue, 3);
		check(strict.classHits == 0, "strict scans must not reuse class results");
		final nextBody = new OcamlNativeSurfaceScan(() -> capture, true);
		nextBody.find(classValue, 3);
		check(nextBody.classHits == 0 && nextBody.classQueries == 1, "new field body has no previous result");
	}

	static function classRef(path:String):Ref<ClassType> {
		return switch Context.getType(path) {
			case TInst(reference, _): reference;
			case _: throw new haxe.Exception("Expected class");
		};
	}

	static function check(condition:Bool, label:String):Void {
		if (!condition)
			throw new haxe.Exception(label);
	}
}
#end
