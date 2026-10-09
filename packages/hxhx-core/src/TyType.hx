/**
	Incremental semantic type representation for Stage3 typing.

	`display` remains available for existing diagnostics and target hints, while
	the semantic key records primitives, functions, type parameters, nullable
	types, control flow that does not return normally, and canonical nominal identities structurally. In particular, an abstract never
	becomes its primitive carrier merely because a backend may erase it later.

	This is intentionally not the complete Haxe type system. Unresolved or
	unsupported type grammar remains explicit instead of falling back to a false
	nominal identity.
**/
class TyType {
	static final KIND_UNKNOWN = "unknown";
	static final KIND_PRIMITIVE = "primitive";
	static final KIND_DYNAMIC = "dynamic";
	static final KIND_NULL = "null";
	static final KIND_NULLABLE = "nullable";
	static final KIND_NOMINAL = "nominal";
	static final KIND_ABSTRACT_META = "abstract-meta";
	static final KIND_CLASS_VALUE = "class-value";
	static final KIND_ALIAS_APPLICATION = "alias-application";
	static final KIND_FUNCTION = "function";
	static final KIND_ANONYMOUS = "anonymous";
	static final KIND_TYPE_PARAMETER = "type-parameter";
	static final KIND_OPEN_METHOD_PARAMETER = "open-method-parameter";
	static final KIND_UNRESOLVED = "unresolved";
	static final KIND_NO_NORMAL_COMPLETION = "no-normal-completion";

	public final display:String;

	final kind:String;
	final nominalIdentity:Null<TyNominalTypeId>;
	final typeArguments:Array<TyType>;
	final nullableInner:Null<TyType>;
	final unresolvedPath:String;
	final functionParameters:Array<TyFunctionParameter>;
	final functionReturn:Null<TyType>;
	final anonymousFields:Array<TyAnonymousField>;
	final typeParameterIdentity:Null<TyTypeParameterId>;
	final openMethodParameterIdentity:Null<TyOpenMethodParameterId>;
	final classValueScheme:Null<TyClassValueScheme>;
	final aliasDefinition:Null<TyAliasDefinition>;

	function new(input:TyTypeStorage) {
		display = input.display;
		kind = input.kind;
		nominalIdentity = input.nominalIdentity;
		typeArguments = input.typeArguments == null ? [] : input.typeArguments.copy();
		nullableInner = input.nullableInner;
		unresolvedPath = input.unresolvedPath == null ? "" : input.unresolvedPath;
		functionParameters = input.functionParameters == null ? [] : [for (parameter in input.functionParameters) TyFunctionParameter.copy(parameter)];
		functionReturn = input.functionReturn;
		anonymousFields = input.anonymousFields == null ? [] : [for (field in input.anonymousFields) TyAnonymousField.copy(field)];
		typeParameterIdentity = input.typeParameterIdentity;
		openMethodParameterIdentity = input.openMethodParameterIdentity;
		classValueScheme = input.classValueScheme;
		aliasDefinition = input.aliasDefinition;
	}

	/**
		Retain an alias reference without unfolding its body. Definitions may still
		be under construction here; semantic publication requires a sealed graph.
		Ordinary getters never follow this edge implicitly.
	 */
	public static function aliasApplication(definition:TyAliasDefinition, arguments:Array<TyType>):TyType {
		if (definition == null || arguments == null || definition.getParameterIds().length != arguments.length)
			throw "alias application requires a definition and its exact argument count";
		for (argument in arguments)
			if (argument == null)
				throw "alias application contains a missing argument";
		final name = definition.getCanonicalName();
		return new TyType({
			display: name + (arguments.length == 0 ? "" : "<" + [for (argument in arguments) argument.getCanonicalDisplay()].join(",") + ">"),
			kind: KIND_ALIAS_APPLICATION,
			aliasDefinition: definition,
			typeArguments: arguments
		});
	}

	public function getAliasDefinition():Null<TyAliasDefinition>
		return aliasDefinition;

	/** Store a generic class declaration without selecting its instance arguments. */
	public static function classValue(scheme:TyClassValueScheme):TyType {
		if (scheme == null)
			throw "class value requires a declaration scheme";
		return new TyType({display: "Class<" + scheme.getIdentity().getCanonicalName() + ">", kind: KIND_CLASS_VALUE, classValueScheme: scheme});
	}

	public function getClassValueScheme():Null<TyClassValueScheme>
		return classValueScheme;

	public static function unknown():TyType {
		return new TyType({display: "Unknown", kind: KIND_UNKNOWN});
	}

	/**
		Describe an expression that changes control flow instead of producing a value.

		Examples are `break`, `continue`, and a future expression-position `throw`.
		This is an internal typing fact, not a fake runtime value and not `Dynamic`.
		When one branch has this type, the type of a normally completing branch can
		remain the result of the surrounding expression.
	**/
	public static function noNormalCompletion():TyType {
		return new TyType({display: "NoNormalCompletion", kind: KIND_NO_NORMAL_COMPLETION});
	}

	static function primitive(name:String):TyType {
		return new TyType({display: name, kind: KIND_PRIMITIVE});
	}

	static function dynamicType():TyType {
		return new TyType({display: "Dynamic", kind: KIND_DYNAMIC});
	}

	static function nullType():TyType {
		return new TyType({display: "Null", kind: KIND_NULL});
	}

	public static function nullable(inner:TyType, ?display:String):TyType {
		final actualInner = inner == null ? dynamicType() : inner;
		final shown = display == null || display.length == 0 ? "Null<" + actualInner.getDisplay() + ">" : display;
		return new TyType({display: shown, kind: KIND_NULLABLE, nullableInner: actualInner});
	}

	public static function nominal(identity:TyNominalTypeId, args:Array<TyType>, ?display:String):TyType {
		final actualArgs = args == null ? [] : args;
		var shown = display == null ? "" : StringTools.trim(display);
		if (shown.length == 0) {
			shown = identity.getCanonicalName();
			if (actualArgs.length > 0)
				shown += "<" + [for (arg in actualArgs) arg.getDisplay()].join(",") + ">";
		}
		return new TyType({
			display: shown,
			kind: KIND_NOMINAL,
			nominalIdentity: identity,
			typeArguments: actualArgs
		});
	}

	/**
		Describe a runtime abstract type value, such as the expression `Int`.

		Haxe reports this internal meta-type as `Abstract<T>`. It is neither an
		instance of T nor a Class<T>, and it has no nominal declaration owner.
		Keep the argument structural so substitution and dependency walks see it.
	**/
	public static function abstractMeta(instance:TyType):TyType {
		if (instance == null)
			throw "abstract meta-type requires an instance type";
		return new TyType({display: "Abstract<" + instance.getDisplay() + ">", kind: KIND_ABSTRACT_META, typeArguments: [instance]});
	}

	public function isAbstractMeta():Bool
		return kind == KIND_ABSTRACT_META;

	/** Create a structural function type whose arguments and result remain available to call typing. **/
	public static function functionType(arguments:Array<TyType>, result:TyType, ?display:String):TyType {
		final actualArguments = arguments == null ? [] : arguments;
		final actualResult = result == null ? unknown() : result;
		var shown = display == null ? "" : StringTools.trim(display);
		if (shown.length == 0) {
			final argumentText = actualArguments.length == 0 ? "()" : "(" + [for (argument in actualArguments) argument.getDisplay()].join(", ") + ")";
			shown = argumentText + "->" + (actualResult.isFunction() ? "(" + actualResult.getDisplay() + ")" : actualResult.getDisplay());
		}
		return new TyType({
			display: shown,
			kind: KIND_FUNCTION,
			functionReturn: actualResult,
			functionParameters: [
				for (type in actualArguments)
					TyFunctionParameter.normalizeRest({
						name: null,
						type: type,
						isOptional: false,
						isRest: false,
						metadata: []
					})
			]
		});
	}

	/** Retain named and optional arguments in a declaration-grade function type. */
	public static function functionSignature(parameters:Array<TyFunctionParameter>, result:TyType):TyType {
		final normalized = [for (parameter in parameters) TyFunctionParameter.normalizeRest(parameter)];
		final shown = "(" + [
			for (parameter in normalized)
				(parameter.isRest ? "..." : parameter.isOptional ? "?" : "") + (parameter.name == null ? "" : parameter.name + ":") +
				parameter.type.getCanonicalDisplay()
		].join(",") + ")->" + (result.isFunction() ? "(" + result.getCanonicalDisplay() + ")" : result.getCanonicalDisplay());
		return new TyType({
			display: shown,
			kind: KIND_FUNCTION,
			functionReturn: result,
			functionParameters: normalized
		});
	}

	/** Rebuild child types while preserving argument names, optionality, and metadata. */
	public function withFunctionTypes(arguments:Array<TyType>, result:TyType):TyType {
		if (!isFunction() || arguments.length != functionParameters.length)
			throw "function type rebuild requires the original argument count";
		return functionSignature([
			for (index in 0...arguments.length)
				TyFunctionParameter.withType(functionParameters[index], arguments[index])
		], result);
	}

	/**
		Create a deterministic structural type for an anonymous object literal.

		Field order is not semantic, so names and their inferred types are sorted
		together. Duplicate names keep the final observed value, matching the
		object literal's effective field.
	**/
	public static function anonymous(fieldNames:Array<String>, fieldTypes:Array<TyType>):TyType {
		final fields = new Map<String, TyType>();
		final count = fieldNames == null
			|| fieldTypes == null ? 0 : (fieldNames.length < fieldTypes.length ? fieldNames.length : fieldTypes.length);
		for (index in 0...count) {
			final name = fieldNames[index] == null ? "" : StringTools.trim(fieldNames[index]);
			if (name.length > 0)
				fields.set(name, fieldTypes[index] == null ? unknown() : fieldTypes[index]);
		}
		final names = [for (name in fields.keys()) name];
		names.sort((left, right) -> Reflect.compare(left, right));
		final types = new Array<TyType>();
		for (name in names) {
			final type = fields.get(name);
			types.push(type == null ? unknown() : type);
		}
		final shown = "{" + [
			for (index in 0...names.length)
				names[index] + ":" + types[index].getCanonicalDisplay()
		].join(",") + "}";
		return new TyType({
			display: shown,
			kind: KIND_ANONYMOUS,
			anonymousFields: [
				for (index in 0...names.length)
					TyAnonymousField.inferred(names[index], types[index])
			]
		});
	}

	/** Build a structural declaration after duplicate and extension validation. */
	public static function declaredAnonymous(fields:Array<TyAnonymousField>):TyType {
		final sorted = [for (field in fields) TyAnonymousField.copy(field)];
		sorted.sort((left, right) -> left.name < right.name ? -1 : left.name > right.name ? 1 : 0);
		for (index in 1...sorted.length)
			if (sorted[index - 1].name == sorted[index].name)
				throw "structural type contains duplicate field " + sorted[index].name;
		final shown = "{" + [for (field in sorted) TyAnonymousField.display(field)].join(" ") + "}";
		return new TyType({display: shown, kind: KIND_ANONYMOUS, anonymousFields: sorted});
	}

	/** Rebuild nested types without erasing structural access or method facts. */
	public function withAnonymousTypes(types:Array<TyType>):TyType {
		if (!isAnonymous() || types.length != anonymousFields.length)
			throw "structural type rebuild requires the original field count";
		return declaredAnonymous([
			for (index in 0...types.length)
				TyAnonymousField.withType(anonymousFields[index], types[index])
		]);
	}

	public static function typeParameter(identity:TyTypeParameterId):TyType {
		if (identity == null)
			throw "semantic type parameter requires an exact binder identity";
		return new TyType({display: identity.getName(), kind: KIND_TYPE_PARAMETER, typeParameterIdentity: identity});
	}

	/** A sealed open method instance is a valid type fact, distinct from failed lookup, Unknown, or Dynamic. */
	public static function openMethodParameter(identity:TyOpenMethodParameterId):TyType {
		if (identity == null)
			throw "open method type requires its immutable instance identity";
		return new TyType({display: "Open<" + identity.getName() + ">", kind: KIND_OPEN_METHOD_PARAMETER, openMethodParameterIdentity: identity});
	}

	public function isOpenMethodParameter():Bool
		return kind == KIND_OPEN_METHOD_PARAMETER;

	/** Source-shaped target hints must explicitly erase open parameters without changing semantic facts. */
	public function hasOpenMethodParameter():Bool
		return containsComponent(type -> type.isOpenMethodParameter(), []);

	/** Walk each definition once; application arguments remain separate children. */
	function containsComponent(predicate:TyType->Bool, visited:Array<TyAliasDefinition>):Bool {
		if (predicate(this))
			return true;
		if (aliasDefinition != null && visited.indexOf(aliasDefinition) < 0) {
			visited.push(aliasDefinition);
			if (aliasDefinition.getBody().containsComponent(predicate, visited))
				return true;
		}
		if (nullableInner != null && nullableInner.containsComponent(predicate, visited))
			return true;
		if (functionReturn != null && functionReturn.containsComponent(predicate, visited))
			return true;
		for (component in typeArguments.concat(getFunctionArguments()).concat(getAnonymousFieldTypes()))
			if (component.containsComponent(predicate, visited))
				return true;
		return false;
	}

	public static function unresolved(path:String, args:Array<TyType>, ?display:String):TyType {
		final cleanPath = path == null ? "" : StringTools.trim(path);
		final actualArgs = args == null ? [] : args;
		var shown = display == null ? "" : StringTools.trim(display);
		if (shown.length == 0) {
			shown = cleanPath;
			if (actualArgs.length > 0)
				shown += "<" + [for (arg in actualArgs) arg.getDisplay()].join(",") + ">";
		}
		return new TyType({
			display: shown,
			kind: KIND_UNRESOLVED,
			typeArguments: actualArgs,
			unresolvedPath: cleanPath
		});
	}

	public function isUnknown():Bool
		return kind == KIND_UNKNOWN;

	/** An incomplete structural type cannot serve as a fully selected backend contract. */
	public function hasUnknownComponent():Bool
		return containsComponent(type -> type.isUnknown(), []);

	public function isNoNormalCompletion():Bool
		return kind == KIND_NO_NORMAL_COMPLETION;

	public function isVoid():Bool
		return kind == KIND_PRIMITIVE && display == "Void";

	/** Distinguish language primitives from nominal types that merely have similar display text. */
	public function isPrimitive():Bool
		return kind == KIND_PRIMITIVE;

	public function isNumeric():Bool
		return kind == KIND_PRIMITIVE && (display == "Int" || display == "Float");

	public function isDynamic():Bool
		return kind == KIND_DYNAMIC;

	public function isFunction():Bool
		return kind == KIND_FUNCTION;

	public function isAnonymous():Bool
		return kind == KIND_ANONYMOUS;

	public function isNullWrapped():Bool
		return kind == KIND_NULLABLE;

	public function isNullable():Bool
		return kind == KIND_NULLABLE;

	/** The null literal is distinct from a value whose declared type permits null. */
	public function isNullLiteral():Bool
		return kind == KIND_NULL;

	public function isUnresolved():Bool
		return kind == KIND_UNRESOLVED;

	public function isTypeParameter():Bool
		return kind == KIND_TYPE_PARAMETER;

	public function unwrapNull():TyType {
		return nullableInner == null ? this : nullableInner;
	}

	public function getNullableInner():Null<TyType>
		return nullableInner;

	public function getNominalIdentity():Null<TyNominalTypeId>
		return nominalIdentity;

	public function getTypeArguments():Array<TyType>
		return typeArguments.copy();

	public function getUnresolvedPath():String
		return unresolvedPath;

	public function getFunctionArguments():Array<TyType>
		return [for (parameter in functionParameters) parameter.type];

	public function getFunctionParameters():Array<TyFunctionParameter>
		return [for (parameter in functionParameters) TyFunctionParameter.copy(parameter)];

	public function getFunctionReturn():Null<TyType>
		return functionReturn;

	public function getAnonymousFieldNames():Array<String>
		return [for (field in anonymousFields) field.name];

	public function getAnonymousFieldTypes():Array<TyType>
		return [for (field in anonymousFields) field.type];

	public function getAnonymousFields():Array<TyAnonymousField>
		return [for (field in anonymousFields) TyAnonymousField.copy(field)];

	/** Return the declared parameter name carried by this exact type parameter. **/
	public function getTypeParameterName():Null<String>
		return typeParameterIdentity == null ? null : typeParameterIdentity.getName();

	/** Return the exact class-, abstract-, or method-level binder identity. **/
	public function getTypeParameterIdentity():Null<TyTypeParameterId>
		return typeParameterIdentity;

	public function getSemanticKey():String
		return semanticKeyInScopes([]);

	/**
		Internal structural comparison entry: method-local parameters use their
		scope depth and ordinal. Ordinary callers use getSemanticKey(). Free
		parameters retain exact identities, so no caller or outer binding is captured.
	 */
	public function semanticKeyInScopes(scopes:Array<Array<TyTypeParameterId>>, ?aliases:Array<TyAliasDefinition>):String {
		final path = aliases == null ? [] : aliases;
		if (aliasDefinition != null) {
			final body = aliasDefinition.getBody();
			final name = aliasDefinition.getCanonicalName();
			final previous = path.indexOf(aliasDefinition);
			final ordinal = previous >= 0 ? previous : path.length;
			if (previous < 0)
				path.push(aliasDefinition);
			final args = [for (argument in typeArguments) argument.semanticKeyInScopes(scopes, path)].join(",");
			if (previous >= 0)
				return "alias-ref:" + ordinal + ":" + name + "<" + args + ">";
			// A definition is closed over its own parameters. Caller method scopes
			// apply to arguments, never to the referenced declaration's body. Share
			// the traversal table across siblings to serialize each body only once.
			return "alias:"
				+ ordinal
				+ ":"
				+ name
				+ "<"
				+ args
				+ ">={"
				+ body.semanticKeyInScopes([aliasDefinition.getParameterIds()], path)
				+ "}";
		}
		if (classValueScheme != null)
			return "class-value:" + classValueScheme.getSemanticKey();
		if (kind == KIND_OPEN_METHOD_PARAMETER)
			return "open-method-parameter:" + openMethodParameterIdentity.getCanonicalKey();
		if (kind == KIND_PRIMITIVE)
			return "primitive:" + display;
		if (kind == KIND_DYNAMIC)
			return "dynamic";
		if (kind == KIND_NULL)
			return "null";
		if (kind == KIND_UNKNOWN)
			return "unknown";
		if (kind == KIND_NO_NORMAL_COMPLETION)
			return "no-normal-completion";
		if (kind == KIND_TYPE_PARAMETER) {
			if (typeParameterIdentity != null)
				for (depth in 0...scopes.length) {
					final parameters = scopes[scopes.length - 1 - depth];
					for (index in 0...parameters.length)
						if (typeParameterIdentity.equals(parameters[index]))
							return "bound-parameter:" + depth + ":" + index;
				}
			return "type-parameter:" + (typeParameterIdentity == null ? "<missing>" : typeParameterIdentity.getCanonicalKey());
		}
		if (kind == KIND_NULLABLE)
			return "nullable:" + (nullableInner == null ? "dynamic" : nullableInner.semanticKeyInScopes(scopes, path));
		if (kind == KIND_FUNCTION) {
			final arguments = [
				for (parameter in functionParameters)
					(parameter.isRest ? "..." : parameter.isOptional ? "?" : "") + parameter.type.semanticKeyInScopes(scopes, path)
			].join(",");
			return "function:("
				+ arguments
				+ ")->"
				+ (functionReturn == null ? "unknown" : functionReturn.semanticKeyInScopes(scopes, path));
		}
		if (kind == KIND_ANONYMOUS)
			return "anonymous:{" + [for (field in anonymousFields) TyAnonymousField.semanticKey(field, scopes, path)].join(",") + "}";
		final args = typeArguments.length == 0 ? "" : "<" + [for (arg in typeArguments) arg.semanticKeyInScopes(scopes, path)].join(",") + ">";
		if (kind == KIND_ABSTRACT_META)
			return "abstract-meta" + args;
		if (kind == KIND_NOMINAL)
			return "nominal:" + (nominalIdentity == null ? "" : nominalIdentity.getCanonicalName()) + args;
		return "unresolved:" + unresolvedPath + args;
	}

	/**
		Render this semantic type as a canonical Haxe-shaped type hint.

		Unlike `display`, this spelling uses the resolved nominal identity when one
		exists. Source-shaped backend projections can therefore carry a readable
		type hint without asking each target to repeat import and alias resolution.
	**/
	public function getCanonicalDisplay():String {
		if (aliasDefinition != null)
			return aliasDefinition.getCanonicalName()
				+ (typeArguments.length == 0 ? "" : "<" + [for (argument in typeArguments) argument.getCanonicalDisplay()].join(",") + ">");
		if (classValueScheme != null)
			return classValueScheme.getCanonicalDisplay();
		// Source-shaped backend hints use the opaque carrier for a valid open
		// parameter. The typed graph and revision key retain its exact identity;
		// this rendering must never be fed back as semantic inference evidence.
		if (kind == KIND_OPEN_METHOD_PARAMETER)
			return "Dynamic";
		if (kind == KIND_NULLABLE)
			return "Null<" + (nullableInner == null ? "Dynamic" : nullableInner.getCanonicalDisplay()) + ">";
		if (kind == KIND_FUNCTION) {
			final arguments = [
				for (parameter in functionParameters)
					(parameter.isRest ? "..." : parameter.isOptional ? "?" : "") + (parameter.name == null ? "" : parameter.name + ":") +
					parameter.type.getCanonicalDisplay()
			];
			final result = functionReturn == null ? "Dynamic" : functionReturn.getCanonicalDisplay();
			return "("
				+ arguments.join(",")
				+ ")->"
				+ (functionReturn != null && functionReturn.isFunction() ? "(" + result + ")" : result);
		}
		if (kind == KIND_ANONYMOUS)
			return "{" + [for (field in anonymousFields) TyAnonymousField.display(field)].join(" ") + "}";
		final arguments = typeArguments.length == 0 ? "" : "<" + [for (argument in typeArguments) argument.getCanonicalDisplay()].join(",") + ">";
		if (kind == KIND_ABSTRACT_META)
			return "Abstract" + arguments;
		if (kind == KIND_NOMINAL)
			return (nominalIdentity == null ? "" : nominalIdentity.getCanonicalName()) + arguments;
		if (kind == KIND_UNRESOLVED)
			return unresolvedPath + arguments;
		return display;
	}

	static function genericStart(text:String):Int {
		for (i in 0...text.length)
			if (text.charAt(i) == "<")
				return i;
		return -1;
	}

	static function splitTypeArguments(text:String):Array<String> {
		return splitTopLevel(text, ",");
	}

	static function hasWrappingParentheses(text:String):Bool {
		if (!StringTools.startsWith(text, "(") || !StringTools.endsWith(text, ")"))
			return false;
		var depth = 0;
		for (i in 0...text.length) {
			final ch = text.charAt(i);
			if (ch == "(")
				depth++;
			else if (ch == ")") {
				depth--;
				if (depth == 0 && i < text.length - 1)
					return false;
			}
		}
		return depth == 0;
	}

	static function splitTopLevel(text:String, separator:String):Array<String> {
		final out = new Array<String>();
		var parenDepth = 0;
		var angleDepth = 0;
		var bracketDepth = 0;
		var braceDepth = 0;
		var start = 0;
		for (i in 0...text.length) {
			final ch = text.charAt(i);
			switch (ch) {
				case "(":
					parenDepth++;
				case ")":
					if (parenDepth > 0)
						parenDepth--;
				case "<":
					angleDepth++;
				case ">":
					if (angleDepth > 0 && (i == 0 || text.charAt(i - 1) != "-"))
						angleDepth--;
				case "[":
					bracketDepth++;
				case "]":
					if (bracketDepth > 0)
						bracketDepth--;
				case "{":
					braceDepth++;
				case "}":
					if (braceDepth > 0)
						braceDepth--;
				case _:
			}
			if (ch == separator && parenDepth == 0 && angleDepth == 0 && bracketDepth == 0 && braceDepth == 0) {
				out.push(StringTools.trim(text.substring(start, i)));
				start = i + 1;
			}
		}
		out.push(StringTools.trim(text.substr(start)));
		return out;
	}

	static function splitFunctionSegments(text:String):Array<String> {
		final out = new Array<String>();
		var parenDepth = 0;
		var angleDepth = 0;
		var bracketDepth = 0;
		var braceDepth = 0;
		var start = 0;
		var index = 0;
		while (index < text.length) {
			final ch = text.charAt(index);
			switch (ch) {
				case "(":
					parenDepth++;
				case ")":
					if (parenDepth > 0)
						parenDepth--;
				case "<":
					angleDepth++;
				case ">":
					if (angleDepth > 0 && (index == 0 || text.charAt(index - 1) != "-"))
						angleDepth--;
				case "[":
					bracketDepth++;
				case "]":
					if (bracketDepth > 0)
						bracketDepth--;
				case "{":
					braceDepth++;
				case "}":
					if (braceDepth > 0)
						braceDepth--;
				case _:
			}
			if (ch == "-" && index + 1 < text.length && text.charAt(index + 1) == ">" && parenDepth == 0 && angleDepth == 0 && bracketDepth == 0
				&& braceDepth == 0) {
				out.push(StringTools.trim(text.substring(start, index)));
				index += 2;
				start = index;
				continue;
			}
			index++;
		}
		if (out.length == 0)
			return [];
		out.push(StringTools.trim(text.substr(start)));
		for (segment in out)
			if (segment.length == 0)
				return [];
		return out;
	}

	/** Preserve optional parameters in both named hints and the unnamed hints produced for local functions. */
	static function functionParameterFromHint(text:String):TyFunctionParameter {
		final raw = StringTools.trim(text);
		final rest = StringTools.startsWith(raw, "...");
		final trimmed = rest ? StringTools.trim(raw.substr(3)) : raw;
		var parenDepth = 0;
		var angleDepth = 0;
		var bracketDepth = 0;
		var braceDepth = 0;
		for (i in 0...trimmed.length) {
			final ch = trimmed.charAt(i);
			switch (ch) {
				case "(":
					parenDepth++;
				case ")":
					if (parenDepth > 0)
						parenDepth--;
				case "<":
					angleDepth++;
				case ">":
					if (angleDepth > 0 && (i == 0 || trimmed.charAt(i - 1) != "-"))
						angleDepth--;
				case "[":
					bracketDepth++;
				case "]":
					if (bracketDepth > 0)
						bracketDepth--;
				case "{":
					braceDepth++;
				case "}":
					if (braceDepth > 0)
						braceDepth--;
				case _:
			}
			if (ch == ":" && parenDepth == 0 && angleDepth == 0 && bracketDepth == 0 && braceDepth == 0) {
				final label = StringTools.trim(trimmed.substr(0, i));
				final optional = StringTools.startsWith(label, "?");
				return {
					name: optional ? label.substr(1) : label,
					type: fromHintText(StringTools.trim(trimmed.substr(i + 1))),
					isOptional: optional,
					isRest: rest,
					metadata: []
				};
			}
		}
		final optional = StringTools.startsWith(trimmed, "?");
		return {
			name: null,
			type: fromHintText(optional ? StringTools.trim(trimmed.substr(1)) : trimmed),
			isOptional: optional,
			isRest: rest,
			metadata: []
		};
	}

	static function parseFunctionType(text:String):Null<TyType> {
		final segments = splitFunctionSegments(text);
		if (segments.length < 2)
			return null;
		final arguments = new Array<TyFunctionParameter>();
		for (index in 0...segments.length - 1) {
			var argumentGroup = StringTools.trim(segments[index]);
			// The legacy bare Void marker means no inputs only when it is the
			// entire argument list. Explicit (Void) retains a real Void argument.
			if (segments.length == 2 && argumentGroup == "Void")
				continue;
			if (hasWrappingParentheses(argumentGroup))
				argumentGroup = StringTools.trim(argumentGroup.substr(1, argumentGroup.length - 2));
			if (argumentGroup.length == 0)
				continue;
			for (argument in splitTopLevel(argumentGroup, ",")) {
				if (StringTools.trim(argument).length == 0)
					return null;
				arguments.push(functionParameterFromHint(argument));
			}
		}
		var resultText = StringTools.trim(segments[segments.length - 1]);
		if (hasWrappingParentheses(resultText))
			resultText = StringTools.trim(resultText.substr(1, resultText.length - 2));
		if (resultText.length == 0)
			return null;
		return functionSignature(arguments, fromHintText(resultText));
	}

	/**
		Parse the short required-field record form before resolving its field types.

		Optional fields, properties, extensions, and long declarations need richer
		field contracts. Keep those forms unresolved instead of discarding their
		meaning or treating an optional field as required.
	**/
	static function parseAnonymousType(text:String):Null<TyType> {
		if (!StringTools.endsWith(text, "}"))
			return null;
		final inner = StringTools.trim(text.substring(1, text.length - 1));
		if (inner.length == 0)
			return anonymous([], []);
		final names = new Array<String>();
		final types = new Array<TyType>();
		final fields = splitTopLevel(inner, ",");
		for (index in 0...fields.length) {
			if (fields[index].length == 0 && index == fields.length - 1)
				continue;
			final parts = splitTopLevel(fields[index], ":");
			if (parts.length != 2
				|| !~/^[A-Za-z_][A-Za-z0-9_]*$/.match(parts[0])
				|| names.indexOf(parts[0]) >= 0
				|| parts[1].length == 0)
				return null;
			names.push(parts[0]);
			types.push(fromHintText(parts[1]));
		}
		return anonymous(names, types);
	}

	/** Parse supported structural hints without guessing unresolved declaration identities. **/
	public static function fromHintText(hint:String):TyType {
		if (hint == null)
			return unknown();
		final text = StringTools.trim(hint);
		if (text.length == 0)
			return unknown();
		if (text == "Int" || text == "Float" || text == "Bool" || text == "String" || text == "Void")
			return primitive(text);
		if (text == "Dynamic")
			return dynamicType();
		if (text == "Null")
			return nullType();
		final parsedFunction = parseFunctionType(text);
		if (parsedFunction != null)
			return parsedFunction;
		if (StringTools.startsWith(text, "{")) {
			final parsedAnonymous = parseAnonymousType(text);
			return parsedAnonymous == null ? unresolved(text, [], text) : parsedAnonymous;
		}

		final open = genericStart(text);
		if (open > 0 && StringTools.endsWith(text, ">")) {
			final base = StringTools.trim(text.substring(0, open));
			final inner = text.substring(open + 1, text.length - 1);
			final args = [for (part in splitTypeArguments(inner)) fromHintText(part)];
			if (base == "Null" && args.length == 1)
				return nullable(args[0], text);
			return unresolved(base, args, text);
		}
		return unresolved(text, [], text);
	}

	/**
		Best-effort unification retained for the bootstrap typer.

		Semantic identities improve equality but do not broaden compatibility:
		unknown, numeric widening, nullable wrappers, null, and Dynamic keep their
		existing bounded behavior.
	**/
	public static function unify(a:TyType, b:TyType):Null<TyType> {
		if (a == null || b == null)
			return null;
		if (a.isNoNormalCompletion())
			return b;
		if (b.isNoNormalCompletion())
			return a;
		if (a.isUnknown())
			return b;
		if (b.isUnknown())
			return a;
		if (a.getSemanticKey() == b.getSemanticKey())
			return a;
		if (a.isFunction() && b.isFunction()) {
			final aArguments = a.getFunctionArguments();
			final bArguments = b.getFunctionArguments();
			if (aArguments.length != bArguments.length)
				return null;
			final arguments = new Array<TyType>();
			for (index in 0...aArguments.length) {
				if (a.functionParameters[index].isRest != b.functionParameters[index].isRest)
					return null;
				final left = aArguments[index];
				final right = bArguments[index];
				final argument = left.isUnknown()
					|| left.isDynamic() ? right : right.isUnknown() || right.isDynamic() ? left : unify(left, right);
				if (argument == null)
					return null;
				arguments.push(argument);
			}
			final aReturn = a.getFunctionReturn();
			final bReturn = b.getFunctionReturn();
			if (aReturn == null || bReturn == null)
				return null;
			final result = aReturn.isUnknown()
				|| aReturn.isDynamic() ? bReturn : bReturn.isUnknown() || bReturn.isDynamic() ? aReturn : unify(aReturn, bReturn);
			return result == null ? null : functionSignature([
				for (index in 0...arguments.length)
					{
						name: a.functionParameters[index].name,
						type: arguments[index],
						isOptional: a.functionParameters[index].isOptional && b.functionParameters[index].isOptional,
						isRest: a.functionParameters[index].isRest,
						metadata: a.functionParameters[index].metadata
					}
			], result);
		}
		if (a.display == "Null")
			return b;
		if (b.display == "Null")
			return a;
		if (a.isNullWrapped() && b.isNullWrapped()) {
			final unified = unify(a.unwrapNull(), b.unwrapNull());
			return unified == null ? null : nullable(unified);
		}
		if (a.isNullWrapped()) {
			final unified = unify(a.unwrapNull(), b);
			return unified == null ? null : a;
		}
		if (b.isNullWrapped()) {
			final unified = unify(a, b.unwrapNull());
			return unified == null ? null : b;
		}
		if (a.isNumeric() && b.isNumeric())
			return primitive("Float");
		if (a.display == "Dynamic")
			return a;
		if (b.display == "Dynamic")
			return b;
		return null;
	}

	public function toString():String
		return display;

	/** Non-inline diagnostic-display getter for cross-module OCaml builds. **/
	public function getDisplay():String
		return display;
}

/** Named internal storage input; public factories establish each type constructor's invariants. */
private typedef TyTypeStorage = {
	final display:String;
	final kind:String;
	final ?nominalIdentity:TyNominalTypeId;
	final ?typeArguments:Array<TyType>;
	final ?nullableInner:TyType;
	final ?unresolvedPath:String;
	final ?functionParameters:Array<TyFunctionParameter>;
	final ?functionReturn:TyType;
	final ?anonymousFields:Array<TyAnonymousField>;
	final ?typeParameterIdentity:TyTypeParameterId;
	final ?openMethodParameterIdentity:TyOpenMethodParameterId;
	final ?classValueScheme:TyClassValueScheme;
	final ?aliasDefinition:TyAliasDefinition;
};
