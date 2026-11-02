package backend.ocaml;

import TypedBackendClassSemanticFacts.TypedBackendClassMethodFact;

/** One class that the native request knows about, with its exact typed facts. */
private typedef StringifierClass = {
	final facts:TypedBackendClassSemanticFacts;
	final generated:Bool;
	final module:String;
}

/**
	Calls a class's `toString()` when Stage3 native output turns an instance into text.

	Why
	- Haxe's `Std.string(value)`, string concatenation, and `Array.join` /
	  `Array.toString` call the value's `toString()` method when its class has
	  one. A call through a supertype reaches the override:

	  ```haxe
	  class Animal { public function toString() return "animal"; }
	  class Dog extends Animal { override public function toString() return "dog"; }
	  Sys.println(Std.string((new Dog() : Animal))); // upstream prints dog
	  ```

	- Stage3 stores a class instance as an `HxAnon` object tagged with its class,
	  and its methods are module functions, not fields. The runtime string
	  conversion (`HxDynamic.toStdString`) printed the stored fields instead
	  (`{name: rex}`), because no class told it which function to call.

	What
	- Every generated class whose ancestry has a zero-argument instance
	  `toString()` returning `String` registers one adapter with
	  `HxDynamic.register_class_stringifier`, under the class's own runtime
	  name. The adapter calls the class's own `toString`, or the nearest
	  superclass method it inherits. The runtime looks the adapter up by the
	  receiver's runtime class, so a value typed as a supertype still reaches
	  the override.
	- A class without such a method registers nothing. The runtime then prints
	  the class name, as upstream eval does.

	How
	- Typing chooses the ancestry and each method's declaration; this class only
	  looks for the `toString` name in those typed facts and never reads OCaml
	  text.
	- The registration is the last statement of the class's OCaml module, after
	  its functions. It references only that module and its superclass modules,
	  which the module already depends on.
	- The adapter passes the method's result back through
	  `HxDynamic.toStdString`, so a `toString()` that returns null prints `null`.

	Limits
	- A `dynamic`, static, generic, or argument-taking `toString`, or one
	  inherited from a class without generated bodies, registers nothing. Such a
	  class prints its class name.
	- A static initializer in the class's own module runs before the
	  registration, so converting an instance there prints the class name.
**/
class Stage3OcamlClassStringifiers {
	final classes:Map<String, StringifierClass> = [];

	public function new() {}

	/** Record one class of this request. `generated` means Stage3 writes its methods from Haxe bodies. */
	public function add(facts:TypedBackendClassSemanticFacts, generated:Bool, module:String):Void {
		if (!facts.getNominalKind().match(ClassInstance))
			return;
		classes.set(facts.getClassIdentity(), {facts: facts, generated: generated && !facts.getIsExtern(), module: module});
	}

	/**
		The OCaml statement that registers this class's string adapter, or null
		when the class has no usable `toString()`. `ident` names a function
		exported by an OCaml module, exactly as the emitter names it.
	**/
	public function registration(facts:TypedBackendClassSemanticFacts, currentModule:String, ident:(String, String) -> String,
			quote:String->String):Null<String> {
		final known = classes.get(facts.getClassIdentity());
		if (known == null || !known.generated || facts.getIsInterface())
			return null;
		final owner = toStringOwner(facts.getClassIdentity());
		if (owner == null)
			return null;
		final name = ident(owner.module, "toString");
		final callee = owner.module == currentModule ? name : owner.module + "." + name;
		return "let () = HxDynamic.register_class_stringifier "
			+ quote(facts.requirePublicReflectionName())
			+ " (fun (__hx_value : Obj.t) -> HxDynamic.toStdString (Obj.repr ("
			+ callee
			+ " (Obj.magic __hx_value))))";
	}

	/** The nearest generated class, starting at `identity`, whose instance `toString()` the adapter may call. */
	function toStringOwner(identity:String):Null<StringifierClass> {
		var current:Null<String> = identity;
		final chain:Map<String, Bool> = [];
		while (current != null) {
			if (chain.exists(current))
				throw "native class stringifier found cyclic ancestry at " + current;
			chain.set(current, true);
			final known = classes.get(current);
			if (known == null)
				return null;
			for (method in known.facts.copyMethods())
				if (!method.isStatic && method.name == "toString")
					return known.generated && method.hasBody && usable(method) ? known : null;
			current = known.facts.getSuperClassIdentity();
		}
		return null;
	}

	static function usable(method:TypedBackendClassMethodFact):Bool {
		return !method.isDynamic
			&& method.typeParameters.length == 0
			&& method.arguments.length == 0
			&& method.returnSemanticType != null
			&& method.returnSemanticType.unwrapNull().getSemanticKey() == "primitive:String";
	}
}
