package reflaxe.ocaml.macros;

#if macro
import haxe.macro.Type;
import haxe.macro.TypeTools;

/** Final declarations and their formal parameters, collected without reading parameter references. */
typedef NativeSurfaceCapture = {
	final declarations:Map<String, Bool>;
	final parameters:Array<TypeParameter>;
}

private enum abstract DeclarationKind(String) {
	var Class = "class";
	var Enum = "enum";
	var Typedef = "typedef";
	var Abstract = "abstract";
}

/**
	Finds target-native type families within the existing validation depth limit.

	Only completed named-body queries may be reused. Haxe returns fresh macro
	wrappers when reading a declaration, so keys use its final program identity,
	remaining depth, and requested families. Actual type arguments are always
	visited separately. Ordinary queries never retain results across roots. The
	field-body scan may supply a body-owned result map under its stricter contract.

	The caller must supply identities from Haxe's complete generation capture.
	Those compiler-owned declarations have already been built and observed by
	the framework before synchronous target validation starts. This contract does
	not authorize fabricated reference getters or earlier typing callbacks.
	An uncaptured declaration, lazy thunk, or monomorph disables all reuse before
	later results can depend on the observation. Ordinary traversal then continues
	in its original order; it is not restarted after possible effects.

	Formal parameters are transparent only when Haxe's substitution API identifies
	them as parameters of an observed declaration or field. Their constraints and
	defaults are not traversed. Compiler-created type-expression wrappers are also
	transparent at the expression root, but their bodies are never cached.
**/
class OcamlNativeSurfaceQuery {
	public static inline final OCAML = 1;
	public static inline final ATOMIC = 2;

	final capturedDeclarations:Map<String, Bool>;
	final capturedParameters:Array<TypeParameter>;
	final onObservationBarrier:Null<Void->Void>;
	var ownedParameters:Array<TypeParameter> = [];
	var parameterReplacements:Array<Type> = [];
	var completedBodies:Map<String, Int> = [];
	var reuseEnabled = true;
	var enumPathsAllowed = false;

	#if reflaxe_lifecycle_test
	public var bodyExpansions(default, null) = 0;
	public var memoHits(default, null) = 0;
	public var enumPathReads(default, null) = 0;
	#end

	public function new(capture:NativeSurfaceCapture, ?onObservationBarrier:Void->Void) {
		this.capturedDeclarations = capture.declarations;
		this.capturedParameters = capture.parameters;
		this.onObservationBarrier = onObservationBarrier;
	}

	/** Records declaration identities, not cached type facts or query results. */
	public static function captureDeclarations(types:Array<ModuleType>):NativeSurfaceCapture {
		final result:Map<String, Bool> = [];
		final parameters:Array<TypeParameter> = [];
		function capture(kind:DeclarationKind, definition:BaseType):String {
			for (parameter in definition.params)
				parameters.push(parameter);
			return declarationKey(kind, definition);
		}
		for (type in types) {
			final key = switch type {
				case TClassDecl(reference): capture(Class, reference.get());
				case TEnumDecl(reference): capture(Enum, reference.get());
				case TTypeDecl(reference): capture(Typedef, reference.get());
				case TAbstract(reference): capture(Abstract, reference.get());
			};
			result.set(key, true);
		}
		return {declarations: result, parameters: parameters};
	}

	/** Starts an independent observation; even reuse of this object keeps no old result. */
	public function find(type:Type, depth:Int, requested:Int):Int {
		return start(type, depth, requested, false);
	}

	/**
		Queries a compiler-produced expression from the caller's final generation capture.
		The expression must be decoded by Haxe, without replacement reference getters;
		an assembled TypedExpr record is not sufficient to establish this boundary.
		TTypeExpr supplies a typed witness for its synthetic root alias. Its package,
		parameters, and static fields retain their original traversal and depth charges.
		No owner getter is added, and the witness does not admit nested unknown aliases.
		Compiler expression types permit nominal enum-path reads until the first observation barrier.
	**/
	public function findExpression(expression:TypedExpr, depth:Int, requested:Int):Int {
		return expressionQuery(expression, depth, requested);
	}

	/** Shares only completed named bodies while the scan owns all intervening type observations. */
	@:allow(reflaxe.ocaml.macros.OcamlNativeSurfaceScan)
	function findBodyExpression(expression:TypedExpr, depth:Int, requested:Int, results:Map<String, Int>):Int {
		return expressionQuery(expression, depth, requested, results);
	}

	/** Variable and argument types retain ordinary reads but use the same body invalidation owner. */
	@:allow(reflaxe.ocaml.macros.OcamlNativeSurfaceScan)
	function findBodyType(type:Type, depth:Int, requested:Int, results:Map<String, Int>):Int {
		return start(type, depth, requested, false, false, results);
	}

	function expressionQuery(expression:TypedExpr, depth:Int, requested:Int, ?results:Map<String, Int>):Int {
		final typeExpressionRoot = switch expression.expr {
			case TTypeExpr(_): true;
			case _: false;
		};
		return start(expression.t, depth, requested, typeExpressionRoot, true, results);
	}

	function start(type:Type, depth:Int, requested:Int, typeExpressionRoot:Bool, compilerExpression:Bool = false, ?results:Map<String, Int>):Int {
		completedBodies = results == null ? [] : results;
		reuseEnabled = true;
		enumPathsAllowed = compilerExpression;
		ownedParameters = capturedParameters.copy();
		parameterReplacements = [for (_ in ownedParameters) TDynamic(null)];
		#if reflaxe_lifecycle_test
		bodyExpansions = 0;
		memoHits = 0;
		enumPathReads = 0;
		#end
		return visit(type, depth, requested, typeExpressionRoot);
	}

	/**
		Uses compiler parameter identity rather than fresh wrapper pointers or names.
		The caller has already observed a KTypeParameter at the original getter site.
		Substituting this single parameter does not follow its constraints or defaults.
		TDynamic is only a substitution marker here; it never enters the queried graph.
	**/
	function isOwnedParameter(type:Type):Bool {
		return switch TypeTools.applyTypeParameters(type, ownedParameters, parameterReplacements) {
			case TDynamic(null): true;
			case _: false;
		};
	}

	static function declarationKey(kind:DeclarationKind, type:BaseType):String {
		return kind + ":" + type.module + ":" + type.pack.concat([type.name]).join(".");
	}

	function observeDeclaration(kind:DeclarationKind, type:BaseType):String {
		final key = declarationKey(kind, type);
		if (!capturedDeclarations.exists(key))
			disableReuse();
		return key;
	}

	function disableReuse():Void {
		if (reuseEnabled && onObservationBarrier != null)
			onObservationBarrier();
		reuseEnabled = false;
		enumPathsAllowed = false;
		completedBodies.clear();
	}

	/**
		Identifies the class denoted by an unmodified compiler-decoded class expression.
		The caller contract, not a matching name, permits nominal syntax conversion.
		A body-scoped caller can use this identity only while all intervening queries
		remain observable through onObservationBarrier and no other type work occurs.
	**/
	public function capturedClassIdentity(expression:TypedExpr):Null<String> {
		return switch expression.expr {
			case TTypeExpr(TClassDecl(reference)):
				final syntax = try TypeTools.toComplexType(TInst(reference, [])) catch (_:haxe.Exception) null;
				switch syntax {
					case TPath(path):
						final moduleName = path.pack.concat([path.name]).join(".");
						final typeName = path.pack.concat([path.sub == null ? path.name : path.sub]).join(".");
						final key = Class + ":" + moduleName + ":" + typeName;
						capturedDeclarations.exists(key) ? key : null;
					case _: null;
				}
			case _: null;
		};
	}

	/**
		Reads a captured enum's package without encoding all of its constructors.
		Only a compiler-decoded expression can establish this input boundary.
		Ordinary type queries cannot use it: syntax conversion can call toString on
		a fabricated reference before rejecting it. Every observation barrier ends
		this permission before its getter or thunk runs, including later siblings.

		The syntax conversion receives no actual arguments, so it cannot inspect
		their lazy or unresolved types. The normal walk still visits those arguments.
		Capture membership admits the returned nominal path; it does not authenticate
		arbitrary references. No result is stored across reads or root queries.
	**/
	function capturedEnumPackage(reference:Ref<EnumType>):Null<Int> {
		if (!enumPathsAllowed)
			return null;
		final syntax = try TypeTools.toComplexType(TEnum(reference, [])) catch (_:haxe.Exception) null;
		return switch syntax {
			case TPath(path):
				final moduleName = path.pack.concat([path.name]).join(".");
				final typeName = path.pack.concat([path.sub == null ? path.name : path.sub]).join(".");
				if (!capturedDeclarations.exists(Enum + ":" + moduleName + ":" + typeName)) {
					null;
				} else {
					#if reflaxe_lifecycle_test
					enumPathReads++;
					#end
					packageMask(path.pack);
				}
			case _: null;
		};
	}

	function body(type:Type, declaration:String, depth:Int, requested:Int):Int {
		if (depth <= 0 || requested == 0)
			return 0;
		final key = declaration + ":" + depth + ":" + requested;
		if (reuseEnabled) {
			final previous = completedBodies.get(key);
			if (previous != null) {
				#if reflaxe_lifecycle_test
				memoHits++;
				#end
				return previous;
			}
		}
		#if reflaxe_lifecycle_test
		bodyExpansions++;
		#end
		final result = visit(type, depth, requested);
		// A descendant may have disabled reuse while this body was being read.
		if (reuseEnabled)
			completedBodies.set(key, result);
		return result;
	}

	function visit(type:Type, depth:Int, requested:Int, typeExpressionRoot:Bool = false):Int {
		if (depth <= 0 || requested == 0)
			return 0;
		return switch type {
			case TInst(reference, parameters):
				final definition = reference.get();
				switch definition.kind {
					case KTypeParameter(_) if (reuseEnabled && parameters.length == 0 && isOwnedParameter(type)):
					case _: observeDeclaration(Class, definition);
				}
				final own = packageMask(definition.pack) & requested;
				own | parametersMask(parameters, depth - 1, requested & ~own);
			case TEnum(reference, parameters):
				var ownPackage = capturedEnumPackage(reference);
				if (ownPackage == null) {
					final definition = reference.get();
					observeDeclaration(Enum, definition);
					ownPackage = packageMask(definition.pack);
				}
				final own = ownPackage & requested;
				own | parametersMask(parameters, depth - 1, requested & ~own);
			case TType(reference, parameters):
				final definition = reference.get();
				final identity = typeExpressionRoot ? declarationKey(Typedef, definition) : observeDeclaration(Typedef, definition);
				var found = packageMask(definition.pack) & requested;
				found |= parametersMask(parameters, depth - 1, requested & ~found);
				found | (typeExpressionRoot ? visit(definition.type, depth - 1,
					requested & ~found) : body(definition.type, identity, depth - 1, requested & ~found));
			case TAbstract(reference, parameters):
				final definition = reference.get();
				final identity = observeDeclaration(Abstract, definition);
				var found = packageMask(definition.pack) & requested;
				found |= parametersMask(parameters, depth - 1, requested & ~found);
				found | body(definition.type, identity, depth - 1, requested & ~found);
			case TFun(arguments, result):
				var found = 0;
				for (argument in arguments) {
					found |= visit(argument.t, depth - 1, requested & ~found);
					if (found == requested)
						break;
				}
				found | visit(result, depth - 1, requested & ~found);
			case TAnonymous(reference):
				var found = 0;
				for (field in reference.get().fields) {
					// These declarations came with the field already being visited; no extra getter runs.
					for (parameter in field.params) {
						ownedParameters.push(parameter);
						parameterReplacements.push(TDynamic(null));
					}
					found |= visit(field.type, depth - 1, requested & ~found);
					if (found == requested)
						break;
				}
				found;
			case TDynamic(inner): inner == null ? 0 : visit(inner, depth - 1, requested);
			case TLazy(thunk):
				disableReuse();
				visit(thunk(), depth - 1, requested);
			case TMono(reference):
				disableReuse();
				final resolved = reference.get();
				resolved == null ? 0 : visit(resolved, depth - 1, requested);
		}
	}

	function parametersMask(parameters:Array<Type>, depth:Int, requested:Int):Int {
		var found = 0;
		for (parameter in parameters) {
			found |= visit(parameter, depth, requested & ~found);
			if (found == requested)
				break;
		}
		return found;
	}

	/** Preserves the module getter and notifies the body owner if its declaration is unknown. */
	public function findModule(type:ModuleType):Int {
		function observedMask(kind:DeclarationKind, definition:BaseType):Int {
			observeDeclaration(kind, definition);
			return packageMask(definition.pack);
		}
		return switch type {
			case TClassDecl(reference): observedMask(Class, reference.get());
			case TEnumDecl(reference): observedMask(Enum, reference.get());
			case TTypeDecl(reference): observedMask(Typedef, reference.get());
			case TAbstract(reference): observedMask(Abstract, reference.get());
		};
	}

	static function packageMask(pack:Array<String>):Int {
		var result = 0;
		if (pack.length > 0 && pack[0] == "ocaml")
			result |= OCAML;
		if (pack.length > 1 && pack[0] == "haxe" && pack[1] == "atomic")
			result |= ATOMIC;
		return result;
	}
}
#end
