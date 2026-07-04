package backend.cpp;

/**
	C++ target type-hint and reference model helpers.

	Why
	- `CppTargetCore` should stay responsible for source emission and build
	  orchestration, not for owning every rule that maps Haxe type hints to C++
	  reference/value shapes.
	- Full1 burn-down has made nullable references, array-backed abstracts,
	  primitive abstracts, and callable hints stable enough to give them a named
	  seam before the target core grows further.

	What
	- Normalizes Haxe type-hint text.
	- Resolves class-backed hints through the render/class lookup scope.
	- Maps the currently supported Haxe value/reference/function shapes to C++
	  type names and defaults.

	How
	- Keep this module behavior-only: no source rendering, no runtime prelude
	  emission, and no filesystem/build work.
	- Add new C++ type-model rules here first; only leave target-core forwarding
	  wrappers where existing emitter code still calls the old helper name.
**/
class CppTypeModel {
	static inline final ABSTRACT_UNDERLYING_PREFIX = "__hxhx_abstract_underlying=";

	public static function abstractUnderlyingTypeHint(cls:HxClassDecl):Null<String> {
		if (cls == null)
			return null;
		for (meta in HxClassDecl.getMetadata(cls)) {
			if (StringTools.startsWith(meta, ABSTRACT_UNDERLYING_PREFIX))
				return meta.substr(ABSTRACT_UNDERLYING_PREFIX.length);
		}
		return null;
	}

	public static function isArrayBackedAbstractClass(cls:HxClassDecl):Bool {
		final underlying = abstractUnderlyingTypeHint(cls);
		if (underlying == null)
			return false;
		final compact = removeTypeHintWhitespace(underlying);
		return StringTools.startsWith(compact, "Array<") || isStdVectorUnderlying(compact);
	}

	public static function isStdVectorHelperClass(cls:HxClassDecl):Bool {
		final underlying = abstractUnderlyingTypeHint(cls);
		return cls != null
			&& sanitizeTypePath(HxClassDecl.getName(cls)) == "Vector"
			&& underlying != null
			&& isStdVectorUnderlying(removeTypeHintWhitespace(underlying));
	}

	public static function isPrimitiveBackedAbstractClass(cls:HxClassDecl):Bool {
		return primitiveAbstractUnderlyingCppType(cls) != null;
	}

	public static function isStdArrayHelperClass(cls:HxClassDecl):Bool {
		return cls != null && sanitizeTypePath(HxClassDecl.getName(cls)) == "Array";
	}

	public static function arrayBackedAbstractValueCppType(cls:HxClassDecl, classLookup:CppClassLookup):String {
		final underlying = removeTypeHintWhitespace(abstractUnderlyingTypeHint(cls));
		if (StringTools.startsWith(underlying, "Array<") && StringTools.endsWith(underlying, ">"))
			return cppTypeHint(underlying, null, classLookup);
		if (isStdVectorUnderlying(underlying))
			return "std::vector<" + cppTypeHint(genericTypeHintArg(underlying), null, classLookup) + ">";
		return "std::vector<std::string>";
	}

	static function isStdVectorUnderlying(underlying:String):Bool {
		return underlying != null && StringTools.startsWith(underlying, "VectorData<") && StringTools.endsWith(underlying, ">");
	}

	public static function primitiveAbstractUnderlyingCppType(cls:HxClassDecl):Null<String> {
		if (cls == null)
			return null;
		final metadataType = primitiveTypeHintCppType(removeTypeHintWhitespace(abstractUnderlyingTypeHint(cls)));
		if (metadataType != null)
			return metadataType;
		final known = knownPrimitiveBackedAbstractCppType(HxClassDecl.getName(cls));
		return known != null ? known : inferredLiteralAbstractUnderlyingCppType(cls);
	}

	static function inferredLiteralAbstractUnderlyingCppType(cls:HxClassDecl):Null<String> {
		if (!isHxhxAbstractClass(cls))
			return null;
		var found:Null<String> = null;
		var count = 0;
		for (field in HxClassDecl.getFields(cls)) {
			if (!HxFieldDecl.getIsStatic(field))
				continue;
			final name = HxFieldDecl.getName(field);
			if (name != null && StringTools.startsWith(name, "__"))
				continue;
			final literalType = primitiveLiteralExprCppType(HxFieldDecl.getInit(field));
			if (literalType == null)
				return null;
			if (found != null && found != literalType)
				return null;
			found = literalType;
			count++;
		}
		return count == 0 ? null : found;
	}

	static function isHxhxAbstractClass(cls:HxClassDecl):Bool {
		if (cls == null)
			return false;
		for (meta in HxClassDecl.getMetadata(cls))
			if (StringTools.trim(meta) == "__hxhx_abstract")
				return true;
		return false;
	}

	static function primitiveLiteralExprCppType(expr:Null<HxExpr>):Null<String> {
		return switch (expr) {
			case ECast(inner, _) | EUntyped(inner) | EMacroExpr(inner, _):
				primitiveLiteralExprCppType(inner);
			case EInt(_):
				"int";
			case EFloat(_):
				"double";
			case EBool(_):
				"bool";
			case EString(_):
				"std::string";
			case _:
				null;
		};
	}

	public static function primitiveTypeHintCppType(typeHint:String):Null<String> {
		return switch (typeHint) {
			case "String" | "StdTypes.String":
				"std::string";
			case "Int" | "StdTypes.Int":
				"int";
			case "Float" | "StdTypes.Float":
				"double";
			case "Bool" | "StdTypes.Bool":
				"bool";
			case _:
				null;
		};
	}

	public static function knownPrimitiveBackedAbstractCppType(typeHint:String):Null<String> {
		return switch (sanitizeTypePath(typeBaseName(removeTypeHintWhitespace(typeHint)))) {
			// Haxe C++ StdTypes numeric aliases are core abstracts over Int/Float.
			// This mapping only erases their C++ storage shape; width/overflow
			// semantics remain owned by focused runtime/lowering work.
			case "Int8" | "Int16" | "Int32":
				"int";
			case "Int64":
				"long long";
			case "Float32" | "Float64":
				"double";
			case "UInt":
				"unsigned int";
			case _:
				null;
		};
	}

	public static function primitiveBackedAbstractCppTypeForTypeHint(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):Null<String> {
		final cls = lookupClassForTypeHint(typeHint, scope, classLookup);
		final metadataType = primitiveAbstractUnderlyingCppType(cls);
		return metadataType != null ? metadataType : knownPrimitiveBackedAbstractCppType(typeHint);
	}

	public static function arrayBackedAbstractNameForTypeHint(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):Null<String> {
		final cls = lookupClassForTypeHint(typeHint, scope, classLookup);
		return cls != null && isArrayBackedAbstractClass(cls) ? sanitizeTypePath(HxClassDecl.getName(cls)) : null;
	}

	public static function templateWrapAbstractNameForTypeHint(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):Null<String> {
		final cls = lookupClassForTypeHint(typeHint, scope, classLookup);
		if (cls == null || sanitizeTypePath(typeBaseName(HxClassDecl.getName(cls))) != "TemplateWrap")
			return null;
		final underlying = abstractUnderlyingTypeHint(cls);
		return sanitizeTypePath(typeBaseName(underlying == null ? "" : underlying)) == "Template" ? sanitizeTypePath(HxClassDecl.getName(cls)) : null;
	}

	public static function lookupClassForTypeHint(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):Null<HxClassDecl> {
		final hint = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		if (hint.length == 0
			|| isArrayLikeTypeHint(hint)
			|| isIterableTypeHint(hint)
			|| StringTools.startsWith(hint, "Null<")
			|| isFunctionTypeHint(hint))
			return null;
		final generic = hint.indexOf("<");
		final full = sanitizeTypePath(generic >= 0 ? hint.substr(0, generic) : hint);
		final base = sanitizeTypePath(typeBaseName(hint));
		final owner = scope == null ? null : scope.owner;
		if (owner != null) {
			final ownerFull = sanitizeTypePath(HxClassDecl.getName(owner));
			final ownerBase = sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner)));
			if (full == ownerFull || full == ownerBase || base == ownerFull || base == ownerBase)
				return owner;
		}
		if (hint.indexOf(".") >= 0) {
			final qualified = lookupClassByName(full, scope, classLookup);
			if (qualified != null)
				return qualified;
		} else {
			for (name in moduleLocalTypeHintLookupCandidates(hint, base, scope)) {
				final local = lookupClassByName(name, scope, classLookup);
				if (local != null)
					return local;
			}
		}
		final fallback = lookupClassByName(base, scope, classLookup);
		return fallback == null ? null : fallback;
	}

	public static function isArrayLikeTypeHint(typeHint:String):Bool {
		final hint = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		return typeBaseName(hint) == "Array" && StringTools.endsWith(hint, ">");
	}

	public static function isStdArrayTypePath(typeHint:String):Bool {
		return typeBaseName(removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint))) == "Array";
	}

	public static function isIterableTypeHint(typeHint:String):Bool {
		final hint = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		return typeBaseName(hint) == "Iterable" && StringTools.endsWith(hint, ">");
	}

	public static function isIteratorTypeHint(typeHint:String):Bool {
		final hint = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		return typeBaseName(hint) == "Iterator" && StringTools.endsWith(hint, ">");
	}

	public static function genericTypeHintArg(typeHint:String):String {
		final hint = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		final open = hint.indexOf("<");
		return open < 0 || !StringTools.endsWith(hint, ">") ? "" : hint.substr(open + 1, hint.length - open - 2);
	}

	public static function genericTypeHintArgs(typeHint:String):Array<String> {
		final arg = genericTypeHintArg(typeHint);
		return arg.length == 0 ? [] : splitTopLevelComma(arg);
	}

	public static function cppTypeHint(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):String {
		final raw = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		if (isStaleNullPointerTypeHint(raw))
			return "std::any";
		final nullArg = nullTypeHintArg(raw);
		if (nullArg != null)
			return cppNullableTypeHint(nullArg, scope, classLookup);
		if (isBareNullTypeHint(raw))
			return "std::any";
		final hint = raw;
		final primitiveAbstractType = primitiveBackedAbstractCppTypeForTypeHint(hint, scope, classLookup);
		if (primitiveAbstractType != null)
			return primitiveAbstractType;
		final abstractName = arrayBackedAbstractNameForTypeHint(hint, scope, classLookup);
		if (abstractName != null)
			return abstractName;
		final templateWrapName = templateWrapAbstractNameForTypeHint(hint, scope, classLookup);
		if (templateWrapName != null)
			return templateWrapName;
		final scopedTypeParam = scopedGenericTypeParam(hint, scope);
		if (scopedTypeParam != null)
			return scopedTypeParam;
		return switch (hint) {
			case "" | "Void" | "StdTypes.Void":
				hint.length == 0 ? "std::string" : "void";
			case "__HxMacroExpr":
				CppMacroExpr.CPP_TYPE;
			case "Null" | "StdTypes.Null":
				"std::any";
			case "String" | "StdTypes.String":
				"std::string";
			case "Int" | "StdTypes.Int":
				"int";
			case "UInt8" | "cpp.UInt8" | "StdTypes.UInt8":
				"int";
			case _ if (isBytesDataTypeName(hint)):
				"std::vector<int>";
			case "Float" | "StdTypes.Float":
				"double";
			case "Bool" | "StdTypes.Bool":
				"bool";
			case "Dynamic" | "Any":
				"std::string";
			case _ if (isGenericDynamicLikeTypeHint(hint)):
				"std::any";
			case _ if (isCppPointerTypeHint(hint)):
				"std::shared_ptr<" + cppPointerTypeName(hint, scope, classLookup) + ">";
			case _ if (isIteratorTypeHint(hint)):
				"std::shared_ptr<__hxhx_iterator<" + cppTypeHint(genericTypeHintArg(hint), scope, classLookup) + ">>";
			case _ if (isArrayLikeTypeHint(hint) || isIterableTypeHint(hint)):
				"std::vector<" + cppTypeHint(genericTypeHintArg(hint), scope, classLookup) + ">";
			case _ if (isFunctionTypeHint(hint)):
				cppFunctionTypeHint(hint, scope, classLookup);
			case _ if (erasedClassLikeTypeName(hint) != null):
				"std::shared_ptr<" + erasedClassLikeTypeName(hint) + ">";
			case _ if (structuralTypedefTypeNameForTypeHint(hint, scope, classLookup) != null):
				structuralTypedefTypeNameForTypeHint(hint, scope, classLookup);
			case _ if (isClassLikeTypeHint(hint)):
				"std::shared_ptr<" + cppClassLikeTypeName(hint, scope, classLookup) + ">";
			case _:
				"std::string";
		};
	}

	public static function structuralTypedefTypeNameForTypeHint(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):Null<String> {
		final cls = structuralTypedefValueClassForTypeHint(typeHint, scope, classLookup);
		if (cls == null)
			return null;
		return cppClassLikeTypeName(typeHint, scope, classLookup);
	}

	public static function structuralTypedefValueClassForTypeHint(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):Null<HxClassDecl> {
		final cls = classForTypeHint(typeHint, scope, classLookup);
		if (cls == null)
			return null;
		return isStructuralValueTypedefClass(cls, scope, classLookup, [])
			|| isUnmarkedSingleFieldStructuralValueClass(cls, scope, classLookup, []) ? cls : null;
	}

	static function markedStructuralTypedefClassForTypeHint(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):Null<HxClassDecl> {
		final cls = classForTypeHint(typeHint, scope, classLookup);
		if (cls == null || HxClassDecl.getFields(cls).length == 0 || !hasStructuralTypedefMetadata(cls))
			return null;
		return cls;
	}

	static function classForTypeHint(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):Null<HxClassDecl> {
		final raw = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		final generic = raw.indexOf("<");
		final full = sanitizeTypePath(generic >= 0 ? raw.substr(0, generic) : raw);
		final base = sanitizeTypePath(typeBaseName(typeHint));
		final owner = scope == null ? null : scope.owner;
		if (owner != null) {
			final ownerFull = sanitizeTypePath(HxClassDecl.getName(owner));
			final ownerBase = sanitizeTypePath(typeBaseName(HxClassDecl.getName(owner)));
			if (full == ownerFull || full == ownerBase || base == ownerFull || base == ownerBase)
				return owner;
		}
		if (raw.indexOf(".") >= 0) {
			final qualified = lookupClassByName(full, scope, classLookup);
			if (qualified != null)
				return qualified;
		} else {
			for (name in moduleLocalTypeHintLookupCandidates(raw, base, scope)) {
				final local = lookupClassByName(name, scope, classLookup);
				if (local != null)
					return local;
			}
			final nearest = nearestClassForBaseName(base, scope, classLookup);
			if (nearest != null)
				return nearest;
		}
		final fallback = lookupClassByName(base, scope, classLookup);
		if (fallback != null)
			return fallback;
		return null;
	}

	static function lookupClassByName(name:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):Null<HxClassDecl> {
		if (name == null || name.length == 0)
			return null;
		if (scope != null && scope.classByName.exists(name))
			return scope.classByName.get(name);
		if (classLookup != null && classLookup.byName.exists(name))
			return classLookup.byName.get(name);
		return null;
	}

	static function moduleLocalTypeHintLookupCandidates(raw:String, base:String, ?scope:CppRenderScope):Array<String> {
		final out = new Array<String>();
		function add(name:String):Void {
			if (name != null && name.length > 0 && out.indexOf(name) < 0)
				out.push(name);
		}
		if (scope != null && scope.owner != null && raw.indexOf(".") < 0 && base.length > 0) {
			final ownerName = HxClassDecl.getName(scope.owner);
			final ownerBase = sanitizeTypePath(typeBaseName(ownerName == null ? "" : ownerName));
			if (ownerBase.length > 0 && ownerBase != base)
				add(sanitizeTypePath(ownerBase + "." + base));
			final dot = ownerName == null ? -1 : ownerName.lastIndexOf(".");
			if (dot > 0)
				add(sanitizeTypePath(ownerName.substr(0, dot + 1) + base));
		}
		return out;
	}

	static function nearestClassForBaseName(base:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):Null<HxClassDecl> {
		if (base == null || base.length == 0 || scope == null || scope.owner == null)
			return null;
		final all = classLookup != null && classLookup.all != null ? classLookup.all : scope.allClasses;
		if (all == null || all.length == 0)
			return null;
		var ownerIndex = -1;
		for (i in 0...all.length)
			if (all[i] == scope.owner) {
				ownerIndex = i;
				break;
			}
		if (ownerIndex < 0)
			return null;
		var best:Null<HxClassDecl> = null;
		var bestDistance = 0x3fffffff;
		for (i in 0...all.length) {
			final cls = all[i];
			if (cls == scope.owner || sanitizeTypePath(typeBaseName(HxClassDecl.getName(cls))) != base)
				continue;
			final distance = i > ownerIndex ? i - ownerIndex : ownerIndex - i;
			if (distance < bestDistance) {
				best = cls;
				bestDistance = distance;
			}
		}
		return best;
	}

	static function hasStructuralTypedefMetadata(cls:HxClassDecl):Bool {
		if (cls == null)
			return false;
		for (meta in HxClassDecl.getMetadata(cls))
			if (StringTools.trim(meta) == "__hxhx_typedef")
				return true;
		return false;
	}

	static function isStructuralValueTypedefClass(cls:HxClassDecl, ?scope:CppRenderScope, ?classLookup:CppClassLookup, seen:Array<String>):Bool {
		if (cls == null || !hasStructuralTypedefMetadata(cls))
			return false;
		final name = sanitizeTypePath(HxClassDecl.getName(cls));
		if (seen.indexOf(name) >= 0)
			return false;
		final nextSeen = seen.copy();
		nextSeen.push(name);
		var fieldCount = 0;
		for (field in HxClassDecl.getFields(cls)) {
			if (HxFieldDecl.getIsStatic(field))
				continue;
			fieldCount++;
			if (!isStructuralValueTypedefFieldTypeSafe(HxFieldDecl.getTypeHint(field), scope, classLookup, nextSeen))
				return false;
		}
		return fieldCount > 0;
	}

	static function isUnmarkedSingleFieldStructuralValueClass(cls:HxClassDecl, ?scope:CppRenderScope, ?classLookup:CppClassLookup, seen:Array<String>):Bool {
		if (cls == null || hasStructuralTypedefMetadata(cls) || HxClassDecl.getIsInterface(cls))
			return false;
		if (HxClassDecl.getFunctions(cls).length > 0
			|| HxClassDecl.getExtendsPath(cls).length > 0
			|| HxClassDecl.getImplementsPaths(cls).length > 0)
			return false;
		final fields = [
			for (field in HxClassDecl.getFields(cls))
				if (!HxFieldDecl.getIsStatic(field)) field
		];
		if (fields.length != 1)
			return false;
		final fieldCls = markedStructuralTypedefClassForTypeHint(HxFieldDecl.getTypeHint(fields[0]), scope, classLookup);
		return fieldCls != null && isStructuralValueTypedefClass(fieldCls, scope, classLookup, seen);
	}

	static function isStructuralValueTypedefFieldTypeSafe(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup, seen:Array<String>):Bool {
		final hint = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		if (hint.length == 0)
			return false;
		final nullArg = nullTypeHintArg(hint);
		if (nullArg != null)
			return isStructuralValueTypedefFieldTypeSafe(nullArg, scope, classLookup, seen);
		if (primitiveTypeHintCppType(hint) != null)
			return true;
		return switch (hint) {
			case "Dynamic" | "Any" | "StdTypes.Null" | "Null":
				true;
			case _ if (isBytesDataTypeName(hint)):
				true;
			case _ if (isArrayLikeTypeHint(hint) || isIterableTypeHint(hint) || isIteratorTypeHint(hint)):
				isStructuralValueTypedefFieldTypeSafe(genericTypeHintArg(hint), scope, classLookup, seen);
			case _ if (isStructuralTypeHint(hint)): final fields = structuralTypeHintFields(hint); fields.length > 0 && fields.filter(field ->
					!isStructuralValueTypedefFieldTypeSafe(field.typeHint, scope, classLookup, seen))
					.length == 0;
			case _: final cls = markedStructuralTypedefClassForTypeHint(hint, scope,
					classLookup); cls != null && isStructuralValueTypedefClass(cls, scope, classLookup, seen);
		};
	}

	/**
		Detect `Dynamic<T>`/`Any<T>` shapes produced by upstream metadata helpers.

		These are erased value surfaces in the C++ MVP, not real generated template
		classes named `Dynamic` or `Any`.
	**/
	public static function isGenericDynamicLikeTypeHint(typeHint:String):Bool {
		final hint = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		final base = sanitizeTypePath(typeBaseName(hint));
		return (base == "Dynamic" || base == "Any") && genericTypeHintArgs(hint).length > 0;
	}

	static function erasedClassLikeTypeName(typeHint:String):Null<String> {
		return switch (sanitizeTypePath(typeBaseName(typeHint))) {
			case "Class":
				"Class";
			case "Enum":
				"Enum";
			case "KeyValueIterator":
				"KeyValueIterator";
			case _:
				null;
		};
	}

	static function scopedGenericTypeParam(typeHint:String, ?scope:CppRenderScope):Null<String> {
		final clean = sanitizeTypePath(removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint)));
		if (clean.length == 0 || scope == null || scope.owner == null)
			return null;
		if (scope.typeParams != null)
			for (param in scope.typeParams) {
				final candidate = sanitizeTypePath(StringTools.trim(param));
				if (candidate == clean)
					return mappedScopeTypeParam(candidate, scope);
			}
		for (meta in HxClassDecl.getMetadata(scope.owner)) {
			final prefix = "__hxhx_type_params=";
			if (!StringTools.startsWith(meta, prefix))
				continue;
			for (param in meta.substr(prefix.length).split(",")) {
				final candidate = sanitizeTypePath(StringTools.trim(param));
				if (candidate == clean)
					return mappedScopeTypeParam(candidate, scope);
			}
		}
		return null;
	}

	static function mappedScopeTypeParam(param:String, ?scope:CppRenderScope):String {
		final clean = sanitizeTypePath(StringTools.trim(param == null ? "" : param));
		if (scope != null && scope.typeParamCppNames != null) {
			final mapped = scope.typeParamCppNames.get(clean);
			if (mapped != null && mapped.length > 0)
				return mapped;
		}
		return clean;
	}

	static function isCppPointerTypeHint(typeHint:String):Bool {
		return switch (sanitizeTypePath(typeBaseName(typeHint))) {
			case "RawConstPointer" | "ConstPointer" | "RawPointer" | "Pointer":
				true;
			case _:
				false;
		};
	}

	static function cppPointerTypeName(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):String {
		final base = sanitizeTypePath(typeBaseName(typeHint));
		final args = genericTypeHintArgs(typeHint);
		final arg = args.length == 0 ? "void" : cppTypeHint(args[0], scope, classLookup);
		return base + "<" + arg + ">";
	}

	static function cppClassLikeTypeName(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):String {
		final base = sanitizeTypePath(typeBaseName(typeHint));
		final cppBase = shouldQualifyGlobalClassLikeType(base, scope, classLookup) ? "::" + base : base;
		final args = genericTypeHintArgs(typeHint);
		if (args.length == 0)
			return cppBase;
		return cppBase + "<" + [for (arg in args) cppTypeHint(arg, scope, classLookup)].join(", ") + ">";
	}

	static function shouldQualifyGlobalClassLikeType(base:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):Bool {
		if (base == null || base.length == 0 || scope == null || scope.owner == null)
			return false;
		if (!scopeHasClass(scope, base) && (classLookup == null || !classLookup.names.exists(base)))
			return false;
		for (field in HxClassDecl.getFields(scope.owner))
			if (sanitizeIdentifier(HxFieldDecl.getName(field)) == base)
				return true;
		for (fn in HxClassDecl.getFunctions(scope.owner))
			if (sanitizeIdentifier(HxFunctionDecl.getName(fn)) == base)
				return true;
		return false;
	}

	public static function cppReturnTypeHint(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):String {
		final raw = StringTools.trim(typeHint == null ? "" : typeHint);
		if (isStaleNullPointerTypeHint(raw))
			return "std::any";
		final hint = unwrapNullTypeHint(raw);
		return isStructuralTypeHint(hint) ? "auto" : cppTypeHint(raw, scope, classLookup);
	}

	public static function cppNullableTypeHint(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):String {
		final inner = cppTypeHint(typeHint, scope, classLookup);
		if (isCppReferenceType(inner) || isCppOptionalType(inner))
			return inner;
		return "std::optional<" + inner + ">";
	}

	public static function unwrapNullTypeHint(typeHint:String):String {
		final hint = removeTypeHintWhitespace(typeHint);
		final nullArg = nullTypeHintArg(hint);
		if (nullArg != null)
			return nullArg;
		return hint;
	}

	public static function nullTypeHintArg(typeHint:String):Null<String> {
		final hint = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		for (prefix in ["Null<", "StdTypes.Null<"])
			if (StringTools.startsWith(hint, prefix) && StringTools.endsWith(hint, ">"))
				return hint.substr(prefix.length, hint.length - prefix.length - 1);
		return null;
	}

	public static function isBareNullTypeHint(typeHint:String):Bool {
		final hint = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		return hint == "Null" || hint == "StdTypes.Null";
	}

	public static function isStaleNullPointerTypeHint(typeHint:String):Bool {
		final hint = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		return hint == "std::shared_ptr<Null>" || hint == "std::shared_ptr<StdTypes.Null>";
	}

	public static function isFunctionTypeHint(typeHint:String):Bool {
		return splitTopLevelFunctionType(typeHint).length > 1;
	}

	public static function cppFunctionTypeHint(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):String {
		final parts = splitTopLevelFunctionType(typeHint);
		if (parts.length <= 1)
			return "std::function<std::string()>";
		final returnType = cppTypeHint(parts[parts.length - 1], scope, classLookup);
		final args = [
			for (arg in functionArgTypeParts(parts.slice(0, parts.length - 1))) {
				final typePart = functionArgTypePartType(arg);
				functionArgTypePartIsOptional(arg) ? cppNullableTypeHint(typePart, scope, classLookup) : cppTypeHint(typePart, scope, classLookup);
			}
		].filter(t -> t != "void");
		return "std::function<" + returnType + "(" + args.join(", ") + ")>";
	}

	public static function cppFunctionReturnTypeFromCppType(typeName:String):String {
		final prefix = "std::function<";
		if (typeName == null || !StringTools.startsWith(typeName, prefix) || !StringTools.endsWith(typeName, ">"))
			return "";
		final signature = typeName.substr(prefix.length, typeName.length - prefix.length - 1);
		var angleDepth = 0;
		for (i in 0...signature.length) {
			final c = signature.charAt(i);
			if (c == "<")
				angleDepth++;
			else if (c == ">" && angleDepth > 0)
				angleDepth--;
			else if (c == "(" && angleDepth == 0)
				return StringTools.trim(signature.substring(0, i));
		}
		return "";
	}

	public static function cppFunctionArgTypesFromCppType(typeName:String):Array<String> {
		final prefix = "std::function<";
		if (typeName == null || !StringTools.startsWith(typeName, prefix) || !StringTools.endsWith(typeName, ">"))
			return [];
		final signature = typeName.substr(prefix.length, typeName.length - prefix.length - 1);
		var angleDepth = 0;
		var parenStart = -1;
		var i = 0;
		while (i < signature.length) {
			final c = signature.charAt(i);
			if (c == "<")
				angleDepth++;
			else if (c == ">" && angleDepth > 0)
				angleDepth--;
			else if (c == "(" && angleDepth == 0) {
				parenStart = i + 1;
				break;
			}
			i++;
		}
		if (parenStart < 0)
			return [];
		angleDepth = 0;
		i = parenStart;
		while (i < signature.length) {
			final c = signature.charAt(i);
			if (c == "<")
				angleDepth++;
			else if (c == ">" && angleDepth > 0)
				angleDepth--;
			else if (c == ")" && angleDepth == 0) {
				final args = StringTools.trim(signature.substring(parenStart, i));
				return args.length == 0 ? [] : splitTopLevelComma(args);
			}
			i++;
		}
		return [];
	}

	public static function isCppFunctionType(typeName:String):Bool {
		return typeName != null && StringTools.startsWith(typeName, "std::function<") && StringTools.endsWith(typeName, ">");
	}

	public static function splitTopLevelFunctionType(typeHint:String):Array<String> {
		final parts = [];
		var start = 0;
		var angleDepth = 0;
		var parenDepth = 0;
		var braceDepth = 0;
		var i = 0;
		while (i < typeHint.length) {
			final c = typeHint.charAt(i);
			if (c == "<")
				angleDepth++;
			else if (c == ">" && angleDepth > 0)
				angleDepth--;
			else if (c == "(")
				parenDepth++;
			else if (c == ")" && parenDepth > 0)
				parenDepth--;
			else if (c == "{")
				braceDepth++;
			else if (c == "}" && braceDepth > 0)
				braceDepth--;
			else if (c == "-" && i + 1 < typeHint.length && typeHint.charAt(i + 1) == ">" && angleDepth == 0 && parenDepth == 0 && braceDepth == 0) {
				parts.push(stripTypeParens(typeHint.substring(start, i)));
				i += 2;
				start = i;
				continue;
			}
			i++;
		}
		if (parts.length > 0)
			parts.push(stripTypeParens(typeHint.substr(start)));
		return parts;
	}

	public static function splitTopLevelComma(text:String):Array<String> {
		final parts = [];
		var start = 0;
		var angleDepth = 0;
		var parenDepth = 0;
		var braceDepth = 0;
		for (i in 0...text.length) {
			final c = text.charAt(i);
			if (c == "<")
				angleDepth++;
			else if (c == ">" && angleDepth > 0)
				angleDepth--;
			else if (c == "(")
				parenDepth++;
			else if (c == ")" && parenDepth > 0)
				parenDepth--;
			else if (c == "{")
				braceDepth++;
			else if (c == "}" && braceDepth > 0)
				braceDepth--;
			else if (c == "," && angleDepth == 0 && parenDepth == 0 && braceDepth == 0) {
				parts.push(stripTypeParens(text.substring(start, i)));
				start = i + 1;
			}
		}
		parts.push(stripTypeParens(text.substr(start)));
		return parts.filter(part -> part.length > 0);
	}

	static function splitTopLevelStructuralFields(text:String):Array<String> {
		final parts = [];
		var start = 0;
		var angleDepth = 0;
		var parenDepth = 0;
		var braceDepth = 0;
		for (i in 0...text.length) {
			final c = text.charAt(i);
			if (c == "<")
				angleDepth++;
			else if (c == ">" && angleDepth > 0)
				angleDepth--;
			else if (c == "(")
				parenDepth++;
			else if (c == ")" && parenDepth > 0)
				parenDepth--;
			else if (c == "{")
				braceDepth++;
			else if (c == "}" && braceDepth > 0)
				braceDepth--;
			else if ((c == "," || c == ";") && angleDepth == 0 && parenDepth == 0 && braceDepth == 0) {
				parts.push(stripTypeParens(text.substring(start, i)));
				start = i + 1;
			}
		}
		parts.push(stripTypeParens(text.substr(start)));
		return parts.filter(part -> part.length > 0);
	}

	public static function structuralTypeHintFields(typeHint:String):Array<{name:String, typeHint:String}> {
		final hint = StringTools.trim(typeHint == null ? "" : typeHint);
		if (!isStructuralTypeHint(hint))
			return [];
		final inner = hint.substr(1, hint.length - 2);
		final fields = new Array<{name:String, typeHint:String}>();
		for (part in splitTopLevelStructuralFields(inner)) {
			final colon = topLevelColonIndex(part);
			if (colon < 0)
				continue;
			final name = normalizeStructuralFieldName(part.substring(0, colon));
			final fieldTypeHint = StringTools.trim(part.substr(colon + 1));
			if (name.length > 0 && fieldTypeHint.length > 0)
				fields.push({name: name, typeHint: fieldTypeHint});
		}
		return fields;
	}

	static function normalizeStructuralFieldName(name:String):String {
		var out = StringTools.trim(name == null ? "" : name);
		var changed = true;
		while (changed) {
			changed = false;
			if (StringTools.startsWith(out, "?")) {
				out = StringTools.trim(out.substr(1));
				changed = true;
			}
			for (modifier in ["final", "var", "public", "private"]) {
				if (out == modifier)
					return "";
				if (StringTools.startsWith(out, modifier + " ")) {
					out = StringTools.trim(out.substr(modifier.length));
					changed = true;
				}
				if (modifier == "final" && StringTools.startsWith(out, modifier) && out.length > modifier.length) {
					out = StringTools.trim(out.substr(modifier.length));
					changed = true;
				}
			}
		}
		return out;
	}

	public static function topLevelColonIndex(text:String):Int {
		var angleDepth = 0;
		var parenDepth = 0;
		var braceDepth = 0;
		for (i in 0...text.length) {
			final c = text.charAt(i);
			if (c == "<")
				angleDepth++;
			else if (c == ">" && angleDepth > 0)
				angleDepth--;
			else if (c == "(")
				parenDepth++;
			else if (c == ")" && parenDepth > 0)
				parenDepth--;
			else if (c == "{")
				braceDepth++;
			else if (c == "}" && braceDepth > 0)
				braceDepth--;
			else if (c == ":" && angleDepth == 0 && parenDepth == 0 && braceDepth == 0)
				return i;
		}
		return -1;
	}

	public static function stripTypeParens(typeHint:String):String {
		var hint = StringTools.trim(typeHint == null ? "" : typeHint);
		while (StringTools.startsWith(hint, "(") && StringTools.endsWith(hint, ")") && enclosesWholeType(hint))
			hint = StringTools.trim(hint.substr(1, hint.length - 2));
		return hint;
	}

	public static function removeTypeHintWhitespace(typeHint:String):String {
		var out = "";
		final raw = typeHint == null ? "" : typeHint;
		for (i in 0...raw.length) {
			final c = raw.charAt(i);
			if (c != " " && c != "\t" && c != "\n" && c != "\r")
				out += c;
		}
		return out;
	}

	public static function typeBaseName(typeHint:String):String {
		var hint = unwrapNullTypeHint(typeHint);
		if (StringTools.startsWith(hint, "::"))
			hint = hint.substr(2);
		final generic = hint.indexOf("<");
		if (generic >= 0)
			hint = hint.substr(0, generic);
		final dot = hint.lastIndexOf(".");
		return dot >= 0 ? hint.substr(dot + 1) : hint;
	}

	public static function isClassLikeTypeHint(typeHint:String):Bool {
		final base = typeBaseName(typeHint);
		if (base.length == 0)
			return false;
		if (base.length == 1) {
			final c = base.charCodeAt(0);
			if (c >= "A".code && c <= "Z".code)
				return false;
		}
		final first = base.charCodeAt(0);
		return first >= "A".code && first <= "Z".code;
	}

	public static function isStructuralTypeHint(typeHint:String):Bool {
		final hint = removeTypeHintWhitespace(typeHint == null ? "" : typeHint);
		return StringTools.startsWith(hint, "{") && StringTools.endsWith(hint, "}");
	}

	public static function isCppReferenceType(typeName:String):Bool {
		return typeName != null && StringTools.startsWith(typeName, "std::shared_ptr<");
	}

	public static function isCppVectorType(typeName:String):Bool {
		return typeName != null && StringTools.startsWith(typeName, "std::vector<");
	}

	public static function isCppBytesDataVectorType(typeName:String):Bool {
		return typeName == "std::vector<int>";
	}

	public static function cppVectorElementType(typeName:String):String {
		if (!isCppVectorType(typeName) || !StringTools.endsWith(typeName, ">"))
			return "";
		return typeName.substr("std::vector<".length, typeName.length - "std::vector<".length - 1);
	}

	public static function cppIteratorElementType(typeName:String):String {
		final prefix = "std::shared_ptr<__hxhx_iterator<";
		if (typeName == null || !StringTools.startsWith(typeName, prefix) || !StringTools.endsWith(typeName, ">>"))
			return "";
		return typeName.substr(prefix.length, typeName.length - prefix.length - 2);
	}

	public static function isCppArrayBackedAbstractType(typeName:String, ?scope:CppRenderScope):Bool {
		if (scope == null || typeName == null || typeName.length == 0)
			return false;
		final cls = scope.classByName.get(typeName);
		return cls != null && isArrayBackedAbstractClass(cls);
	}

	public static function isCppOptionalType(typeName:String):Bool {
		return typeName != null && StringTools.startsWith(typeName, "std::optional<");
	}

	public static function isScopedGenericCppType(typeName:String, ?scope:CppRenderScope):Bool {
		final clean = sanitizeTypePath(StringTools.trim(typeName == null ? "" : typeName));
		if (clean.length == 0 || scope == null || scope.typeParams == null)
			return false;
		for (param in scope.typeParams) {
			final raw = sanitizeTypePath(StringTools.trim(param == null ? "" : param));
			if (raw == clean || mappedScopeTypeParam(raw, scope) == clean)
				return true;
		}
		return false;
	}

	public static function classNameFromCppType(typeName:String):Null<String> {
		if (!isCppReferenceType(typeName))
			return null;
		final className = typeName.substr("std::shared_ptr<".length, typeName.length - "std::shared_ptr<".length - 1);
		return StringTools.startsWith(className, "::") ? className.substr(2) : className;
	}

	public static function classNameFromCppExprType(typeName:String, ?scope:CppRenderScope):Null<String> {
		final referenceName = classNameFromCppType(typeName);
		if (referenceName != null)
			return referenceName;
		return scopeHasClass(scope, typeName) ? typeName : null;
	}

	public static function cppDefaultValue(typeName:String, ?scope:CppRenderScope):String {
		return switch (typeName) {
			case "void":
				"";
			case "std::string":
				"std::string()";
			case "double":
				"0.0";
			case "bool":
				"false";
			case "std::any":
				"std::any()";
			case "__HxMacroExpr":
				"__HxMacroExpr{}";
			case _ if (StringTools.startsWith(typeName, "std::vector<")):
				"{}";
			case _ if (isCppArrayBackedAbstractType(typeName, scope)):
				typeName + "()";
			case _ if (templateWrapAbstractNameForTypeHint(typeName, scope, null) != null):
				typeName + "()";
			case _ if (isCppReferenceType(typeName)):
				"nullptr";
			case _ if (isCppFunctionType(typeName)):
				"nullptr";
			case _ if (isCppOptionalType(typeName)):
				"std::nullopt";
			case _ if (StringTools.startsWith(typeName, "__hxhx_anon_")):
				typeName + "{}";
			case _ if (scopeHasClass(scope, typeName)):
				typeName + "()";
			case _ if (isScopedGenericCppType(typeName, scope)):
				"nullptr";
			case _:
				"0";
		};
	}

	public static function isBytesDataTypeName(name:String):Bool {
		return sanitizeTypePath(typeBaseName(name == null ? "" : name)) == "BytesData";
	}

	public static function functionArgTypeParts(parts:Array<String>):Array<String> {
		if (parts.length != 1)
			return parts;
		final single = stripTypeParens(parts[0]);
		if (single == "Void" || single == "StdTypes.Void")
			return [];
		return splitTopLevelComma(single);
	}

	public static function functionArgTypePartType(part:String):String {
		final text = stripTypeParens(part);
		final colon = topLevelColonIndex(text);
		if (colon <= 0)
			return StringTools.startsWith(text, "?") ? StringTools.trim(text.substr(1)) : text;
		var name = StringTools.trim(text.substring(0, colon));
		if (StringTools.startsWith(name, "?"))
			name = StringTools.trim(name.substr(1));
		return isIdentifierText(name) ? StringTools.trim(text.substr(colon + 1)) : text;
	}

	public static function functionArgTypePartIsOptional(part:String):Bool {
		final text = stripTypeParens(part);
		final colon = topLevelColonIndex(text);
		if (colon <= 0)
			return StringTools.startsWith(text, "?");
		return StringTools.startsWith(StringTools.trim(text.substring(0, colon)), "?");
	}

	public static function isIdentifierText(text:String):Bool {
		if (text == null || text.length == 0)
			return false;
		for (i in 0...text.length) {
			final code = text.charCodeAt(i);
			final isLetter = (code >= "A".code && code <= "Z".code) || (code >= "a".code && code <= "z".code) || code == "_".code;
			final isDigit = code >= "0".code && code <= "9".code;
			if (i == 0) {
				if (!isLetter)
					return false;
			} else if (!isLetter && !isDigit)
				return false;
		}
		return true;
	}

	static function enclosesWholeType(typeHint:String):Bool {
		var depth = 0;
		for (i in 0...typeHint.length) {
			final c = typeHint.charAt(i);
			if (c == "(")
				depth++;
			else if (c == ")") {
				depth--;
				if (depth == 0 && i < typeHint.length - 1)
					return false;
			}
		}
		return depth == 0;
	}

	static function scopeHasClass(?scope:CppRenderScope, className:String):Bool {
		return scope != null && className != null && (scope.classNames.exists(className) || scope.classByName.exists(className));
	}

	static function sanitizeTypePath(path:String):String {
		if (path == null || path.length == 0)
			return "_";
		return sanitizeIdentifier(StringTools.replace(path, ".", "_"));
	}

	static function sanitizeIdentifier(name:String):String {
		if (name == null || name.length == 0)
			return "_";
		final out = new StringBuf();
		for (i in 0...name.length) {
			final c = name.charAt(i);
			final ok = (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c == "_" || (i > 0 && c >= "0" && c <= "9");
			out.add(ok ? c : "_");
		}
		final s = out.toString();
		final first = s.charAt(0);
		if (first >= "0" && first <= "9")
			return "_" + s;
		return switch (s) {
			case "and" | "and_eq" | "auto" | "bitand" | "bitor" | "bool" | "break" | "case" | "catch" | "class" | "compl" | "const" | "continue" | "delete" |
				"do" | "double" | "else" | "false" | "float" | "for" | "if" | "int" | "long" | "namespace" | "new" | "not" | "not_eq" | "nullptr" | "or" |
				"or_eq" | "private" | "public" | "return" | "short" | "static" | "std" | "struct" | "switch" | "this" | "throw" | "true" | "try" | "void" |
				"while" | "xor" | "xor_eq":
				s
				+ "_";
			case _:
				s;
		};
	}
}
