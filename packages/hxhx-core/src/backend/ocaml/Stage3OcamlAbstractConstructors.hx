package backend.ocaml;

/**
	Native construction for generated abstracts whose constructor assigns `this`.

	An abstract has no object of its own. Its value at run time is the backing
	value, and its constructor chooses that value with `this = value`:

	```haxe
	abstract Bag(Map<String, Int>) {
		public function new() this = new Map();
		public function add(key:String):Void this.set(key, 1);
	}
	final bag = new Bag();
	```

	The constructor becomes an OCaml function that returns the backing value,
	and `new Bag()` calls it. The abstract's methods already receive that value
	as their `this_` parameter, so `bag.add("a")` passes the map itself:

	```ocaml
	let rec new_ () = (let this_value = ref (Obj.repr HxRuntime.hx_null) in
	  (try (let _ = (this_value := Obj.repr (... new map ...)) in ())
	   with HxReturn_new _ -> ());
	  Obj.magic (!this_value))
	let bag = Main_Bag.new_ ()
	```

	`this` is a mutable slot while the constructor runs: a later assignment
	replaces an earlier one, and `return` keeps the value assigned so far.
	A constructor body that never assigns `this` is rejected at emit time, as
	upstream Haxe rejects it ("Missing this = value"). Checking that every
	path assigns `this` before it is read is the typer's job; see Bead
	haxe_ocaml-vitgz.

	Only abstracts emitted in this request are registered. Multi-type
	abstracts such as `Map` have no constructor body; their construction is
	selected elsewhere (see `Stage3OcamlMapCalls`).
**/
class Stage3OcamlAbstractConstructors {
	final constructors:Map<String, TypedBackendFunctionProjection> = [];
	final modules:Map<String, String> = [];
	final underlyings:Map<String, TyType> = [];

	public function new() {}

	/**
		Register the constructor of one generated abstract. Class storage supplies
		the abstract's checked identity and backing type from its semantic facts;
		`module` is the OCaml module the abstract is emitted as.
	**/
	public function add(input:{
		projection:TypedBackendClassProjection,
		identity:String,
		underlying:TyType,
		module:String
	}):Void {
		final identity = input.identity;
		if (modules.exists(identity))
			throw "native abstract constructor owner registered twice: " + identity;
		modules.set(identity, input.module);
		underlyings.set(identity, input.underlying);
		for (fn in input.projection.getFunctions()) {
			final declaration = fn.getDeclaration();
			if (HxFunctionDecl.getIsStatic(declaration)
				|| HxFunctionDecl.getName(declaration) != "new"
				|| !HxFunctionDecl.getHasBody(declaration))
				continue;
			if (constructors.exists(identity))
				throw "native abstract has more than one constructor body: " + identity;
			constructors.set(identity, fn);
		}
	}

	/**
		The body owner for `fn` when it is a registered abstract constructor, or
		null for every other function. `names` supplies the fresh OCaml local that
		holds `this` while the body runs.
	**/
	public function body(fn:TypedBackendFunctionProjection, names:Stage3OcamlLocalNames):Null<Stage3OcamlAbstractConstructorBody> {
		for (identity in constructors.keys())
			if (constructors.get(identity) == fn)
				return new Stage3OcamlAbstractConstructorBody(identity, names.internalName("__hx_abstract_this"), underlyings.get(identity));
		return null;
	}

	/** Whether `construct` renders this occurrence: a generated abstract constructor, not a parent call or multi-type selection. */
	public function ownsConstruction(occurrence:TypedBackendConstructorOccurrence):Bool {
		occurrence.assertCurrent();
		if (occurrence.getIsSuperCall())
			return false;
		final identity = occurrence.getConstructedType().getNominalIdentity();
		final application = occurrence.findApplication();
		return identity != null
			&& application != null
			&& constructors.exists(identity.getCanonicalName())
			&& application.getMultiTypeConstruction() == null;
	}

	/**
		Call the generated constructor of the constructed abstract, or return null
		when this request does not own that abstract's construction.
	**/
	public function construct(input:{
		occurrence:TypedBackendConstructorOccurrence,
		currentModule:String,
		names:Stage3OcamlLocalNames,
		emitArgument:(expression:HxExpr, actual:TyType, expected:TyType, expectedIsOptional:Bool) -> String
	}):Null<String> {
		final occurrence = input.occurrence;
		if (!ownsConstruction(occurrence))
			return null;
		final identity = occurrence.getConstructedType().getNominalIdentity();
		final constructor = constructors.get(identity.getCanonicalName());
		final application = occurrence.requireApplication();
		if (constructor.requireSemanticDeclaration() != application.getDeclaration())
			throw "native abstract construction selected another constructor for " + identity.getCanonicalName();
		if (input.names == null)
			throw "native abstract construction requires its exact local naming owner";
		final arguments = new Stage3OcamlConstructorArguments({
			occurrence: occurrence,
			constructor: constructor,
			names: input.names,
			emitArgument: input.emitArgument
		});
		final module = modules.get(identity.getCanonicalName());
		final callee = module == input.currentModule ? "new_" : module + ".new_";
		final parameters = arguments.parameters.length == 0 ? " ()" : arguments.parameters.map(parameter -> " (" + parameter + ")").join("");
		return "(" + arguments.evaluateBefore(callee + parameters) + ")";
	}
}

/**
	The `this` slot of one abstract constructor while its body is emitted.
	Reads and assignments of `this` render through this owner, and `render`
	wraps the emitted statements so the function returns the final value.
**/
class Stage3OcamlAbstractConstructorBody {
	final owner:String;
	final valueName:String;
	final underlying:TyType;
	var assignments = 0;

	public function new(owner:String, valueName:String, underlying:TyType) {
		this.owner = owner;
		this.valueName = valueName;
		this.underlying = underlying;
	}

	/** The type that `this = value` stores. */
	public function getUnderlyingType():TyType
		return underlying;

	/** The current value of `this`, typed by the context that reads it. */
	public function read():String
		return "(Obj.magic (!" + valueName + "))";

	/** Store an already rendered backing value; the result is OCaml `unit`. */
	public function assign(value:String):String {
		assignments++;
		return "(" + valueName + " := Obj.repr (" + value + "))";
	}

	/**
		Wrap the emitted statements. `returnException` is the function's local
		return exception: `return` ends the body and keeps the value assigned so far.
	**/
	public function render(statements:String, returnException:String):String {
		if (assignments == 0)
			throw "stage3 emitter: abstract constructor " + owner + ".new never assigns this; Haxe requires `this = value` (Missing this = value)";
		return "(let " + valueName + " = ref (Obj.repr HxRuntime.hx_null) in (try (let _ = " + statements + " in ()) with " + returnException
			+ " _ -> ()); Obj.magic (!" + valueName + "))";
	}
}
