#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.ocaml.macros.OcamlNativeSurfaceQuery;
import reflaxe.ocaml.macros.OcamlNativeSurfaceQuery.NativeSurfaceCapture;

private typedef EffectCase = {final root:Type; final trace:Array<String>;};

/** Proves bounded native-family discovery against independent expectations and the old walker. */
class NativeSurfaceFixture {
	public static function run():Void {
		final recursive = Context.getType("SurfaceCases.RecursiveRecord");
		final positive = Context.getType("SurfaceCases.RecursiveNative");
		final template = Context.getType("SurfaceCases.EffectBody");
		final native = Context.getType("ocaml.SurfaceMarker");
		final atomic = Context.getType("haxe.atomic.SurfaceMarker");
		final ordinary = Context.getType("String");
		final genericNative = Context.typeof(macro(null : SurfaceCases.GenericRecord<ocaml.SurfaceMarker>));
		final genericOrdinary = Context.typeof(macro(null : SurfaceCases.GenericRecord<String>));
		final enumeration = Context.typeof(macro(null : SurfaceCases.ParameterEnum<ocaml.SurfaceMarker>));
		final abstraction = Context.getType("SurfaceCases.SurfaceAbstract");
		var modules:Array<ModuleType> = [];
		Context.onGenerate(types -> modules = [
			for (type in types)
				switch type {
					case TInst(reference, _):
						TClassDecl(reference);
					case TEnum(reference, _):
						TEnumDecl(reference);
					case TType(reference, _):
						TTypeDecl(reference);
					case TAbstract(reference, _):
						TAbstract(reference);
					case _:
						throw new haxe.Exception("Unexpected generation declaration");
				}
		]);
		Context.onAfterGenerate(() -> {
			final captured = OcamlNativeSurfaceQuery.captureDeclarations(modules);
			final query = new OcamlNativeSurfaceQuery(captured);
			check(query.find(native, 1, 3) == 1, "direct OCaml family");
			check(query.find(atomic, 1, 3) == 2, "direct atomic family");
			check(query.find(chain([native, atomic]), 2, 3) == 3, "both families");
			check(query.find(chain([native]), 1, 3) == 0, "depth boundary");
			check(query.find(genericNative, 2, 1) == 1, "actual generic parameter");
			check(query.find(positive, 3, 1) == 1, "native field after recursion");
			check(query.find(positive, 2, 1) == 0, "recursive alias depth charge");

			// Syntax conversion can stringify a custom reference while rejecting it.
			// Even a captured declaration name must not authorize that extra observation.
			for (useReference in [true, false]) {
				var enumReads = 0;
				var enumStrings = 0;
				final forwarded = switch enumeration {
					case TEnum(reference, parameters):
						TEnum({
							get: () -> {
								enumReads++;
								return reference.get();
							},
							toString: () -> {
								enumStrings++;
								return "ParameterEnum";
							}
						}, parameters);
					case _: throw new haxe.Exception("Expected enum fixture");
				};
				final mask = useReference ? NativeSurfaceReference.find(forwarded, 4, 3) : query.find(forwarded, 4, 3);
				check(mask == 1 && enumReads == 1 && enumStrings == 0, "enum conversion must not add reference observations");
			}

			final examples = [
				recursive,
				positive,
				genericNative,
				genericOrdinary,
				enumeration,
				abstraction,
				ordinary,
				native,
				atomic,
				TDynamic(null),
				TDynamic(native),
				chain([genericOrdinary, genericNative]),
				chain([chain([native]), native])
			];
			for (type in examples)
				for (depth in -1...9)
					for (mask in 0...4)
						check(query.find(type, depth, mask) == NativeSurfaceReference.find(type, depth, mask), 'differential depth=$depth mask=$mask');
			// Shared acyclic shapes exercise different remaining depths and masks.
			for (index in 0...24) {
				final shared = examples[index % examples.length];
				final graph = chain([chain([shared]), shared, examples[(index * 7) % examples.length]]);
				for (depth in 1...7)
					for (mask in 0...4)
						check(query.find(graph, depth, mask) == NativeSurfaceReference.find(graph, depth, mask), "shared graph differential");
			}

			compareEffects(captured, () -> {
				final trace:Array<String> = [];
				final lazy = TLazy(() -> {
					trace.push("lazy");
					return trace.length == 1 ? TDynamic(null) : native;
				});
				final alias = aliasBody(template, lazy).root;
				return {root: chain([alias, alias]), trace: trace};
			}, "lazy ancestor");
			compareEffects(captured, () -> {
				final trace:Array<String> = [];
				final alias = aliasBody(template, TDynamic(null));
				final lazy = TLazy(() -> {
					trace.push("mutate");
					alias.definition.type = native;
					return TDynamic(null);
				});
				return {root: chain([alias.root, lazy, alias.root]), trace: trace};
			}, "lazy sibling");
			compareEffects(captured, () -> {
				final trace:Array<String> = [];
				final mono:Type = TMono({
					get: () -> {
						trace.push("mono");
						return trace.length == 1 ? null : native;
					},
					toString: () -> "changing mono"
				});
				final alias = aliasBody(template, mono).root;
				return {root: chain([alias, alias]), trace: trace};
			}, "changing monomorph");
			compareEffects(captured, () -> {
				final trace:Array<String> = [];
				final mono = Context.makeMonomorph();
				final bind = TLazy(() -> {
					trace.push("bind");
					check(Context.unify(mono, native), "bind real mono");
					return TDynamic(null);
				});
				return {root: chain([mono, bind, mono]), trace: trace};
			}, "real monomorph binding");

			var effects = 0;
			final throwing = TLazy(() -> {
				effects++;
				throw new haxe.Exception("expected lazy failure");
			});
			check(query.find(throwing, 0, 3) == 0 && effects == 0, "zero depth skips thunk");
			check(query.find(chain([native, throwing]), 3, 1) == 1 && effects == 0, "residual mask skips thunk");
			try {
				query.find(throwing, 1, 1);
				throw new haxe.Exception("Expected lazy failure");
			} catch (error:haxe.Exception) {
				check(error.message == "expected lazy failure" && effects == 1, "depth one still invokes thunk");
			}
			final mutable = aliasBody(template, TDynamic(null));
			check(query.find(mutable.root, 8, 1) == 0, "first root");
			mutable.definition.type = native;
			check(query.find(mutable.root, 8, 1) == 1, "no result survives root query");
			final uncaptured = new OcamlNativeSurfaceQuery({declarations: [], parameters: []});
			check(uncaptured.find(recursive, 8, 3) == NativeSurfaceReference.find(recursive, 8, 3), "uncaptured declaration result");
			check(uncaptured.memoHits == 0, "uncaptured declarations disable reuse");

			final baselineStart = Sys.cpuTime();
			check(NativeSurfaceReference.find(recursive, 12, 3) == 0, "recursive baseline");
			final baselineCpu = Sys.cpuTime() - baselineStart;
			final candidateStart = Sys.cpuTime();
			check(query.find(recursive, 16, 3) == 0, "full-depth recursive result");
			final candidateCpu = Sys.cpuTime() - candidateStart;
			check(query.bodyExpansions <= 16 && query.memoHits > 0, "recursive body expansion bound");
			Sys.println('NATIVE_SURFACE_QUERY:PASS baseline_depth12_cpu=$baselineCpu candidate_depth16_cpu=$candidateCpu expansions=${query.bodyExpansions} hits=${query.memoHits}');
		});
	}

	static function chain(types:Array<Type>):Type {
		return TFun([for (index => type in types) {name: "arg" + index, opt: false, t: type}], TDynamic(null));
	}

	/** Stable fixture-owned getters expose only the explicitly modeled lazy/mono mutations. */
	static function aliasBody(template:Type, body:Type):{root:Type, definition:DefType} {
		return switch template {
			case TType(reference, parameters):
				final definition = reference.get();
				definition.type = body;
				{root: TType({get: () -> definition, toString: () -> definition.name}, parameters), definition: definition};
			case _: throw new haxe.Exception("Expected alias template");
		};
	}

	static function compareEffects(captured:NativeSurfaceCapture, create:Void->EffectCase, label:String):Void {
		final before = create();
		final expected = NativeSurfaceReference.find(before.root, 12, 1);
		final after = create();
		final actual = new OcamlNativeSurfaceQuery(captured).find(after.root, 12, 1);
		check(expected == 1 && actual == expected && before.trace.join(",") == after.trace.join(","), label);
	}

	static function check(condition:Bool, message:String):Void {
		if (!condition)
			throw new haxe.Exception(message);
	}
}
#end
