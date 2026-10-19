package backend.ocaml;

/** One host call retains both its selected declaration and its exact projected operands. */
private typedef NativeCall = {
	final reference:String;
	final arguments:Array<HxExpr>;
}

/**
	Bind extern static functions to literal OCaml module exports in one request.
	The shared index freezes metadata; exact executable occurrences select it.
	Only fixed Int, Float, Bool, String, array, and Void signatures are admitted here. Optional,
	generic, callback, Dynamic, and instance representations need separate ABIs.
	Admission runs before files are written, and no extern body is synthesized.
 */
class Stage3OcamlExternBindings {
	final classes = new Map<String, TypedBackendClassSemanticFacts>();
	final functions = new haxe.ds.ObjectMap<TypedBackendFunctionProjection, Bool>();
	final initializers = new haxe.ds.ObjectMap<TypedBackendFieldInitializerProjection, Bool>();
	final values:Array<HxExpr> = [];

	public function new(modules:Array<TypedModule>) {
		for (module in modules)
			for (owner in module.getBackendProjection().getClasses()) {
				if (ownsClass(owner)) {
					final facts = owner.requireSemanticFacts();
					classes.set(facts.getClassIdentity(), facts);
				}
			}
		if (!classes.iterator().hasNext())
			return;
		for (module in modules)
			for (owner in module.getBackendProjection().getClasses()) {
				for (fn in owner.getFunctions()) {
					functions.set(fn, true);
					for (entry in fn.requireCaptureCatalog().getCallableExpressions())
						admit(entry, fn, null);
				}
				for (field in owner.getFieldInitializers()) {
					initializers.set(field, true);
					for (entry in field.requireCaptureCatalog().getCallableExpressions())
						admit(entry, null, field);
				}
			}
	}

	/** Scan the already checked callable inventory once; ordinary identifier reads need no repeated body validation. */
	function admit(entry:TypedBackendCallableExpression, fn:Null<TypedBackendFunctionProjection>, field:Null<TypedBackendFieldInitializerProjection>):Void {
		selectCall(entry.expression, fn, field);
		if (entry.source.getTag() == NameRead || entry.source.getTag() == FieldRead) {
			if (reference(entry.source.getDeclaration()) != null) {
				values.push(entry.expression);
				value(entry.expression, fn, field);
			}
		}
	}

	/**
		Ordinary locally typed classes need no host-binding facts. The declaration
		category can exclude them, but only indexed facts can authorize an extern.
		A host-owned class contributes declarations, never executable Haxe stubs.
	 */
	public function ownsClass(owner:TypedBackendClassProjection):Bool {
		if (!HxClassDecl.getIsExtern(owner.getDeclaration()))
			return false;
		final facts = owner.requireSemanticFacts();
		return facts.getIsExtern() && facts.getNativeName() != null && facts.getNativeName().getName() != null;
	}

	/** Names are host identifiers, not arbitrary target source or generated-name aliases. */
	static function moduleName(name:String):String {
		if (name == null || !~/^[A-Z][A-Za-z0-9_']*(\.[A-Z][A-Za-z0-9_']*)*$/.match(name))
			throw "OCaml extern requires a literal module path";
		return name;
	}

	static function memberName(name:String):String {
		if (name == null
			|| name == "_"
			|| !~/^[a-z_][A-Za-z0-9_']*$/.match(name)
			|| reflaxe.ocaml.OcamlNameTools.isOcamlReservedValueName(name))
			throw "OCaml extern requires a literal value name";
		return name;
	}

	/** These carriers already agree with the ordinary native runtime; no guessed object conversion is allowed. */
	static function nativeType(type:TyType, result:Bool):Null<String> {
		final type = TyAliasExpansion.reveal(type);
		final nominal = type.getNominalIdentity();
		if (nominal != null && nominal.getCanonicalName() == "Array") {
			final arguments = type.getTypeArguments();
			final element = arguments.length == 1 ? nativeType(arguments[0], false) : null;
			return element == null ? null : "(" + element + " HxArray.t)";
		}
		return switch type.getSemanticKey() {
			case "primitive:Int": "int";
			case "primitive:Float": "float";
			case "primitive:Bool": "bool";
			case "primitive:String": "string";
			case "primitive:Void" if (result): "unit";
			case _: null;
		};
	}

	/** A separately indexed declaration with the same text cannot borrow this program's native export. */
	public function reference(declaration:TyDeclarationInfo):Null<String> {
		if (declaration == null)
			return null;
		final owner = classes.get(declaration.getOwner().getCanonicalName());
		if (owner == null)
			return null;
		final method = owner.requireMethod(declaration);
		final result = nativeType(method.returnSemanticType, true);
		if (!method.isStatic
			|| method.hasBody
			|| method.isDynamic
			|| method.isEnumConstructor
			|| owner.getTypeParameters().length != 0
			|| method.typeParameters.length != 0
			|| result == null)
			throw "OCaml extern requires a supported static native ABI: " + method.canonicalIdentity;
		final signature:Array<String> = [];
		for (argument in method.arguments)
			if (argument.isOptional || argument.isRest || nativeType(argument.semanticType, false) == null)
				throw "OCaml extern requires a supported fixed native argument: " + method.canonicalIdentity;
			else
				signature.push(nativeType(argument.semanticType, false));
		if (signature.length == 0)
			signature.push("unit");
		signature.push(result);
		final renamed = method.nativeName.getName();
		// Let OCaml verify that the real host export implements the declared ABI.
		// Without this annotation, a wrong declaration can leave a partial function
		// where a scalar was promised and still pass a later erased-value boundary.
		return "(" + moduleName(owner.getNativeName().getName()) + "." + memberName(renamed == null ? method.name : renamed) + " : "
			+ signature.join(" -> ") + ")";
	}

	function source(expression:HxExpr, fn:Null<TypedBackendFunctionProjection>, field:Null<TypedBackendFieldInitializerProjection>):Null<TypedExpr> {
		if (field != null) {
			if (!initializers.exists(field))
				throw "OCaml extern has a foreign field initializer";
			return field.findCallableExpression(expression);
		}
		if (fn == null || !functions.exists(fn))
			throw "OCaml extern has a foreign function projection";
		return fn.findCallableExpression(expression);
	}

	function selectCall(expression:HxExpr, fn:Null<TypedBackendFunctionProjection>, field:Null<TypedBackendFieldInitializerProjection>):Null<NativeCall> {
		final call = TypedExactStaticCallSource.decode(expression);
		if (call == null || !classes.exists(call.owner))
			return null;
		final fact = source(expression, fn, field);
		if (fact == null || fact.getTag() != Call)
			throw "OCaml extern requires its exact typed call";
		final children = fact.getExpressions();
		var callee = children[0];
		while (callee.getTag() == Parenthesized || callee.getTag() == CheckType)
			callee = callee.getExpressions()[0];
		final declaration = callee.getDeclaration();
		if (declaration == null
			|| declaration.getIdentity().getCanonicalKey() != call.declaration
			|| declaration.getOwner().getCanonicalName() != call.owner)
			throw "OCaml extern call lost its selected declaration";
		final target = reference(declaration);
		final parameters = declaration.getSignature().getArgs();
		if (call.arguments.length != parameters.length || children.length != parameters.length + 1)
			throw "OCaml extern call requires its fixed argument mapping";
		for (index in 0...parameters.length)
			if (TyAliasExpansion.reveal(children[index + 1].getType()).getSemanticKey() != TyAliasExpansion.reveal(parameters[index]).getSemanticKey())
				throw "OCaml extern call requires an exact native argument carrier";
		return {reference: target, arguments: call.arguments};
	}

	/** Bind arguments left to right before OCaml application, whose evaluation order differs from Haxe. */
	public function renderCall(expression:HxExpr, fn:Null<TypedBackendFunctionProjection>, field:Null<TypedBackendFieldInitializerProjection>,
			emit:HxExpr->String, names:Stage3OcamlLocalNames):Null<String> {
		final call = selectCall(expression, fn, field);
		if (call == null)
			return null;
		if (names == null)
			throw "OCaml extern call requires its local naming owner";
		names.requireOwner(field != null ? field.getLocalCatalog() : fn.getLocalCatalog());
		final locals = [
			for (index in 0...call.arguments.length)
				names.internalName("__hx_native_argument_" + index)
		];
		final values = [for (argument in call.arguments) emit(argument)];
		var output = call.reference + (locals.length == 0 ? " ()" : " " + locals.join(" "));
		var index = values.length;
		while (index-- > 0)
			output = "let " + locals[index] + " = (" + values[index] + ") in " + output;
		return "(" + output + ")";
	}

	/** Saved functions use the same export as direct calls; enclosing callback code owns their storage form. */
	public function value(expression:HxExpr, fn:Null<TypedBackendFunctionProjection>, field:Null<TypedBackendFieldInitializerProjection>):Null<String> {
		if (values.indexOf(expression) < 0)
			return null;
		final fact = source(expression, fn, field);
		if (fact == null || (fact.getTag() != NameRead && fact.getTag() != FieldRead))
			throw "OCaml extern value requires its exact typed occurrence";
		return reference(fact.getDeclaration());
	}
}
