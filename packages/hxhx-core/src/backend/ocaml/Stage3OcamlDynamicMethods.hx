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
	- A Dynamic call now goes through `HxDynamicMethods.call`. The runtime
	  applies a function stored in the receiver, or otherwise finds this class's
	  method adapter on the receiver's class or nearest ancestor.
	- Each generated class registers one adapter per method it declares. The
	  adapter reads each `Dynamic` argument into the representation the method's
	  OCaml function expects, then boxes the result as a `Dynamic` value:
	  - an `Int`, `Float`, or `Bool` parameter needs a real OCaml number or
		Boolean, so an `Int` argument for a `Float` parameter is converted and a
		wrong value raises a named error instead of being read as memory;
	  - a `Bool` result is boxed so it still prints as `true` or `false`.

	Limits
	- A method with its own type parameters or a rest argument gets no adapter.
	  Calling one through `Dynamic` raises a named, catchable error.
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
	public static function registration(facts:TypedBackendClassSemanticFacts, virtuals:Stage3OcamlVirtualDispatch, module:String,
			ident:(String, String) -> String, quote:String->String):Null<String> {
		if (facts.getIsExtern() || facts.getIsInterface() || !facts.getNominalKind().match(ClassInstance))
			return null;
		final entries = new Array<String>();
		for (method in facts.copyMethods()) {
			if (!adapterAvailable(method))
				continue;
			final name = ident(module, virtuals.superCallTarget(facts.getClassIdentity(), method.name));
			entries.push("(" + quote(method.name) + ", " + method.arguments.length + ", fun (__hx_this : Obj.t) (__hx_args : Obj.t list) -> "
				+ adapterBody(method, name, quote) + ")");
		}
		if (entries.length == 0)
			return null;
		return "let () = HxDynamicMethods.register " + quote(facts.requirePublicReflectionName()) + " [" + entries.join("; ") + "]";
	}

	/** The expression for one Dynamic call, evaluating the receiver and then the arguments in Haxe order. */
	public static function call(receiver:String, field:String, arguments:Array<String>, names:Stage3OcamlLocalNames, quote:String->String):String {
		final receiverName = names.internalName("__hx_dynamic_receiver");
		final argumentNames = [
			for (index in 0...arguments.length)
				names.internalName("__hx_dynamic_argument_" + index)
		];
		var body = "(HxDynamicMethods.call " + receiverName + " " + quote(field) + " [" + argumentNames.join("; ") + "])";
		var index = arguments.length;
		while (index-- > 0)
			body = "let " + argumentNames[index] + " = (" + arguments[index] + ") in " + body;
		return "(Obj.magic (let " + receiverName + " = (Obj.repr (" + receiver + ")) in " + body + "))";
	}

	/** A method whose OCaml function a Dynamic call can reach with converted arguments. */
	static function adapterAvailable(method:TypedBackendClassMethodFact):Bool {
		if (method.isStatic || !method.hasBody || method.name == "new" || method.typeParameters.length > 0)
			return false;
		for (argument in method.arguments)
			if (argument.isRest)
				return false;
		return true;
	}

	static function adapterBody(method:TypedBackendClassMethodFact, name:String, quote:String->String):String {
		final arguments = [
			for (index in 0...method.arguments.length)
				" (Obj.magic (HxDynamicMethods.argument "
				+ quote(method.name)
				+ " "
				+ index
				+ " HxDynamicMethods."
				+ argumentKind(method.arguments[index])
				+ " __hx_args))"];
		final call = name + " (Obj.magic __hx_this)" + arguments.join("");
		final result = TyAliasExpansion.reveal(method.returnSemanticType);
		if (result.isVoid())
			return "ignore (" + call + "); HxRuntime.hx_null";
		return result.isUnknown() ? "Obj.repr (" + call + ")" : Stage3OcamlObjects.store(result, call);
	}

	/** The runtime argument kind that matches how the method's OCaml function reads this parameter. */
	static function argumentKind(argument:TypedBackendClassMethodArgumentFact):String {
		final revealed = TyAliasExpansion.reveal(argument.semanticType);
		final key = TyAliasExpansion.revealNonNullable(revealed).getSemanticKey();
		final nullable = argument.isOptional || revealed.isNullable();
		return switch key {
			case "primitive:Int": nullable ? "Nullable_int_argument" : "Int_argument";
			case "primitive:Float": nullable ? "Nullable_float_argument" : "Float_argument";
			case "primitive:Bool": nullable ? "Nullable_bool_argument" : "Bool_argument";
			case _ if (revealed.getCanonicalDisplay() == "String" || revealed.getCanonicalDisplay() == "Null<String>"): "String_argument";
			case _: "Value_argument";
		};
	}
}
