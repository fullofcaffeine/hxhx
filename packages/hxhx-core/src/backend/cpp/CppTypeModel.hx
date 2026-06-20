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
		return metadataType != null ? metadataType : knownPrimitiveBackedAbstractCppType(HxClassDecl.getName(cls));
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
			case "Int32":
				"int";
			case "Int64":
				"long long";
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

	public static function lookupClassForTypeHint(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):Null<HxClassDecl> {
		final hint = removeTypeHintWhitespace(StringTools.trim(typeHint == null ? "" : typeHint));
		if (hint.length == 0
			|| isArrayLikeTypeHint(hint)
			|| isIterableTypeHint(hint)
			|| StringTools.startsWith(hint, "Null<")
			|| isFunctionTypeHint(hint))
			return null;
		final name = sanitizeTypePath(typeBaseName(hint));
		if (scope != null) {
			final scoped = scope.classByName.get(name);
			if (scoped != null)
				return scoped;
		}
		return classLookup == null ? null : classLookup.byName.get(name);
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
		if (StringTools.startsWith(raw, "Null<") && StringTools.endsWith(raw, ">"))
			return cppNullableTypeHint(raw.substr("Null<".length, raw.length - "Null<".length - 1), scope, classLookup);
		final hint = raw;
		final primitiveAbstractType = primitiveBackedAbstractCppTypeForTypeHint(hint, scope, classLookup);
		if (primitiveAbstractType != null)
			return primitiveAbstractType;
		final abstractName = arrayBackedAbstractNameForTypeHint(hint, scope, classLookup);
		if (abstractName != null)
			return abstractName;
		final scopedTypeParam = scopedGenericTypeParam(hint, scope);
		if (scopedTypeParam != null)
			return scopedTypeParam;
		return switch (hint) {
			case "" | "Void" | "StdTypes.Void":
				hint.length == 0 ? "std::string" : "void";
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
			case _ if (isClassLikeTypeHint(hint)):
				"std::shared_ptr<" + cppClassLikeTypeName(hint, scope, classLookup) + ">";
			case _:
				"std::string";
		};
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
					return candidate;
			}
		for (meta in HxClassDecl.getMetadata(scope.owner)) {
			final prefix = "__hxhx_type_params=";
			if (!StringTools.startsWith(meta, prefix))
				continue;
			for (param in meta.substr(prefix.length).split(",")) {
				final candidate = sanitizeTypePath(StringTools.trim(param));
				if (candidate == clean)
					return candidate;
			}
		}
		return null;
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
		final args = genericTypeHintArgs(typeHint);
		if (args.length == 0)
			return base;
		return base + "<" + [for (arg in args) cppTypeHint(arg, scope, classLookup)].join(", ") + ">";
	}

	public static function cppReturnTypeHint(typeHint:String, ?scope:CppRenderScope, ?classLookup:CppClassLookup):String {
		final raw = StringTools.trim(typeHint == null ? "" : typeHint);
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
		if (StringTools.startsWith(hint, "Null<") && StringTools.endsWith(hint, ">"))
			return hint.substr("Null<".length, hint.length - "Null<".length - 1);
		return hint;
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
			for (arg in functionArgTypeParts(parts.slice(0, parts.length - 1)))
				cppTypeHint(functionArgTypePartType(arg), scope, classLookup)
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

	public static function splitTopLevelFunctionType(typeHint:String):Array<String> {
		final parts = [];
		var start = 0;
		var angleDepth = 0;
		var parenDepth = 0;
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
			else if (c == "-" && i + 1 < typeHint.length && typeHint.charAt(i + 1) == ">" && angleDepth == 0 && parenDepth == 0) {
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

	static function topLevelColonIndex(text:String):Int {
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

	public static function classNameFromCppType(typeName:String):Null<String> {
		if (!isCppReferenceType(typeName))
			return null;
		return typeName.substr("std::shared_ptr<".length, typeName.length - "std::shared_ptr<".length - 1);
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
			case _ if (StringTools.startsWith(typeName, "std::vector<")):
				"{}";
			case _ if (isCppArrayBackedAbstractType(typeName, scope)):
				typeName + "()";
			case _ if (isCppReferenceType(typeName)):
				"nullptr";
			case _ if (isCppOptionalType(typeName)):
				"std::nullopt";
			case _:
				"0";
		};
	}

	public static function isBytesDataTypeName(name:String):Bool {
		return sanitizeTypePath(typeBaseName(name == null ? "" : name)) == "BytesData";
	}

	static function functionArgTypeParts(parts:Array<String>):Array<String> {
		if (parts.length != 1)
			return parts;
		final single = stripTypeParens(parts[0]);
		if (single == "Void" || single == "StdTypes.Void")
			return [];
		return splitTopLevelComma(single);
	}

	static function functionArgTypePartType(part:String):String {
		final text = stripTypeParens(part);
		final colon = topLevelColonIndex(text);
		if (colon <= 0)
			return text;
		var name = StringTools.trim(text.substring(0, colon));
		if (StringTools.startsWith(name, "?"))
			name = StringTools.trim(name.substr(1));
		return isIdentifierText(name) ? StringTools.trim(text.substr(colon + 1)) : text;
	}

	static function isIdentifierText(text:String):Bool {
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
		return scope != null && className != null && scope.classNames.exists(className);
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
