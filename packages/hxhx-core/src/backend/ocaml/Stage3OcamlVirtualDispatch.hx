package backend.ocaml;

import TypedBackendClassSemanticFacts.TypedBackendClassMethodFact;

/** One class that the native request knows about, with its exact typed facts. */
private typedef VirtualDispatchClass = {
	final facts:TypedBackendClassSemanticFacts;
	final generated:Bool;
	final module:String;
}

/** One entry of a class's method table: the class that implements `method` and its OCaml module. */
typedef Stage3OcamlMethodTableEntry = {
	final method:String;
	final owner:String;
	final module:String;

	/**
		Whether a read through a structure type may bind this method to its
		receiver. False for a method with its own type parameters, an optional
		argument, or a rest argument: the table still dispatches ordinary calls to
		it, but a structural read raises a named, catchable error instead.
	**/
	final structurallyBindable:Bool;
}

/**
	Overridden class methods and `super` calls in Stage3 native OCaml output.

	Why
	- Stage3 writes one OCaml module per Haxe class. An instance method becomes a
	  module-level function whose first argument is the receiver. A call names
	  the function of the class that declares the method, so a call on a value
	  typed as the superclass used to run the superclass method:

	  ```haxe
	  class Person { public function name() return "person"; }
	  class Teacher extends Person { override public function name() return "teacher"; }
	  final p:Person = new Teacher();
	  Sys.println(p.name()); // printed "person"; Haxe prints "teacher"
	  ```

	- `super.name()` rendered its receiver as the placeholder `(Obj.magic 0)`, and
	  the emitter then replaced the whole enclosing expression with that
	  placeholder.

	What
	- A method is *virtual* here when a generated subclass overrides it. Its
	  declaring module then holds two functions:
	  - `name'direct`, the method body as written in that class. The `'` cannot
		appear in a Haxe name, so it cannot collide with another method.
	  - `name`, a dispatcher. It reads the receiver's class, looks up that
		class's function for `name` in the `HxMethodDispatch` runtime, and calls
		it with the same receiver and arguments.
	  Every existing call and method value that names `Person.name` therefore
	  reaches the receiver's override, including implicit `this` calls inside
	  `Person` itself.
	- Each generated class registers one method table. It holds the virtual
	  methods the class answers and the interface methods it implements (see
	  `Stage3OcamlInterfaceDispatch`), each mapped to the nearest declaring
	  class's direct function.
	- Some calls do not need a lookup and stay direct:
	  - a method that no subclass overrides keeps one ordinary function;
	  - `super.name()` calls the nearest ancestor's direct function;
	  - a call whose static receiver type has no subclass that overrides the
		method, such as a call on a `final` class or on the most derived class,
		calls the declaring class's direct function, when that function lives in
		another module. Inside the declaring module the dispatcher is used.

	How
	- Typing chooses the class ancestry and each method's declaration. This
	  class only compares method names along those typed superclass links; it
	  never reads OCaml text.
	- The table is registered at the end of the class's module, after its
	  functions. Code in other modules runs later, because OCaml initializes a
	  module before the modules that use it.

	Limits
	- A static initializer in the class's own module runs before the table is
	  registered. A virtual call there stops with a named "class has no method
	  table" error (haxe_ocaml-j6aof).
	- An overridden method whose calling convention the dispatcher cannot forward
	  unchanged is not dispatched: a `dynamic` method or a rest argument, in the
	  declaration or in an override. A
	  call that would need dispatch fails at emit time with a named error
	  (`requireCallTarget`). Calls on a receiver type that no override can reach
	  stay direct and still compile (haxe_ocaml-w0z3y).
	- A class that is not generated from Haxe bodies (an extern or a module
	  supplied by the native runtime) takes no part: its methods get no
	  dispatcher, and its subclasses' overrides are not reached through it.
	- Only methods with a body are planned. An abstract method of an abstract
	  class would keep its stub; hxhx does not parse abstract classes yet
	  (haxe_ocaml-aqaao).
	- Each virtual call costs a lookup by class name and method name
	  (haxe_ocaml-1hz8t).
**/
class Stage3OcamlVirtualDispatch {
	final classes:Map<String, VirtualDispatchClass> = [];
	final identitiesByModule:Map<String, String> = [];
	final subclasses:Map<String, Array<String>> = [];
	// `identity.method` for each generated method that a generated subclass overrides.
	final overridden:Map<String, Bool> = [];
	// The reason an overridden method cannot dispatch, by `identity.method`.
	final gaps:Map<String, String> = [];
	var planned = false;

	public function new() {}

	/** Record one class or interface of this request. `generated` means Stage3 writes its methods from Haxe bodies. */
	public function add(facts:TypedBackendClassSemanticFacts, generated:Bool, module:String):Void {
		if (!facts.getNominalKind().match(ClassInstance))
			return;
		if (planned)
			throw "native virtual dispatch received a class after planning: " + facts.getClassIdentity();
		final known:VirtualDispatchClass = {facts: facts, generated: generated && !facts.getIsExtern() && !facts.getIsInterface(), module: module};
		classes.set(facts.getClassIdentity(), known);
		if (known.generated)
			identitiesByModule.set(module, facts.getClassIdentity());
	}

	/** The raw Haxe-side name of the direct function that holds a virtual method's own body. */
	public static function directName(method:String):String
		return method + "'direct";

	/** Whether this class's module splits `method` into a direct function and a dispatcher. */
	public function dispatches(identity:String, method:String):Bool {
		plan();
		final key = identity + "." + method;
		return overridden.exists(key) && !gaps.exists(key);
	}

	/** `dispatches`, for the class that a generated OCaml module holds. */
	public function dispatchesInModule(module:String, method:String):Bool {
		final identity = identitiesByModule.get(module);
		return identity != null && dispatches(identity, method);
	}

	/**
		Select the method name to call for `receiver.method(...)`, where typing chose
		the declaration of class `owner` and the receiver's static type is the class
		`receiverType` (null when it is not a known class).

		Returns `method` when the ordinary function is right: the method is not
		overridden, or the call goes through the dispatcher. Returns the direct
		function's name when the static type proves that no override applies and
		the call is made from another module. Throws a named error when the call
		needs dispatch that this method's shape does not support.
	**/
	public function requireCallTarget(owner:String, method:String, receiverType:Null<String>, currentModule:String):String {
		plan();
		final key = owner + "." + method;
		if (!overridden.exists(key))
			return method;
		final exact = receiverType != null && nearestDeclaration(receiverType, method) == owner && !overriddenBelow(receiverType, method);
		final gap = gaps.get(key);
		if (gap != null) {
			if (exact)
				return method;
			throw "stage3 emitter: the call " + key + " has no native virtual dispatch: " + gap;
		}
		final known = classes.get(owner);
		return exact && known.module != currentModule ? directName(method) : method;
	}

	/**
		The method name that `super.method(...)` calls in the superclass module.
		`owner` is the ancestor whose declaration typing selected.
	**/
	public function superCallTarget(owner:String, method:String):String
		return dispatches(owner, method) ? directName(method) : method;

	/** Every virtual method that instances of this class answer, with the class that implements it. */
	public function entries(identity:String):Array<Stage3OcamlMethodTableEntry> {
		plan();
		final result = new Array<Stage3OcamlMethodTableEntry>();
		final known = classes.get(identity);
		if (known == null || !known.generated)
			return result;
		final seen:Map<String, Bool> = [];
		var current:Null<String> = identity;
		while (current != null) {
			final ancestor = classes.get(current);
			if (ancestor == null)
				break;
			for (method in declaredMethods(ancestor))
				if (!seen.exists(method.name) && dispatches(current, method.name)) {
					seen.set(method.name, true);
					final implementation = nearestDeclaration(identity, method.name);
					final implementing = classes.get(implementation);
					final declared = [
						for (candidate in declaredMethods(implementing))
							if (candidate.name == method.name) candidate
					][0];
					result.push({
						method: method.name,
						owner: implementation,
						module: implementing.module,
						structurallyBindable: structurallyBindable(declared)
					});
				}
			current = ancestor.facts.getSuperClassIdentity();
		}
		return result;
	}

	/**
		The statement that registers this class's method table, or null when the
		class answers no virtual or interface method. `interfaceEntries` come from
		`Stage3OcamlInterfaceDispatch`; a method in both lists must have the same
		implementing class. `ident` names a function exported by an OCaml module,
		exactly as the emitter names it.
	**/
	public function registration(facts:TypedBackendClassSemanticFacts, interfaceEntries:Array<Stage3OcamlMethodTableEntry>, currentModule:String,
			ident:(String, String) -> String, quote:String->String):Null<String> {
		final selected = new Array<Stage3OcamlMethodTableEntry>();
		final owners:Map<String, String> = [];
		for (entry in entries(facts.getClassIdentity()).concat(interfaceEntries)) {
			final previous = owners.get(entry.method);
			if (previous != null) {
				if (previous != entry.owner)
					throw "native method table of " + facts.getClassIdentity() + " selects two implementations of " + entry.method;
				continue;
			}
			owners.set(entry.method, entry.owner);
			selected.push(entry);
		}
		if (selected.length == 0)
			return null;
		final rendered = [
			for (entry in selected) {final name = ident(entry.module, superCallTarget(entry.owner, entry.method));
				"("
				+ quote(entry.method)
				+ ", Obj.repr "
				+ (entry.module == currentModule ? name : entry.module + "." + name)
				+ ")";
			}
		];
		final table = "let () = HxMethodDispatch.register_class_methods "
			+ quote(facts.requirePublicReflectionName())
			+ " ["
			+ rendered.join("; ")
			+ "]";
		final excluded = [for (entry in selected) if (!entry.structurallyBindable) quote(entry.method)];
		if (excluded.length == 0)
			return table;
		return table
			+ "\nlet () = HxMethodDispatch.exclude_structural_methods "
			+ quote(facts.requirePublicReflectionName())
			+ " ["
			+ excluded.join("; ")
			+ "]";
	}

	/**
		Whether a structural read can bind this method to its receiver unchanged.
		A structural call site does not pad an omitted optional argument yet, so
		binding such a method would read OCaml's `()` as the argument value.
	**/
	public static function structurallyBindable(method:TypedBackendClassMethodFact):Bool {
		if (method.typeParameters.length > 0)
			return false;
		for (argument in method.arguments)
			if (argument.isRest || argument.isOptional)
				return false;
		return true;
	}

	function plan():Void {
		if (planned)
			return;
		planned = true;
		final identities = [for (identity in classes.keys()) identity];
		identities.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		for (identity in identities) {
			final parent = classes.get(identity).facts.getSuperClassIdentity();
			if (parent == null)
				continue;
			final siblings = subclasses.get(parent);
			if (siblings == null)
				subclasses.set(parent, [identity]);
			else
				siblings.push(identity);
		}
		for (identity in identities) {
			final known = classes.get(identity);
			if (!known.generated)
				continue;
			for (method in declaredMethods(known)) {
				final overrides = overridesBelow(identity, method.name);
				if (overrides.length == 0)
					continue;
				final key = identity + "." + method.name;
				overridden.set(key, true);
				var problem = shapeProblem(method, identity + "." + method.name);
				for (candidate in overrides)
					if (problem == null)
						problem = shapeProblem(candidate.method, candidate.owner + "." + method.name);
				if (problem != null)
					gaps.set(key, problem);
			}
		}
	}

	/** A method shape whose OCaml calling convention a dispatcher cannot forward unchanged. */
	static function shapeProblem(method:TypedBackendClassMethodFact, subject:String):Null<String> {
		if (method.isDynamic)
			return subject + " is a dynamic method";
		for (argument in method.arguments)
			if (argument.isRest)
				return subject + " has a rest argument";
		return null;
	}

	/** Instance methods with a body that a generated class declares itself. */
	static function declaredMethods(known:VirtualDispatchClass):Array<TypedBackendClassMethodFact> {
		if (!known.generated)
			return [];
		return [
			for (method in known.facts.copyMethods())
				if (!method.isStatic && method.hasBody && method.name != "new") method
		];
	}

	/** The generated strict subclasses of `identity` that declare `method` themselves. */
	function overridesBelow(identity:String, method:String):Array<{owner:String, method:TypedBackendClassMethodFact}> {
		final result = new Array<{owner:String, method:TypedBackendClassMethodFact}>();
		final pending = subclasses.exists(identity) ? subclasses.get(identity).copy() : [];
		while (pending.length > 0) {
			final current = pending.shift();
			final known = classes.get(current);
			for (declared in declaredMethods(known))
				if (declared.name == method)
					result.push({owner: current, method: declared});
			if (subclasses.exists(current))
				for (child in subclasses.get(current))
					pending.push(child);
		}
		return result;
	}

	function overriddenBelow(identity:String, method:String):Bool
		return overridesBelow(identity, method).length > 0;

	/** The nearest class from `identity` upwards that declares `method` with a body, or null. */
	function nearestDeclaration(identity:String, method:String):Null<String> {
		var current:Null<String> = identity;
		final visited:Map<String, Bool> = [];
		while (current != null) {
			if (visited.exists(current))
				throw "native virtual dispatch found cyclic ancestry at " + current;
			visited.set(current, true);
			final known = classes.get(current);
			if (known == null)
				return null;
			for (declared in declaredMethods(known))
				if (declared.name == method)
					return current;
			current = known.facts.getSuperClassIdentity();
		}
		return null;
	}
}
