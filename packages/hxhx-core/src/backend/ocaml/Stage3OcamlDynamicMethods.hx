package backend.ocaml;

import TypedBackendClassSemanticFacts.TypedBackendClassMethodFact;
import TypedBackendClassSemanticFacts.TypedBackendClassMethodArgumentFact;

/**
	Calls of class methods through a `Dynamic` value in Stage3 native output.

	Why
	- `final d:Dynamic = new Late(); d.pick();` must find `pick` when the program
	  runs. A Stage3 instance stores its fields in `HxAnon`, while its methods
	  are module-level OCaml functions that take the receiver first, so a field
	  read found nothing. The native program then applied null as a function and
	  stopped with exit 138 (SIGBUS). Upstream Haxe 4.3.7 calls the method.

	What
	- The type of the receiver decides that a call is a Dynamic member call. The
	  receiver and arguments are evaluated once, then the program chooses a path
	  at run time. A class instance uses its method adapters. Any other receiver,
	  and a function stored in an instance's field, uses the stored-function
	  path, which keeps the arguments it always received. Only that path reads a
	  same-named function's signature, and only to convert arguments.
	- Each generated class registers one adapter per method it declares. The
	  adapter reads each `Dynamic` argument into the representation the method's
	  OCaml function expects, then boxes the result as a `Dynamic` value:
	  - an `Int`, `Float`, or `String` parameter needs a real OCaml value, so an
		`Int` argument for a `Float` parameter is converted and a wrong value
		raises a named error instead of being read as memory. An abstract
		parameter follows its backing type;
	  - a `Bool` parameter is read as a plain OCaml Boolean, as a direct call
		passes it. An optional one may also receive null;
	  - a rest parameter collects the remaining arguments into one array;
	  - a `Bool` result is boxed so it still prints as `true` or `false`.

	Limits
	- Only the methods of generated classes are reachable. `String`, `Array`,
	  and other runtime values answer only the fields `HxAnon.get` provides, and
	  a missing one raises a named error (haxe_ocaml-9sa52).
**/
class Stage3OcamlDynamicMethods {
	/**
		The statement that registers this class's declared methods, or null when
		it has none. `ident` names a function exported by an OCaml module, exactly
		as the emitter names it. `virtuals` selects the direct function of an
		overridden method: the override chain is already resolved by the runtime,
		so the dispatcher would only repeat that lookup.
	**/
	public static function registration(facts:TypedBackendClassSemanticFacts, virtuals:Stage3OcamlVirtualDispatch, backing:TyType->TyType, module:String,
			ident:(String, String) -> String, quote:String->String):Null<String> {
		if (facts.getIsExtern() || facts.getIsInterface() || !facts.getNominalKind().match(ClassInstance))
			return null;
		final entries = new Array<String>();
		for (method in facts.copyMethods()) {
			if (!adapterAvailable(method))
				continue;
			final name = ident(module, virtuals.superCallTarget(facts.getClassIdentity(), method.name));
			entries.push("("
				+ quote(method.name)
				+ ", "
				+ (hasRest(method) ? "Stdlib.max_int" : Std.string(method.arguments.length))
				+ ", fun (__hx_this : Obj.t) (__hx_args : Obj.t list) -> "
				+ adapterBody(method, name, backing, quote)
				+ ")");
		}
		if (entries.length == 0)
			return null;
		return "let () = HxDynamicMethods.register " + quote(facts.requirePublicReflectionName()) + " [" + entries.join("; ") + "]";
	}

	/**
		The expression for one Dynamic call. The receiver and arguments are bound
		once, in Haxe order, before the run-time path is chosen. `stored` builds
		the stored-function argument list from the bound names, so nested calls
		stay linear in size.
	**/
	public static function call(input:{
		receiver:String,
		field:String,
		arguments:Array<String>,
		stored:Array<String>->Array<String>,
		names:Stage3OcamlLocalNames,
		quote:String->String
	}):String {
		final receiverName = input.names.internalName("__hx_dynamic_receiver");
		final bound = [
			for (index in 0...input.arguments.length)
				input.names.internalName("__hx_dynamic_argument_" + index)
		];
		final field = input.quote(input.field);
		final target = receiverName + " " + field + " [";
		var body = "(if HxDynamicMethods.is_method " + receiverName + " " + field + " then HxDynamicMethods.call_method " + target + bound.join("; ")
			+ "] else HxDynamicMethods.apply_stored " + target + input.stored(bound).join("; ") + "])";
		var index = input.arguments.length;
		while (index-- > 0)
			body = "let " + bound[index] + " = (" + input.arguments[index] + ") in " + body;
		return "(Obj.magic (let " + receiverName + " = (Obj.repr (" + input.receiver + ")) in " + body + "))";
	}

	/** A method whose OCaml function a Dynamic call can reach with converted arguments. */
	static function adapterAvailable(method:TypedBackendClassMethodFact):Bool {
		return !method.isStatic && method.hasBody && method.name != "new";
	}

	static function hasRest(method:TypedBackendClassMethodFact):Bool {
		return Lambda.exists(method.arguments, argument -> argument.isRest);
	}

	static function adapterBody(method:TypedBackendClassMethodFact, name:String, backing:TyType->TyType, quote:String->String):String {
		final arguments = [
			for (index in 0...method.arguments.length) {
				final parameter = method.arguments[index];
				final read = (parameter.isRest ? "HxDynamicMethods.rest_arguments " : "HxDynamicMethods.argument ")
					+ quote(method.name)
					+ " "
					+ index
					+ " HxDynamicMethods."
					+ (parameter.isRest ? restElementKind(parameter, backing) : argumentKind(parameter, backing))
					+ " __hx_args";
				parameter.isRest ? " (HxBootArray.of_list (Obj.magic (" + read + ")))" : " (Obj.magic (" + read + "))";
			}
		];
		final call = name + " (Obj.magic __hx_this)" + arguments.join("");
		final result = backing(TyAliasExpansion.reveal(method.returnSemanticType));
		if (result.isVoid())
			return "ignore (" + call + "); HxRuntime.hx_null";
		return result.isUnknown() ? "Obj.repr (" + call + ")" : Stage3OcamlObjects.store(result, call);
	}

	/** The runtime argument kind that matches how the method's OCaml function reads this parameter. */
	static function argumentKind(argument:TypedBackendClassMethodArgumentFact, backing:TyType->TyType):String {
		final revealed = TyAliasExpansion.reveal(argument.semanticType);
		final declaredNullable = revealed.isNullable();
		return switch valueKey(revealed, backing) {
			case "primitive:Int": declaredNullable || argument.isOptional ? "Nullable_int_argument" : "Int_argument";
			case "primitive:Float": declaredNullable || argument.isOptional ? "Nullable_float_argument" : "Float_argument";
			// Every Bool parameter reads a plain OCaml bool, and null also selects a default.
			case "primitive:Bool": declaredNullable || argument.isOptional ? "Optional_bool_argument" : "Bool_argument";
			case "String": "String_argument";
			case _: "Value_argument";
		};
	}

	/** A rest parameter's type is its element type, or `haxe.Rest<Element>`. */
	static function restElementKind(argument:TypedBackendClassMethodArgumentFact, backing:TyType->TyType):String {
		final parameters = argument.semanticType.getTypeArguments();
		final element = parameters.length == 1 ? parameters[0] : argument.semanticType;
		return switch valueKey(TyAliasExpansion.reveal(element), backing) {
			case "primitive:Int": "Int_argument";
			case "primitive:Float": "Float_argument";
			case "primitive:Bool": "Bool_argument";
			case "String": "String_argument";
			case _: "Value_argument";
		};
	}

	/** The primitive or String that holds this type's values, following abstracts to their backing type. */
	static function valueKey(type:TyType, backing:TyType->TyType):String {
		final value = TyAliasExpansion.revealNonNullable(backing(TyAliasExpansion.revealNonNullable(type)));
		return value.getCanonicalDisplay() == "String" ? "String" : value.getSemanticKey();
	}
}
