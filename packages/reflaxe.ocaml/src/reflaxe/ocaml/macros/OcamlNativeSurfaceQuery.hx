package reflaxe.ocaml.macros;

#if macro
import haxe.macro.Type;

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
	visited separately. Results never survive a root query.

	The caller must supply identities from Haxe's complete generation capture.
	Those compiler-owned declarations have already been built and observed by
	the framework before synchronous target validation starts. This contract does
	not authorize fabricated reference getters or earlier typing callbacks.
	An uncaptured declaration, lazy thunk, or monomorph disables all reuse before
	later results can depend on the observation. Ordinary traversal then continues
	in its original order; it is not restarted after possible effects.
**/
class OcamlNativeSurfaceQuery {
	public static inline final OCAML = 1;
	public static inline final ATOMIC = 2;

	final capturedDeclarations:Map<String, Bool>;
	final completedBodies:Map<String, Int> = [];
	var reuseEnabled = true;

	#if reflaxe_lifecycle_test
	public var bodyExpansions(default, null) = 0;
	public var memoHits(default, null) = 0;
	#end

	public function new(capturedDeclarations:Map<String, Bool>) {
		this.capturedDeclarations = capturedDeclarations;
	}

	/** Records declaration identities, not cached type facts or query results. */
	public static function captureDeclarations(types:Array<ModuleType>):Map<String, Bool> {
		final result:Map<String, Bool> = [];
		for (type in types) {
			final key = switch type {
				case TClassDecl(reference): declarationKey(Class, reference.get());
				case TEnumDecl(reference): declarationKey(Enum, reference.get());
				case TTypeDecl(reference): declarationKey(Typedef, reference.get());
				case TAbstract(reference): declarationKey(Abstract, reference.get());
			};
			result.set(key, true);
		}
		return result;
	}

	/** Starts an independent observation; even reuse of this object keeps no old result. */
	public function find(type:Type, depth:Int, requested:Int):Int {
		completedBodies.clear();
		reuseEnabled = true;
		#if reflaxe_lifecycle_test
		bodyExpansions = 0;
		memoHits = 0;
		#end
		return visit(type, depth, requested);
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
		reuseEnabled = false;
		completedBodies.clear();
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

	function visit(type:Type, depth:Int, requested:Int):Int {
		if (depth <= 0 || requested == 0)
			return 0;
		return switch type {
			case TInst(reference, parameters):
				final definition = reference.get();
				observeDeclaration(Class, definition);
				final own = packageMask(definition.pack) & requested;
				own | parametersMask(parameters, depth - 1, requested & ~own);
			case TEnum(reference, parameters):
				final definition = reference.get();
				observeDeclaration(Enum, definition);
				final own = packageMask(definition.pack) & requested;
				own | parametersMask(parameters, depth - 1, requested & ~own);
			case TType(reference, parameters):
				final definition = reference.get();
				final identity = observeDeclaration(Typedef, definition);
				var found = packageMask(definition.pack) & requested;
				found |= parametersMask(parameters, depth - 1, requested & ~found);
				found | body(definition.type, identity, depth - 1, requested & ~found);
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

	public static function moduleMask(type:ModuleType):Int {
		return switch type {
			case TClassDecl(reference): packageMask(reference.get().pack);
			case TEnumDecl(reference): packageMask(reference.get().pack);
			case TTypeDecl(reference): packageMask(reference.get().pack);
			case TAbstract(reference): packageMask(reference.get().pack);
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
