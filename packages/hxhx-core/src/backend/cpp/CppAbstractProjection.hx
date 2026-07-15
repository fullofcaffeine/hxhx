package backend.cpp;

typedef CppAbstractProjectionMatch = {
	var fn:HxFunctionDecl;
	var underlyingTypeHint:String;
}

/**
	C++ representation and `@:to` selection for static-only generic abstracts.

	Why
	- Haxe stores an abstract value in its underlying carrier, but the early C++
	  backend models stateful abstracts as generated wrapper classes.
	- A generic abstract containing only static projection helpers has no wrapper
	  state to preserve. Emitting a second `shared_ptr<Abstract<T>>` carrier makes
	  valid underlying assignments and implicit conversions ill-typed.

	What
	- Identifies the narrow static-only class-backed abstract shape that is safe
	  to erase to its specialized underlying class.
	- Substitutes source type arguments into the underlying carrier hint.
	- Selects exactly one `@:to` helper by matching its specialized parameter and
	  return types through caller-supplied C++ type renderers.

	How
	- Stateful, instance-method, primitive-backed, array-backed, non-generic, and
	  ambiguous conversion shapes decline without changing the existing wrapper
	  model.
	- Parser metadata is accepted in both direct (`@:to`) and scanner (`to`)
	  spellings, but conversion selection never relies on a function name.
**/
class CppAbstractProjection {
	public static function isEligible(cls:HxClassDecl, typeParams:Array<String>):Bool {
		if (cls == null
			|| typeParams == null
			|| typeParams.length == 0
			|| !isHxhxAbstractClass(cls)
			|| CppTypeModel.isPrimitiveBackedAbstractClass(cls)
			|| CppTypeModel.isArrayBackedAbstractClass(cls))
			return false;
		final rawUnderlying = CppTypeModel.abstractUnderlyingTypeHint(cls);
		if (rawUnderlying == null)
			return false;
		final underlying = CppTypeModel.removeTypeHintWhitespace(rawUnderlying);
		if (underlying.length == 0
			|| CppTypeModel.genericTypeHintArgs(underlying).length == 0
			|| !CppTypeModel.isClassLikeTypeHint(underlying))
			return false;
		for (field in HxClassDecl.getFields(cls))
			if (!HxFieldDecl.getIsStatic(field))
				return false;
		var hasProjection = false;
		for (fn in HxClassDecl.getFunctions(cls)) {
			if (!HxFunctionDecl.getIsStatic(fn))
				return false;
			if (hasFunctionMetadataMarker(fn, "to"))
				hasProjection = true;
		}
		return hasProjection;
	}

	/** Specialize `Projected<T>(Carrier<T>)` plus `Projected<String>` to `Carrier<String>`. **/
	public static function specializedUnderlyingTypeHint(cls:HxClassDecl, sourceTypeHint:String, typeParams:Array<String>):String {
		if (!isEligible(cls, typeParams))
			return "";
		final source = CppTypeModel.removeTypeHintWhitespace(StringTools.trim(sourceTypeHint == null ? "" : sourceTypeHint));
		final sourceArgs = CppTypeModel.genericTypeHintArgs(source);
		if (typeParams == null || typeParams.length == 0 || sourceArgs.length != typeParams.length)
			return "";
		final underlying = CppTypeModel.abstractUnderlyingTypeHint(cls);
		if (underlying == null || CppTypeModel.typeBaseName(underlying) == CppTypeModel.typeBaseName(source))
			return "";
		return substituteTypeParams(underlying, typeParams, sourceArgs);
	}

	/**
		Select one projection whose specialized carrier and return type both match.

		The callbacks keep target naming and rendered module aliases in the emitter;
		this module owns only abstract representation and overload selection policy.
	**/
	public static function select(cls:HxClassDecl, sourceTypeHint:String, typeParams:Array<String>, expectedCppType:String, renderValueType:String->String,
			renderReturnType:String->String):Null<CppAbstractProjectionMatch> {
		if (expectedCppType == null || expectedCppType.length == 0 || renderValueType == null || renderReturnType == null)
			return null;
		final underlying = specializedUnderlyingTypeHint(cls, sourceTypeHint, typeParams);
		if (underlying.length == 0)
			return null;
		final sourceArgs = CppTypeModel.genericTypeHintArgs(sourceTypeHint);
		final underlyingCppType = renderValueType(underlying);
		var selected:Null<HxFunctionDecl> = null;
		for (fn in HxClassDecl.getFunctions(cls)) {
			if (!HxFunctionDecl.getIsStatic(fn) || !hasFunctionMetadataMarker(fn, "to"))
				continue;
			final args = HxFunctionDecl.getArgs(fn);
			if (args.length != 1)
				continue;
			final returnHint = substituteTypeParams(HxFunctionDecl.getReturnTypeHint(fn), typeParams, sourceArgs);
			final paramHint = substituteTypeParams(HxFunctionArg.getTypeHint(args[0]), typeParams, sourceArgs);
			if (renderReturnType(returnHint) != expectedCppType || renderValueType(paramHint) != underlyingCppType)
				continue;
			if (selected != null)
				return null;
			selected = fn;
		}
		return selected == null ? null : {fn: selected, underlyingTypeHint: underlying};
	}

	/** Match metadata across direct-parser (`@:to`) and scanner (`to`) spellings. **/
	public static function hasFunctionMetadataMarker(fn:HxFunctionDecl, marker:String):Bool {
		if (fn == null || marker == null || marker.length == 0)
			return false;
		for (raw in HxFunctionDecl.getMetadata(fn)) {
			final compact = CppTypeModel.removeTypeHintWhitespace(StringTools.trim(raw == null ? "" : raw));
			if (compact == marker
				|| compact == "@:" + marker
				|| compact == "@" + marker
				|| StringTools.startsWith(compact, "@:" + marker + "("))
				return true;
		}
		return false;
	}

	static function isHxhxAbstractClass(cls:HxClassDecl):Bool {
		if (cls == null)
			return false;
		for (meta in HxClassDecl.getMetadata(cls))
			if (StringTools.trim(meta) == "__hxhx_abstract")
				return true;
		return false;
	}

	static function substituteTypeParams(typeHint:String, typeParams:Array<String>, typeArgs:Array<String>):String {
		var out = typeHint == null ? "" : typeHint;
		final count = typeParams.length < typeArgs.length ? typeParams.length : typeArgs.length;
		for (i in 0...count)
			out = replaceTypeParamToken(out, typeParams[i], typeArgs[i]);
		return out;
	}

	static function replaceTypeParamToken(typeHint:String, param:String, replacement:String):String {
		final clean = StringTools.trim(param == null ? "" : param);
		if (clean.length == 0 || replacement == null || replacement.length == 0)
			return typeHint;
		final out = new StringBuf();
		var i = 0;
		while (i < typeHint.length) {
			if (typeHint.substr(i, clean.length) == clean
				&& !isIdentifierChar(typeHint.charAt(i - 1))
				&& !isIdentifierChar(typeHint.charAt(i + clean.length))) {
				out.add(replacement);
				i += clean.length;
			} else {
				out.add(typeHint.charAt(i));
				i++;
			}
		}
		return out.toString();
	}

	static function isIdentifierChar(ch:String):Bool {
		if (ch == null || ch.length == 0)
			return false;
		final code = ch.charCodeAt(0);
		return (code >= "A".code && code <= "Z".code)
			|| (code >= "a".code && code <= "z".code)
			|| (code >= "0".code && code <= "9".code)
			|| ch == "_";
	}
}
