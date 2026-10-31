package backend.ocaml;

import TypedBackendClassSemanticFacts.TypedBackendClassMethodFact;

/** One class that the native request knows about, with its exact typed facts. */
private typedef InterfaceDispatchClass = {
	final facts:TypedBackendClassSemanticFacts;
	final generated:Bool;
	final module:String;
}

/** The function that implements one interface method for one class. */
private typedef InterfaceDispatchEntry = {
	final method:String;
	final module:String;
}

/**
	Calls through an interface type in Stage3 native OCaml output.

	Why
	- Stage3 writes one OCaml module per Haxe class. An instance method becomes a
	  module-level function whose first argument is the receiver, so a call on a
	  class-typed value names the declaring class's function directly.
	- An interface method has no body. Its module used to hold an empty stub
	  that returned the placeholder `0`, and every call through the interface
	  type bound to that stub:

	  ```haxe
	  interface Named { function name():String; }
	  class Person implements Named { ... function name() return "ann"; }
	  final p:Named = new Person();
	  Sys.println(p.name());               // printed 0
	  Sys.println(p.name().toUpperCase()); // crashed with SIGSEGV
	  ```

	What
	- Each generated class that implements an interface, directly, through a
	  superclass, or through an interface that extends another, registers one
	  table in the `HxMethodDispatch` runtime. The table maps every interface
	  method name to the function that implements it for that class: the class's
	  own method, or the nearest superclass method it inherits.
	- The interface module's method is no longer a stub. It reads the receiver's
	  class, takes that class's function from the table, and calls it with the
	  same receiver and arguments. Existing calls and method values that name
	  the interface module therefore reach the implementing class.

	How
	- Typing chooses the class ancestry and each method's declaration. This
	  class only matches interface method names against those typed facts; it
	  never reads OCaml text.
	- A class registers its table while OCaml initializes its module, before any
	  code can allocate one of its instances. The table only references the class's
	  own module and its superclass modules, which it already depends on.
	- An interface method keeps the OCaml type that its stub had, so its callers
	  stay type-checked against the interface signature.

	Limits
	- A generated implementation whose calling convention this table cannot
	  forward unchanged is not supported yet: a `dynamic` method, a method with
	  its own type parameters, and an optional or rest argument on either side.
	  `requireCall` rejects a call through such an interface method at emit
	  time with a named error.
	- A class that is not generated from Haxe bodies (an extern class or a
	  runtime-provided module, for example `haxe.ds.StringMap` implementing
	  `IMap`) registers no table. Whether such a receiver reaches an interface
	  call is only known at run time: the standard `haxe.ds.Map` module always
	  contains `IMap` calls, even though `Map` methods themselves render through
	  `Stage3OcamlMapCalls`. The dispatcher then stops the program with a named
	  `HxMethodDispatch` error. In neither case does a call reach a placeholder.
	- Overridden class methods called on a superclass-typed value still bind to
	  the superclass function. That is a separate gap.
**/
class Stage3OcamlInterfaceDispatch {
	final classes:Map<String, InterfaceDispatchClass> = [];
	var tables:Null<Map<String, Array<InterfaceDispatchEntry>>> = null;
	var gaps:Null<Map<String, String>> = null;

	public function new() {}

	/** Record one class or interface of this request. `generated` means Stage3 writes its methods from Haxe bodies. */
	public function add(facts:TypedBackendClassSemanticFacts, generated:Bool, module:String):Void {
		if (!facts.getNominalKind().match(ClassInstance))
			return;
		if (tables != null)
			throw "native interface dispatch received a class after planning: " + facts.getClassIdentity();
		classes.set(facts.getClassIdentity(), {facts: facts, generated: generated && !facts.getIsExtern(), module: module});
	}

	/** Whether this generated interface method is replaced by a runtime dispatcher. */
	public function ownsInterfaceMethod(identity:String):Bool {
		final known = classes.get(identity);
		return known != null && known.generated && known.facts.getIsInterface();
	}

	/**
		The body of an interface method in the interface's own module.

		`arguments` are the OCaml parameter names after the receiver. The result
		type stays the stub's declared type, so OCaml checks callers as before.
	**/
	public function dispatcherBody(method:String, arguments:Array<String>, resultType:String, quote:String->String):String {
		final parameters = ["this_"].concat(arguments);
		// Name the arrow shape so OCaml does not treat the looked-up value as an
		// unknown type applied to extra arguments (warning 20).
		final shape = [for (_ in parameters) "_"].concat([resultType]).join(" -> ");
		return "((Obj.obj (HxMethodDispatch.class_method (Obj.repr this_) "
			+ quote(method)
			+ ") : "
			+ shape
			+ ") "
			+ parameters.join(" ")
			+ ")";
	}

	/**
		Reject a call through `owner.method` that some implementing class cannot answer.
		Return whether the call goes through an interface dispatcher at all.
	**/
	public function requireCall(owner:String, method:String):Bool {
		final known = classes.get(owner);
		if (known == null || !known.facts.getIsInterface())
			return false;
		plan();
		final gap = gaps.get(owner + "." + method);
		if (gap != null)
			throw "stage3 emitter: the interface call " + owner + "." + method + " has no native dispatch: " + gap;
		if (!known.generated)
			throw "stage3 emitter: the interface call "
				+ owner
				+ "."
				+ method
				+ " has no native dispatch: the interface module is not generated";
		return true;
	}

	/**
		The OCaml statement that registers this class's interface method table, or
		null when the class implements no interface. `ident` names a function
		exported by an OCaml module, exactly as the emitter names it.
	**/
	public function registration(facts:TypedBackendClassSemanticFacts, currentModule:String, ident:(String, String) -> String,
			quote:String->String):Null<String> {
		plan();
		final entries = tables.get(facts.getClassIdentity());
		if (entries == null || entries.length == 0)
			return null;
		final rendered = [
			for (entry in entries) {final name = ident(entry.module, entry.method);
				"("
				+ quote(entry.method)
				+ ", Obj.repr "
				+ (entry.module == currentModule ? name : entry.module + "." + name)
				+ ")";
			}
		];
		return "let () = HxMethodDispatch.register_class_methods "
			+ quote(facts.requirePublicReflectionName())
			+ " ["
			+ rendered.join("; ")
			+ "]";
	}

	function plan():Void {
		if (tables != null)
			return;
		final selected:Map<String, Array<InterfaceDispatchEntry>> = [];
		final missing:Map<String, String> = [];
		final identities = [for (identity in classes.keys()) identity];
		identities.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		for (identity in identities) {
			final known = classes.get(identity);
			if (known.facts.getIsInterface() || !known.generated)
				continue;
			final entries = new Array<InterfaceDispatchEntry>();
			final seen:Map<String, Bool> = [];
			for (declared in interfaceMethods(identity)) {
				if (seen.exists(declared.method.name))
					continue;
				seen.set(declared.method.name, true);
				final key = declared.owner + "." + declared.method.name;
				final problem = methodShapeProblem(declared.method, "the interface method");
				if (problem != null) {
					missing.set(key, problem);
					continue;
				}
				final implementation = implementationFor(identity, declared.method.name);
				// A method inherited from a class without generated bodies stays out
				// of the table; the runtime dispatcher reports it by name.
				if (implementation != null && !implementation.owner.generated)
					continue;
				final failure = implementation == null ? identity + " has no typed implementation" : methodShapeProblem(implementation.method,
					identity + "'s implementation");
				if (failure != null) {
					if (!missing.exists(key))
						missing.set(key, failure);
					continue;
				}
				entries.push({method: declared.method.name, module: implementation.owner.module});
			}
			if (entries.length > 0)
				selected.set(identity, entries);
		}
		tables = selected;
		gaps = missing;
	}

	/** A method shape whose OCaml calling convention this table cannot forward unchanged. */
	static function methodShapeProblem(method:TypedBackendClassMethodFact, subject:String):Null<String> {
		if (method.isDynamic)
			return subject + " is a dynamic method";
		if (method.typeParameters.length > 0)
			return subject + " has its own type parameters";
		for (argument in method.arguments)
			if (argument.isOptional || argument.isRest)
				return subject + " has an optional or rest argument";
		return null;
	}

	/** Every interface method that a class must answer, with its declaring interface, in a deterministic order. */
	function interfaceMethods(identity:String):Array<{owner:String, method:TypedBackendClassMethodFact}> {
		final result = new Array<{owner:String, method:TypedBackendClassMethodFact}>();
		final visited:Map<String, Bool> = [];
		function visitInterface(owner:String):Void {
			if (visited.exists(owner))
				return;
			visited.set(owner, true);
			final known = classes.get(owner);
			if (known == null)
				throw "native interface dispatch lacks the exact interface declaration " + owner;
			for (method in known.facts.copyMethods())
				if (!method.isStatic && method.name != "new")
					result.push({owner: owner, method: method});
			for (parent in known.facts.getInterfaceTypes())
				visitInterface(requireIdentity(parent, owner));
		}
		var current:Null<String> = identity;
		final chain:Map<String, Bool> = [];
		while (current != null) {
			if (chain.exists(current))
				throw "native interface dispatch found cyclic ancestry at " + current;
			chain.set(current, true);
			final known = classes.get(current);
			if (known == null)
				throw "native interface dispatch lacks the exact class declaration " + current;
			for (parent in known.facts.getInterfaceTypes())
				visitInterface(requireIdentity(parent, current));
			current = known.facts.getSuperClassIdentity();
		}
		return result;
	}

	/** The nearest class in the superclass chain, starting at `identity`, that declares this instance method. */
	function implementationFor(identity:String, name:String):Null<{owner:InterfaceDispatchClass, method:TypedBackendClassMethodFact}> {
		var current:Null<String> = identity;
		while (current != null) {
			final known = classes.get(current);
			if (known == null)
				return null;
			for (method in known.facts.copyMethods())
				if (!method.isStatic && method.name == name)
					return method.hasBody || !known.generated ? {owner: known, method: method} : null;
			current = known.facts.getSuperClassIdentity();
		}
		return null;
	}

	static function requireIdentity(type:TyType, owner:String):String {
		final identity = type.getNominalIdentity();
		if (identity == null)
			throw "native interface dispatch requires a resolved interface of " + owner;
		return identity.getCanonicalName();
	}
}
