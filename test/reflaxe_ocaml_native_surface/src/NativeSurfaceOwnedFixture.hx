#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.ocaml.macros.OcamlNativeSurfaceQuery;
import reflaxe.ocaml.macros.OcamlNativeSurfaceQuery.NativeSurfaceCapture;

/**
	Checks compiler-owned generic and static-value shapes in fresh compilations.
	The runner compares reference and candidate output across separate processes.
	Independent expected masks prevent agreement on the same missing native field.
**/
class NativeSurfaceOwnedFixture {
	static var constraintBuilds = 0;

	/** Records the compiler's constraint build without changing the declaration. */
	public static function buildConstraint():Array<haxe.macro.Expr.Field> {
		constraintBuilds++;
		return Context.getBuildFields();
	}

	public static function run():Void {
		final generic = Context.typeof(macro(null : OwnedSurfaceCases.GenericTree<String>));
		final expressions = [
			{label: "pure", expression: Context.typeExpr(macro OwnedSurfaceCases.PureStatics), expected: 0},
			{label: "class", expression: Context.typeExpr(macro OwnedSurfaceCases.NativeStatics), expected: 3},
			{label: "enum_class", expression: Context.typeExpr(macro OwnedSurfaceCases.EnumStatics), expected: 3},
			{label: "enum_parameter", expression: Context.typeExpr(macro OwnedSurfaceCases.EnumParameterStatics), expected: 1},
			{label: "enum_pure", expression: Context.typeExpr(macro OwnedSurfaceCases.PureEnumStatics), expected: 0},
			{label: "enum", expression: Context.typeExpr(macro OwnedSurfaceCases.NativeConstructors), expected: 3},
			{label: "abstract", expression: Context.typeExpr(macro OwnedSurfaceCases.NativeAbstractStatics), expected: 3}
		];
		var declarations:Array<ModuleType> = [];
		Context.onGenerate(types -> {
			for (type in types)
				switch type {
					case TInst(reference, _): declarations.push(TClassDecl(reference));
					case TEnum(reference, _): declarations.push(TEnumDecl(reference));
					case TType(reference, _): declarations.push(TTypeDecl(reference));
					case TAbstract(reference, _): declarations.push(TAbstract(reference));
					case _: throw new haxe.Exception("Expected generation declaration");
				}
		});
		Context.onAfterGenerate(() -> {
			final capture = OcamlNativeSurfaceQuery.captureDeclarations(declarations);
			final query = new OcamlNativeSurfaceQuery(capture);
			final reference = Context.defined("native_surface_reference");
			final buildsBefore = constraintBuilds;
			check(buildsBefore == 1, "constraint must already be built");
			for (entry in expressions) {
				check(switch entry.expression.expr {
					case TTypeExpr(_): true;
					case _: false;
				}, "real type-expression root");
				final actual = reference ? NativeSurfaceReference.find(entry.expression.t, 12, 3) : query.findExpression(entry.expression, 12, 3);
				check(actual == entry.expected, entry.label + " independent native-family mask");
				Sys.println('OWNED_SURFACE:${entry.label}:$actual');
				if (!reference && StringTools.startsWith(entry.label, "enum_")) {
					check(query.enumPathReads > 0, "compiler class references use captured enum paths");
					check(query.find(entry.expression.t, 12, 3) == entry.expected && query.enumPathReads == 0,
						"plain queries must not inherit enum path permission");
				}
				if (!reference && entry.label == "pure") {
					check(query.memoHits > 0, "static generic methods must permit useful reuse");
					check(query.find(entry.expression.t, 12, 3) == 0
						&& query.memoHits == 0, "plain type queries must not inherit the expression witness");
				}
				for (depth in 0...7)
					for (mask in 0...4) {
						final value = reference ? NativeSurfaceReference.find(entry.expression.t, depth,
							mask) : query.findExpression(entry.expression, depth, mask);
						Sys.println('OWNED_DEPTH:${entry.label}:$depth:$mask:$value');
					}
			}
			check((reference ? NativeSurfaceReference.find(generic, 12, 3) : query.find(generic, 12, 3)) == 0, "generic record stays portable");
			if (!reference) {
				check(query.memoHits > 0 && query.bodyExpansions <= 12,
					'generic recursive expansion bound: hits=${query.memoHits} bodies=${query.bodyExpansions}');
				final withoutOwners = new OcamlNativeSurfaceQuery({declarations: capture.declarations, parameters: []});
				check(withoutOwners.find(generic, 12, 3) == 0
					&& withoutOwners.memoHits == 0, "unowned formal parameter remains a barrier");
				checkParameterIdentity(capture);
				checkEnumBarriers(capture);
			}
			check(constraintBuilds == buildsBefore, "queries must not build constraints again");
			Sys.println("OWNED_SURFACE:PASS");
		});
	}

	/** Exercises permission revocation directly; only compiler-decoded expressions enable it in production. */
	static function checkEnumBarriers(capture:NativeSurfaceCapture):Void {
		final ordinary = Context.typeof(macro(null : OwnedSurfaceCases.PlainEnum<String>));
		final native = Context.typeof(macro(null : ocaml.SurfaceEnum<String>));
		final query = new OcamlNativeSurfaceQuery(capture);
		for (kind in ["lazy", "mono", "unknown"]) {
			var strings = 0;
			var reads = 0;
			final forwarded = switch native {
				case TEnum(reference, parameters): TEnum({
						get: () -> {
							reads++;
							return reference.get();
						},
						toString: () -> {
							strings++;
							return "SurfaceEnum";
						}
					}, parameters);
				case _: throw new haxe.Exception("Expected native enum");
			};
			final barrier:Type = switch kind {
				case "lazy": TLazy(() -> TDynamic(null));
				case "mono": TMono({get: () -> null, toString: () -> "unresolved"});
				case _: switch Context.getType("String") {
						case TInst(reference, parameters):
							final definition = reference.get();
							definition.name = "UncapturedEnumBarrier";
							TInst({get: () -> definition, toString: () -> definition.name}, parameters);
						case _: throw new haxe.Exception("Expected class");
					};
			};
			final root = TFun([
				{name: "first", opt: false, t: ordinary},
				{name: "barrier", opt: false, t: barrier},
				{name: "last", opt: false, t: forwarded}
			], TDynamic(null));
			check(@:privateAccess query.start(root, 8, 3, false, true) == 1, kind + " native mask");
			check(query.enumPathReads == 1 && reads == 1 && strings == 0, kind + " revokes enum syntax conversion");
		}
		var effects = 0;
		final withArgument = switch native {
			case TEnum(reference, _): TEnum(reference, [
					TLazy(() -> {
						effects++;
						return TDynamic(null);
					})
				]);
			case _: throw new haxe.Exception("Expected enum");
		};
		check(@:privateAccess query.start(withArgument, 8, 1, false, true) == 1
			&& effects == 0, "enum package short circuit must not inspect actual arguments");
		check(@:privateAccess query.start(withArgument, 8, 3, false, true) == 1
			&& effects == 1, "remaining family must visit the lazy actual argument once");
		check(@:privateAccess !query.enumPathsAllowed, "actual argument barrier revokes enum conversion");
	}

	/** Same-named parameters from different owners must remain distinguishable. */
	static function checkParameterIdentity(capture:NativeSurfaceCapture):Void {
		final owner = switch Context.getType("OwnedSurfaceCases.PureStatics") {
			case TInst(reference, _): reference;
			case _: throw new haxe.Exception("Expected generic class");
		};
		final declared = owner.get();
		final fresh = owner.get();
		final first = named(declared.statics.get(), "first");
		final second = named(fresh.statics.get(), "second");
		final freshFirst = named(fresh.statics.get(), "first");
		var defaultReads = 0;
		final parameters:Array<TypeParameter> = [
			{
				name: declared.params[0].name,
				t: declared.params[0].t,
				defaultType: TLazy(() -> {
					defaultReads++;
					return TDynamic(null);
				})
			}
		];
		final query = new OcamlNativeSurfaceQuery({declarations: capture.declarations, parameters: parameters});
		query.find(fresh.params[0].t, 1, 3);
		check(@:privateAccess query.reuseEnabled, "fresh wrapper must preserve class parameter ownership");
		query.find(first.params[0].t, 1, 3);
		check(! @:privateAccess query.reuseEnabled, "method parameter must not match same-named class parameter");
		check(defaultReads == 0, "ownership checks must not read defaults");
		final method = new OcamlNativeSurfaceQuery({declarations: capture.declarations, parameters: first.params});
		method.find(freshFirst.params[0].t, 1, 3);
		check(@:privateAccess method.reuseEnabled, "fresh wrapper must preserve method parameter ownership");
		method.find(second.params[0].t, 1, 3);
		check(! @:privateAccess method.reuseEnabled, "same-named methods must retain distinct parameters");
	}

	static function named(fields:Array<ClassField>, name:String):ClassField {
		for (field in fields)
			if (field.name == name)
				return field;
		throw new haxe.Exception("Missing field " + name);
	}

	static function check(condition:Bool, label:String):Void {
		if (!condition)
			throw new haxe.Exception(label);
	}
}
#end
