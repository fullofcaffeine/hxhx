import TyTypeDeclaration.TyTypeResolutionContext;

/** Alias uses preserve target meaning and exact declaration evidence. */
class M14TypedefResolutionTest {
	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function module(path:String, source:String):ResolvedModule
		return new ResolvedModule(path, path.split(".").join("/") + ".hx", ParserStage.parse(source, path.split(".").join("/") + ".hx"));

	static function context(module:ResolvedModule):TyTypeResolutionContext {
		return {
			packagePath: HxModuleDecl.getPackagePath(module.parsed.getDecl()),
			modulePath: module.modulePath,
			directives: HxModuleDecl.getDirectives(module.parsed.getDecl()),
			filePath: module.filePath,
			position: new HxPos(3, 1, 4),
			parameters: []
		};
	}

	static function main():Void {
		genericAliases();
		functionAliases();
		restFunctionAliases();
		resolvedRestParameters();
		callableViews();
		structuralAliases();
		final local = module("Main", "typedef Count=Int; typedef Alias=Original; typedef Chain=Alias; class Original {} class Main {}");
		final index = TyperIndex.build([local]);
		final use = index.resolveTypeUse(TyType.fromHintText("Chain"), context(local));
		require(use.getType().getNominalIdentity().getCanonicalName() == "Main.Original", "chain did not normalize to its nominal target");
		require([for (declaration in use.getDeclarations()) declaration.getCanonicalName()].join(",") == "Main.Chain,Main.Alias,Main.Original",
			"alias expansion lost declaration evidence");
		require(use.getPosition().getColumn() == 4, "type use lost its caller position");
		use.getDeclarations().resize(0);
		require(use.getDeclarations().length == 3, "caller mutated type-use evidence");
		require(index.resolveTypeUse(TyType.fromHintText("Count"), context(local))
			.getType()
			.getSemanticKey() == TyType.fromHintText("Int")
			.getSemanticKey(),
			"primitive alias was treated as a nominal type");
		require(index.getByFullName("Main.Count") == null
			&& index.getByFullName("Main.Alias") == null, "alias entered nominal provider catalog");

		final localSwitch = module("Main",
			"enum abstract Original(Int) { var Red=10; var Blue=20; } typedef Signal=Original;" +
			"class Main { static function select(value:Original):Int { var alias:Signal=value; return switch(alias) { case Red: 1; }; } }");
		var localSwitchDiagnostic = "";
		try {
			TyperStage.typeResolvedModule(localSwitch, TyperIndex.build([localSwitch]));
		} catch (error:TyperError) {
			localSwitchDiagnostic = error.message;
		}
		require(localSwitchDiagnostic == "Unmatched patterns: Blue", "local type hint did not use shared alias resolution: " + localSwitchDiagnostic);

		final target = module("left.Target", "package left; class Target {}");
		final wrong = module("right.Target", "package right; class Target {}");
		final provider = module("definitions.Types", "package definitions; import left.Target; typedef PublicAlias=Target; private typedef Hidden=Target;");
		final caller = module("Main", "import right.Target; import definitions.Types.PublicAlias as Local; class Main {}");
		final imported = TyperIndex.build([caller, wrong, provider, target]);
		final selected = imported.resolveTypeUse(TyType.fromHintText("Local"), context(caller));
		require(selected.getType().getNominalIdentity().getCanonicalName() == "left.Target", "caller imports changed the alias target");
		require(selected.getDeclarations()[0].getCanonicalName() == "definitions.Types.PublicAlias", "import rename replaced declaration identity");
		require(imported.resolveTypeUse(TyType.fromHintText("definitions.Types.Hidden"), context(caller)).getType().isUnresolved(),
			"private alias escaped its defining module");
		require(imported.resolveTypeUse(TyType.fromHintText("absent.Target"), context(caller)).getType().isUnresolved(),
			"missing qualified path selected an unrelated short name");
		final bare = module("Bare", "class Bare {}");
		require(imported.resolveTypeUse(TyType.fromHintText("PublicAlias"), context(bare)).getType().isUnresolved(),
			"unimported globally unique alias became visible");

		for (source in ["typedef Alias=Missing;", "typedef Alias=Other; typedef Other=Alias;"]) {
			final broken = module("Broken", source);
			var rejected = false;
			try {
				TyperIndex.build([broken]);
			} catch (error:TyperError) {
				rejected = true;
				require(error.filePath == "Broken.hx" && error.pos.line == 1, "alias error lost defining source position");
			}
			require(rejected, "unused invalid alias was published without an error");
		}
		Sys.println("TYPEDEF_RESOLUTION:PASS");
	}

	/** Structural declarations retain access rules and method-local parameter scope. */
	static function structuralAliases():Void {
		final scopes = module("Scopes",
			"typedef Outer={function make<T>():{function take<U>(value:T):U;};}; " + "typedef Inner={function make<T>():{function take<U>(value:U):U;};}; " +
			"typedef Renamed={function make<A>():{function take<B>(value:A):B;};};");
		final scopeIndex = TyperIndex.build([scopes]);
		final outer = scopeIndex.resolveTypeUse(TyType.fromHintText("Outer"), context(scopes)).getType();
		final inner = scopeIndex.resolveTypeUse(TyType.fromHintText("Inner"), context(scopes)).getType();
		final renamed = scopeIndex.resolveTypeUse(TyType.fromHintText("Renamed"), context(scopes)).getType();
		require(outer.getSemanticKey() != inner.getSemanticKey(), "nested method parameter scope collapsed into its enclosing scope");
		require(outer.getSemanticKey() == renamed.getSemanticKey(), "renaming method parameters changed structural meaning");
		final source = module("Records",
			"typedef Record<T>={final value:T; var ?label:String; var count(default,null):Int; function echo<T>(item:T):T;}; " +
			"typedef Base={enabled:Bool}; typedef Extended<T>={>Base, payload:T};");
		final index = TyperIndex.build([source]);
		final ctx = context(source);
		final record = index.resolveTypeUse(TyType.fromHintText("Record<Int>"), ctx).getType();
		final fields = record.getAnonymousFields();
		require(record.isAnonymous() && fields.length == 4, "structural alias did not preserve declared fields");
		for (field in fields) {
			switch (field.name) {
				case "value":
					require(field.type.getSemanticKey() == "primitive:Int" && field.kind.match(Variable(true, "", "")),
						"final generic field lost its contract");
				case "label":
					require(field.isOptional && !field.type.isNullable(), "field absence became value nullability");
				case "count":
					require(field.kind.match(Variable(false, "default", "null")), "property access rules were discarded");
				case "echo":
					switch (field.kind) {
						case Method(parameters):
							require(parameters.length == 1
								&& field.type.getFunctionArguments()[0].getTypeParameterIdentity().equals(parameters[0])
								&& field.type.getFunctionReturn().getTypeParameterIdentity().equals(parameters[0]),
								"outer argument captured method-local T");
						case _: throw "method became a variable";
					}
				case _:
					throw "unexpected structural field";
			}
			field.metadata.push("changed");
		}
		require(record.getAnonymousFields()[0].metadata.length == 0, "caller mutated structural metadata");
		require(index.resolveTypeUse(record, ctx).getType().getSemanticKey() == record.getSemanticKey(), "normalization erased declaration facts");
		final extended = index.resolveTypeUse(TyType.fromHintText("Extended<String>"), ctx).getType();
		require(extended.getAnonymousFieldNames().join(",") == "enabled,payload"
			&& extended.getAnonymousFieldTypes()[1].getSemanticKey() == "primitive:String",
			"structural extension did not retain inherited and substituted fields");
		final repeated = module("Repeated", "typedef Base={item:Int}; typedef Record={>Base,item:Int};");
		require(TyperIndex.build([repeated])
			.resolveTypeUse(TyType.fromHintText("Record"), context(repeated))
			.getType()
			.getAnonymousFields()
			.length == 1,
			"an equivalent inherited field was rejected");
		for (text in [
			"typedef Bad={item:Int,item:String};",
			"typedef Base={item:Int}; typedef Bad={>Base,item:String};"
		]) {
			var rejected = false;
			try {
				TyperIndex.build([module("Bad", text)]);
			} catch (error:TyperError) {
				rejected = true;
			}
			require(rejected, "duplicate declaration used object-literal last-write behavior");
		}
	}

	/** Callable views preserve provenance without confusing default values with type identity. */
	static function callableViews():Void {
		final source = module("Provider",
			"class Provider { "
			+ "public static function choose<T>(@:tag value:T, ?label:String):T return value; "
			+ "public static function first(value:Int=7):Int return value; public static function second(value:Int=9):Int return value; "
			+ "public static function exercise():Int { var f=first; return f(); } }");
		final imported = module("Use",
			"import Provider.first as selected; class Use { public static function exercise():Int { var f=selected; return f(); } }");
		final index = TyperIndex.build([source, imported]);
		final owner = index.getByFullName("Provider");
		final declaration = owner.declarationForSignature(owner.staticMethod("choose"));
		final declared = TyCallableSignature.fromDeclaration(declaration);
		require(declared.getDeclaration() == declaration, "callable view replaced the selected declaration");
		require(declared.getMethodTypeParameters().length == 1
			&& declared.getMethodTypeParameters()[0].equals(declaration.getTypeParameterIds()[0]),
			"callable view lost exact generic binder identity");
		require(declared.getParameters()[0].metadata[0] == "@:tag" && declared.getParameters()[1].isOptional,
			"callable view lost parameter metadata or optionality");
		declared.getParameters()[0].metadata.resize(0);
		declared.getMethodTypeParameters().resize(0);
		require(declared.getParameters()[0].metadata.length == 1 && declared.getMethodTypeParameters().length == 1,
			"caller mutated callable parameter or binder facts");
		final value = TyCallableSignature.fromFunctionValue(declared.getFunctionType());
		require(value.getDeclaration() == null && value.getMethodTypeParameters().length == 0,
			"function value acquired a synthetic declaration or owned generic binders");
		require(value.getResultType().getSemanticKey() == declared.getResultType().getSemanticKey(), "function value changed its result type");
		final first = TyCallableSignature.fromDeclaration(owner.declarationForSignature(owner.staticMethod("first")));
		final second = TyCallableSignature.fromDeclaration(owner.declarationForSignature(owner.staticMethod("second")));
		require(first.getFunctionType().getSemanticKey() == second.getFunctionType().getSemanticKey()
			&& first.getDeclaration() != second.getDeclaration(),
			"concrete defaults contaminated function type identity");
		var rejected = false;
		try {
			TyCallableSignature.fromFunctionValue(TyType.fromHintText("Dynamic"));
		} catch (error:String) {
			rejected = error == "callable signature requires a function type with a result";
		}
		require(rejected, "genuine dynamic calls were silently treated as ordinary function values");
		for (input in [source, imported]) {
			final typed = TyperStage.typeResolvedModule(input, index);
			final functions = typed.getTypedClasses()[0].getFunctions();
			final exercise = [
				for (fn in functions)
					if (HxFunctionDecl.getName(fn.getSourceDeclaration()) == "exercise") fn
			][0];
			final locals = [
				for (local in exercise.getEnvironment().getLocals())
					if (local.getName() == "f") local
			];
			require(locals.length == 1 && locals[0].getType().getSemanticKey() == first.getFunctionType().getSemanticKey(),
				"ordinary method-reference inference lost callable facts: " + input.modulePath);
		}
	}

	/** Only a resolved, non-optional standard Rest parameter introduces variadic call semantics. */
	static function resolvedRestParameters():Void {
		final standard = module("haxe.Rest", "package haxe; abstract Rest<T>(Array<T>) {}");
		final array = module("Array", "class Array<T> {}");
		final source = module("Callbacks",
			"import haxe.Rest as Many; typedef Wrapped<T>=Many<T>; " +
			"typedef Named=(values:Many<Int>)->Int; typedef Legacy=Many<Int>->Int; typedef Aliased=(values:Wrapped<Int>)->Int; " +
			"typedef Apply<T>=(values:T)->Int; typedef Optional=(?values:Many<Int>)->Int; typedef Nested=(...values:Many<Int>)->Int;");
		final shadow = module("Shadow", "typedef Rest<T>=Array<T>; typedef Callback=(values:Rest<Int>)->Int;");
		final index = TyperIndex.build([array, standard, source, shadow]);
		final ctx = context(source);
		final expected = TyType.fromHintText("(...values:Int)->Int");
		for (hint in [
			"Named",
			"Legacy",
			"Aliased",
			"Apply<haxe.Rest<Int>>",
			"(values:haxe.Rest<Int>)->Int"
		]) {
			final use = index.resolveTypeUse(TyType.fromHintText(hint), ctx);
			require(use.getType().getSemanticKey() == expected.getSemanticKey(), "resolved Rest did not normalize: " + hint);
			require([for (declaration in use.getDeclarations()) declaration.getCanonicalName()].indexOf("haxe.Rest") >= 0,
				"rest normalization lost standard declaration evidence: " + hint);
		}
		final optional = index.resolveTypeUse(TyType.fromHintText("Optional"), ctx).getType().getFunctionParameters()[0];
		require(optional.isOptional && !optional.isRest && optional.type.getNominalIdentity().getCanonicalName() == "haxe.Rest",
			"optional Rest container was incorrectly treated as variadic");
		final nested = index.resolveTypeUse(TyType.fromHintText("Nested"), ctx).getType().getFunctionParameters()[0];
		require(nested.isRest
			&& nested.type.getNominalIdentity().getCanonicalName() == "haxe.Rest", "normalization consumed more than one rest layer");
		final fixed = index.resolveTypeUse(TyType.fromHintText("Callback"), context(shadow)).getType().getFunctionParameters()[0];
		require(!fixed.isRest && fixed.type.getNominalIdentity().getCanonicalName() == "Array", "unrelated Rest alias became variadic");
		require(!TyType.fromHintText("(values:haxe.Rest<Int>)->Int").getFunctionParameters()[0].isRest,
			"unresolved spelling was mistaken for a resolved standard declaration");
	}

	/** Rest element facts survive aliases, substitution, canonical spelling, and method references. */
	static function restFunctionAliases():Void {
		final source = module("Callbacks",
			"typedef Rest<T>=(...values:T)->Int; typedef Unnamed=(...Int)->Int; " +
			"class Callbacks { public static function sink(...values:Int):Int return 1; }");
		final index = TyperIndex.build([source]);
		final ctx = context(source);
		final rest = index.resolveTypeUse(TyType.fromHintText("Rest<Int>"), ctx).getType();
		final parameter = rest.getFunctionParameters()[0];
		require(parameter.isRest && !parameter.isOptional && parameter.type.getSemanticKey() == "primitive:Int",
			"rest alias lost its element type or confused rest with optionality");
		for (hint in ["(...values:Int)->Int", "(...Int)->Int", rest.getCanonicalDisplay()])
			require(TyType.fromHintText(hint).getSemanticKey() == rest.getSemanticKey(), "rest hint changed callable identity: " + hint);
		require(index.resolveTypeUse(TyType.fromHintText("Unnamed"), ctx).getType().getSemanticKey() == rest.getSemanticKey(),
			"unnamed rest syntax was mistaken for grouping");
		require(index.resolveTypeUse(rest, ctx).getType().getFunctionParameters()[0].isRest, "type normalization discarded rest");
		final fixed = TyType.fromHintText("(values:Int)->Int");
		final array = TyType.fromHintText("(values:Array<Int>)->Int");
		require(rest.getSemanticKey() != fixed.getSemanticKey() && rest.getSemanticKey() != array.getSemanticKey(),
			"rest, scalar, and array callables share an identity");
		require(TyType.unify(rest, fixed) == null, "unification silently discarded rest shape");
		require(TyType.unify(rest, rest).getFunctionParameters()[0].isRest, "unification lost matching rest shape");
		final owner = index.getByFullName("Callbacks");
		final declaration = owner.declarationForSignature(owner.staticMethod("sink"));
		require(TyCallableSignature.fromDeclaration(declaration).getFunctionType().getSemanticKey() == rest.getSemanticKey(),
			"method reference exposed the body array as a fixed parameter");
	}

	/** Function aliases preserve arity, grouping, and argument declaration facts. */
	static function functionAliases():Void {
		final source = module("Callbacks",
			"typedef Identity<T>=T; typedef Flat=Int->String->Bool; " + "typedef Factory=Int->(String->Bool); typedef Empty=Void->Int; " +
			"typedef Handler<T>=(value:Identity<T>, ?label:String)->Null<T>; typedef Parenthesized=(Int)->String->Bool;");
		final index = TyperIndex.build([source]);
		final ctx = context(source);
		final flat = index.resolveTypeUse(TyType.fromHintText("Flat"), ctx).getType();
		require(flat.isFunction()
			&& flat.getFunctionArguments().length == 2
			&& flat.getFunctionReturn().getSemanticKey() == "primitive:Bool",
			"legacy arrow chain did not become one two-argument function");
		final factory = index.resolveTypeUse(TyType.fromHintText("Factory"), ctx).getType();
		require(index.resolveTypeUse(TyType.fromHintText("Parenthesized"), ctx).getType().getSemanticKey() == flat.getSemanticKey(),
			"parenthesized legacy argument incorrectly introduced a returned function");
		require(factory.getFunctionArguments().length == 1
			&& factory.getFunctionReturn().isFunction(), "grouped return function was flattened");
		require(TyType.fromHintText(factory.getCanonicalDisplay()).getSemanticKey() == factory.getSemanticKey(),
			"canonical function spelling changed the returned function into another argument");
		require(index.resolveTypeUse(TyType.fromHintText("Empty"), ctx)
			.getType()
			.getFunctionArguments()
			.length == 0, "Void arrow argument was not empty");
		final handler = index.resolveTypeUse(TyType.fromHintText("Handler<Int>"), ctx).getType();
		require(handler.getFunctionArguments()[0].getSemanticKey() == "primitive:Int"
			&& handler.getFunctionReturn().getNullableInner().getSemanticKey() == "primitive:Int",
			"generic function alias did not substitute argument and result types");
		final arguments = handler.getFunctionParameters();
		require(arguments[0].name == "value" && !arguments[0].isOptional && arguments[1].name == "label" && arguments[1].isOptional,
			"function alias lost argument names or optionality");
		arguments[0].metadata.push("changed");
		arguments.resize(0);
		require(handler.getFunctionParameters().length == 2 && handler.getFunctionParameters()[0].metadata.length == 0,
			"caller mutated function argument facts");
		final required = TyType.functionType(handler.getFunctionArguments(), handler.getFunctionReturn());
		require(handler.getSemanticKey() != required.getSemanticKey(), "optional and required functions have the same semantic identity");
		require(TyType.fromHintText("(value:Int, ?label:String)->Null<Int>").getSemanticKey() == handler.getSemanticKey(),
			"direct function spelling and alias disagree about optionality");
		require(TyType.fromHintText("Void->Int")
			.getSemanticKey() == index.resolveTypeUse(TyType.fromHintText("Empty"), ctx)
			.getType()
			.getSemanticKey(),
			"direct function spelling and alias disagree about empty arguments");
		require(!TyType.unify(handler, required).getFunctionParameters()[1].isOptional,
			"the common function type permits omission that a required branch cannot accept");
		require(index.resolveTypeUse(handler, ctx).getType().getSemanticKey() == handler.getSemanticKey(), "normalization erased optional arguments");
	}

	/** Applied arguments stay in caller scope; alias binders belong to their declaration. */
	static function genericAliases():Void {
		final source = module("Generic",
			"class Pair<A,B> {} typedef Flip<X,Y>=Pair<Y,X>; typedef Identity<T>=T; " +
			"typedef Wrapped<T>=Null<Identity<T>>; typedef Defaulted<T=String>=T; " + "typedef Nested<T>=Identity<Identity<T>>; class Generic {}");
		final index = TyperIndex.build([source]);
		final ctx = context(source);
		final flipped = index.resolveTypeUse(TyType.fromHintText("Flip<Int,String>"), ctx).getType();
		require(flipped.getNominalIdentity().getCanonicalName() == "Generic.Pair", "generic alias lost its nominal target");
		require([for (arg in flipped.getTypeArguments()) arg.getCanonicalDisplay()].join(",") == "String,Int", "alias parameters were not reordered");
		for (name in ["Identity<Identity<Int>>", "Nested<Int>"])
			require(index.resolveTypeUse(TyType.fromHintText(name), ctx).getType().getSemanticKey() == "primitive:Int",
				"finite alias nesting was rejected: " + name);
		require(index.resolveTypeUse(TyType.fromHintText("Flip<String,Bool>"), ctx).getType().getTypeArguments()[0].getSemanticKey() == "primitive:Bool",
			"a second alias instantiation retained the first arguments");
		require(index.resolveTypeUse(TyType.fromHintText("Wrapped<Int>"), ctx)
			.getType()
			.getNullableInner()
			.getSemanticKey() == "primitive:Int",
			"nullable alias did not substitute its nested argument");
		require(index.resolveTypeUse(TyType.fromHintText("Defaulted"), ctx).getType().getSemanticKey() == "primitive:String",
			"default type argument was not applied");
		require(index.resolveTypeUse(TyType.fromHintText("Defaulted<Bool>"), ctx).getType().getSemanticKey() == "primitive:Bool",
			"default replaced an explicit argument");
		final callerT = new TyTypeParameterId("test:caller", 0, "T");
		ctx.parameters.push(callerT);
		final shadowed = index.resolveTypeUse(TyType.fromHintText("Identity<T>"), ctx).getType();
		require(shadowed.getTypeParameterIdentity().equals(callerT), "alias captured the caller's same-name parameter");
		for (name in ["Identity", "Flip<Int>", "Identity<Int,String>"]) {
			var errorText = "";
			try {
				index.resolveTypeUse(TyType.fromHintText(name), ctx);
			} catch (error:TyperError) {
				errorText = error.message;
				require(error.filePath == source.filePath && error.pos == ctx.position, "arity error lost its use position");
			}
			require(errorText.indexOf("type parameters") >= 0, "wrong alias arity was not rejected: " + name);
		}
		for (text in [
			"typedef Bad<T,T>=T;",
			"typedef Bad<T=Missing>=T;",
			"typedef Bad<A,B=A>=A;",
			"typedef Bad<T>=Missing;",
			"class Box<T> {} typedef Bad<T>=Bad<Box<T>>;"
		]) {
			var rejected = false;
			try {
				TyperIndex.build([module("Bad", text)]);
			} catch (error:TyperError) {
				rejected = true;
			}
			require(rejected, "invalid unused generic alias was published: " + text);
		}
	}
}
