/**
	The types an abstract value converts to, and the types that convert into an abstract, for a call
	whose parameter names the called method's own type parameters (haxe_ocaml-uyvpx).

	Why
	- Haxe 4.3.7 unifies a call argument with its parameter through the abstract's casts while the
	  method's type parameters are still monomorphs (callUnification.ml:48-51 with
	  abstractCast.ml), so `same<T>(a:Array<T>, b:Array<T>)` accepts a `CustomArray` declared
	  `to Array<Int>`, `lazy<A>(l:Lazy<A>)` accepts `2` through `@:from ofConst<T>(c:T):Lazy<T>`, and
	  `Lambda.count` accepts a `Foo<Array<Int>>` declared `to T`.
	- hxhx's conversion plans compare against the parameter as written, where those type
	  parameters are rigid, so none of these matched.

	What
	- `outputs(actual)`: the declared `to` types and the results of instance `@:to` methods, with
	  the abstract's arguments applied.
	- `inputs(expected)`: the declared `from` types, and the parameter type of each static `@:from`
	  method, after its own type parameters are bound by matching its result against `expected`
	  (`ofConst<T>(c:T):Lazy<T>` for `Lazy<A>` gives `A`).
	- The caller decides which view fits; method selection then specializes the parameter, and the
	  ordinary conversion of the now concrete destination emits the cast.
**/
final class TyAbstractConversionViews {
	/** Only the declared `to` types: storage-preserving casts that need no method call. **/
	public static function declaredOutputs(index:Null<TyperIndex>, actual:TyType):Array<TyType> {
		final info = abstractInfo(index, actual);
		if (info == null)
			return [];
		final bindings = TyTypeSubstitution.bind(info.getTypeParameterIds(), actual.getTypeArguments(), info.getIdentity().getCanonicalName());
		return [for (type in info.getImplicitToTypes()) TyTypeSubstitution.apply(type, bindings)];
	}

	public static function outputs(index:Null<TyperIndex>, actual:TyType):Array<TyType> {
		final info = abstractInfo(index, actual);
		if (info == null)
			return [];
		final bindings = TyTypeSubstitution.bind(info.getTypeParameterIds(), actual.getTypeArguments(), info.getIdentity().getCanonicalName());
		final views = [for (type in info.getImplicitToTypes()) TyTypeSubstitution.apply(type, bindings)];
		for (declaration in info.getDeclarations()) {
			if (declaration.getIsStatic() || !hasConversion(declaration.getMetadata(), "to"))
				continue;
			final callable = TyCallableSignature.fromDeclaration(declaration).getFunctionType();
			if (callable.getFunctionArguments().length != 0 || declaration.getTypeParameterIds().length != 0)
				continue;
			final result = TyTypeSubstitution.apply(callable.getFunctionReturn(), bindings);
			if (!result.hasUnknownComponent())
				views.push(result);
		}
		return views;
	}

	public static function inputs(index:Null<TyperIndex>, expected:TyType):Array<TyType> {
		final info = abstractInfo(index, expected);
		if (info == null)
			return [];
		final bindings = TyTypeSubstitution.bind(info.getTypeParameterIds(), expected.getTypeArguments(), info.getIdentity().getCanonicalName());
		final views = [
			for (type in info.getImplicitFromTypes())
				TyTypeSubstitution.apply(type, bindings)
		];
		for (declaration in info.getDeclarations()) {
			if (!declaration.getIsStatic() || !hasConversion(declaration.getMetadata(), "from"))
				continue;
			final callable = TyCallableSignature.fromDeclaration(declaration).getFunctionType();
			final parameters = callable.getFunctionArguments();
			if (parameters.length != 1)
				continue;
			final own = declaration.getTypeParameterIds();
			final result = TyTypeSubstitution.apply(callable.getFunctionReturn(), bindings);
			final solved = new haxe.ds.StringMap<TyType>();
			if (!bindResult(result, expected, own, solved))
				continue;
			final input = substitute(TyTypeSubstitution.apply(parameters[0], bindings), own, solved);
			if (!input.hasUnknownComponent() && own.filter(parameter -> !solved.exists(parameter.getCanonicalKey())).length == 0)
				views.push(input);
		}
		return views;
	}

	static function abstractInfo(index:Null<TyperIndex>, type:TyType):Null<TyAbstractInfo> {
		final identity = type == null ? null : type.getNominalIdentity();
		final info = identity == null || index == null ? null : index.getAbstractByFullName(identity.getCanonicalName());
		return info == null || info.getTypeParameterIds().length != type.getTypeArguments().length ? null : info;
	}

	/** Bind the method's own parameters where `result` names them, by matching against `expected`. **/
	static function bindResult(result:TyType, expected:TyType, own:Array<TyTypeParameterId>, solved:haxe.ds.StringMap<TyType>):Bool {
		final identity = result.getTypeParameterIdentity();
		if (identity != null && own.filter(parameter -> parameter.equals(identity)).length > 0) {
			final key = identity.getCanonicalKey();
			final previous = solved.get(key);
			if (previous != null)
				return previous.getSemanticKey() == expected.getSemanticKey();
			solved.set(key, expected);
			return true;
		}
		if (result.getSemanticKey() == expected.getSemanticKey())
			return true;
		final resultArguments = result.getTypeArguments();
		final expectedArguments = expected.getTypeArguments();
		if (result.getNominalIdentity() == null
			|| expected.getNominalIdentity() == null
			|| result.getNominalIdentity().getCanonicalName() != expected.getNominalIdentity().getCanonicalName()
			|| resultArguments.length != expectedArguments.length)
			return false;
		for (slot in 0...resultArguments.length)
			if (!bindResult(resultArguments[slot], expectedArguments[slot], own, solved))
				return false;
		return true;
	}

	static function substitute(type:TyType, own:Array<TyTypeParameterId>, solved:haxe.ds.StringMap<TyType>):TyType {
		if (own.length == 0)
			return type;
		return TyTypeSubstitution.apply(type, TyTypeSubstitution.bind(own, [
			for (parameter in own)
				solved.exists(parameter.getCanonicalKey()) ? solved.get(parameter.getCanonicalKey()) : TyType.typeParameter(parameter)
		], "abstract-cast-input"));
	}

	static function hasConversion(metadata:Array<String>, direction:String):Bool {
		for (entry in metadata) {
			var name = StringTools.trim(entry);
			while (StringTools.startsWith(name, "@") || StringTools.startsWith(name, ":"))
				name = name.substr(1);
			if (name == direction)
				return true;
		}
		return false;
	}
}
