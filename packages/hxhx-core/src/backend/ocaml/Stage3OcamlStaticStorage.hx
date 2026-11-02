package backend.ocaml;

/** How one mutable static field keeps its value in native OCaml. */
enum Stage3OcamlStaticCell {
	/** A non-null Int, Float, Bool, or String in an OCaml `ref` of that type (`int ref`, ...). */
	Typed(ocamlType:String);

	/**
		Every other type in an `Obj.t ref`: class instances, arrays, nullable values,
		functions, and abstracts. A write stores `Obj.repr value`; a read produces
		`Obj.obj` of the cell, so each use site keeps the representation it already
		expects. `Null<Int>` and `Null<Float>` carriers are already `Obj.t` values.
	**/
	Erased;
}

/** How the emitter renders the right operand of a static write before this module stores it. */
enum Stage3OcamlStaticOperand {
	/** The value in its ordinary rendering. */
	Plain;

	/** An OCaml float; Haxe promotes an Int written to a Float destination. */
	FloatValue;

	/** A String, stringifying a non-String operand of `+=` as Haxe concatenation does. */
	StringAppend;
}

/** One write whose target is a typed static field with mutable storage. */
typedef Stage3OcamlStaticWrite = {
	final target:TypedBackendFieldOccurrence;

	/** `=`, a compound operator such as `+=`, or `++`/`--`. */
	final op:String;

	/** The right operand; null for `++`/`--`. */
	final value:Null<HxExpr>;

	final postfix:Bool;
	final operand:Stage3OcamlStaticOperand;
}

/** One static field that this request stores in a mutable cell. */
private typedef StoredStatic = {
	/** The Haxe spelling used in diagnostics, such as `counters.Registry.count`. */
	final key:String;

	final module:String;
	final ident:String;
	final type:TyType;
	final cell:Stage3OcamlStaticCell;
}

/**
	Storage for mutable static fields in Stage3 native OCaml output.

	Why
	- Stage3 writes one OCaml module per Haxe class and used to bind every static
	  field to a module-level `let`. An OCaml `let` cannot change, so every write
	  was dropped without an error: `count++` emitted `ignore ((Obj.magic 0))`,
	  `items = []` and `Main.items = [...]` emitted `()`, and the program kept
	  printing the initial values. A write from another class, such as
	  `Holder.sf = x`, emitted a reference to a value that does not exist.

	What
	- A static `var` with physical storage in a generated class is bound to an
	  OCaml `ref` at module level, so writes from any module and any closure
	  update one cell, and every read sees the latest value:

	  ```haxe
	  class Registry { public static var count = 0; }
	  Registry.count += 5;           // from another class
	  ```
	  ```ocaml
	  let __hx_static_count : int ref = ref (0)           (* Counters_Registry.ml *)
	  ... Counters_Registry.__hx_static_count := ... (!Counters_Registry.__hx_static_count) ...
	  ```
	- `static final`, `static inline`, and accessor-only properties without
	  storage keep their immutable `let` or their accessor calls. A
	  `(default, null)` property is stored here because its own class may write it.
	- Plain assignment, the arithmetic compound operators, and prefix and postfix
	  `++`/`--` produce the value Haxe 4.3.7 produces: the stored value, or the
	  old value for a postfix update.
	- A write this module cannot store stops emission with a named error, never
	  `()` or a placeholder: a static owned by an extern, a runtime-provided
	  module, or a class without typed facts; a write through a property setter;
	  a bitwise or `??=` compound operator; and a numeric update of a type without
	  a native number representation.

	How
	- `add` selects the stored fields once per request from the typed class facts,
	  before any module is emitted, so a read in one module and the declaration
	  in another always agree on the representation.
	- Reads and writes find the field through the exact typed field occurrence
	  of the active body (`TypedBackendFieldOccurrence`), never through source
	  spelling. The cell is bound as `__hx_static_<name>`, a spelling that no
	  local or parameter can have, so a same-named local never shadows it in
	  the generated OCaml either.
	- An uninitialized Int, Float, or Bool static starts at 0, 0.0, or false, as
	  on Haxe's static targets (C++, Java, C#). `haxe --interp` starts them at
	  null; other uninitialized statics start at null on both.
	- The caller renders the right operand in the destination representation
	  (for example `float_of_int` for an Int written to a Float); this module
	  only reads, combines, and stores. Compound and increment arithmetic reuse
	  the local-variable helpers (`Stage3OcamlLocalCompoundValue`,
	  `EmitterNumericUpdate`), so the old value is read before the right operand
	  runs, as for locals.

	Gotchas
	- Startup order is still the order of the `let` bindings in each module.
	  A static initializer that calls a same-class function which reads statics
	  is a separate ordering limit (haxe_ocaml-j6aof).
**/
class Stage3OcamlStaticStorage {
	/**
		Every cell binding starts with this prefix, so a parameter named like the
		static (`function setRatio(ratio:Float) Main.ratio = ratio;`) never shadows
		the cell. `Stage3OcamlLocalNames` renames the rare local whose own name
		starts with this prefix.
	**/
	public static inline final CELL_PREFIX = "__hx_static_";

	final byField:Map<String, StoredStatic> = [];
	final byDeclaration:Map<String, StoredStatic> = [];

	public function new() {}

	/**
		Whether Stage3 emits the declared static fields of output module `moduleName`.
		The Int64 and Vector providers keep their static members in the native runtime.
	**/
	public static function emitsDeclaredStatics(moduleName:String):Bool {
		if (StringTools.startsWith(moduleName, "Haxe_Int64"))
			return false;
		if (moduleName == "Haxe_ds_Vector")
			return false;
		return true;
	}

	/**
		Select the stored static fields of one class that this request generates into
		output module `module`.
	**/
	public function add(facts:TypedBackendClassSemanticFacts, runtimeProvided:Bool, module:String):Void {
		if (runtimeProvided
			|| facts.getIsExtern()
			|| facts.getIsInterface()
			|| !facts.getNominalKind().match(ClassInstance)
			|| !emitsDeclaredStatics(module))
			return;
		for (field in facts.copyFields()) {
			if (!field.isStatic || field.isFinal || field.isInline || !field.hasStorage)
				continue;
			final declaration = module + "." + field.name;
			if (byField.exists(field.canonicalIdentity) || byDeclaration.exists(declaration))
				throw "native static field storage registered twice: " + field.canonicalIdentity;
			final stored:StoredStatic = {
				key: facts.getClassIdentity() + "." + field.name,
				module: module,
				ident: CELL_PREFIX + field.name,
				type: field.semanticType,
				cell: cellFor(field.semanticType)
			};
			byField.set(field.canonicalIdentity, stored);
			byDeclaration.set(declaration, stored);
		}
	}

	/** How to render the initializer `value` of the static `name` in `module`, or null when it keeps an immutable `let`. */
	public function initializerOperand(module:String, name:String, value:HxExpr):Null<Stage3OcamlStaticOperand> {
		final stored = byDeclaration.get(module + "." + name);
		return stored == null ? null : operandFor(stored.type, "=", value);
	}

	/**
		Split `e` when it writes a typed static field: `=`, a compound operator, or
		`++`/`--`. Returns null for every other expression, including writes to locals
		and instance fields. `field` returns the exact typed field occurrence of the
		active body. A static without mutable storage throws a named error here.
	**/
	public function split(e:HxExpr, field:HxExpr->Null<TypedBackendFieldOccurrence>):Null<Stage3OcamlStaticWrite> {
		final parts:Null<{
			op:String,
			target:HxExpr,
			value:Null<HxExpr>,
			postfix:Bool
		}> = switch e {
			case EBinop(op, target, value) if (StringTools.endsWith(op, "=") && op != "==" && op != "!=" && op != "<=" && op != ">="):
				{
					op: op,
					target: target,
					value: value,
					postfix: false
				};
			case EUnop(op, fixity, target) if (op == HxUnaryOperator.Increment || op == HxUnaryOperator.Decrement):
				{
					op: op == HxUnaryOperator.Increment ? "++" : "--",
					target: target,
					value: null,
					postfix: fixity == HxUnaryFixity.Postfix
				};
			case _: null;
		};
		if (parts == null || !(parts.target.match(EIdent(_)) || parts.target.match(EField(_, _))))
			return null;
		final occurrence = field(parts.target);
		if (occurrence == null || !occurrence.getField().getIsStatic())
			return null;
		final type = requireWritable(occurrence);
		return {
			target: occurrence,
			op: parts.op,
			value: parts.value,
			postfix: parts.postfix,
			operand: parts.value == null ? Plain : operandFor(type, parts.op, parts.value)
		};
	}

	/** The occurrence when `e` reads a stored static field, for renderers that spell bare names directly. */
	public function storedRead(e:HxExpr, field:HxExpr->Null<TypedBackendFieldOccurrence>):Null<TypedBackendFieldOccurrence> {
		if (!(e.match(EIdent(_)) || e.match(EField(_, _))))
			return null;
		final occurrence = field(e);
		return occurrence != null && find(occurrence) != null ? occurrence : null;
	}

	/**
		The module-level binding for the stored static `name`, or null when it keeps an
		immutable `let`. `value` is the rendered initializer, or null when the field
		has none; an uninitialized field starts at the Haxe default of its type.
	**/
	public function declaration(module:String, name:String, value:Null<String>):Null<String> {
		final stored = byDeclaration.get(module + "." + name);
		if (stored == null)
			return null;
		return switch stored.cell {
			case Typed(ocamlType):
				"let "
				+ stored.ident
				+ " : "
				+ ocamlType
				+ " ref = ref ("
				+ (value == null ? typedDefault(ocamlType) : value)
				+ ")";
			case Erased:
				"let "
				+ stored.ident
				+ " : Obj.t ref = ref ("
				+ (value == null ? "HxRuntime.hx_null" : "Obj.repr (" + value + ")")
				+ ")";
		};
	}

	/** Read a stored static field, or return null when the occurrence names another field. */
	public function read(occurrence:TypedBackendFieldOccurrence, currentModule:String):Null<String> {
		final stored = find(occurrence);
		if (stored == null)
			return null;
		final field = occurrence.getField();
		if (field.getPropertyGet() == "get" && !occurrence.getHasPropertyStorageAccess())
			throw "native static field read requires lowered stored access: " + stored.key;
		final cell = reference(stored, currentModule);
		return switch stored.cell {
			case Typed(_): "(!" + cell + ")";
			case Erased: "(Obj.obj (!" + cell + "))";
		};
	}

	/**
		The declared type of the static field that a write targets. Throws a named
		error when the field has no mutable storage in this request, so the caller
		never falls back to a placeholder.
	**/
	function requireWritable(occurrence:TypedBackendFieldOccurrence):TyType {
		final field = occurrence.getField();
		final stored = find(occurrence);
		if (stored == null)
			throw "native static field write has no mutable storage: "
				+ field.getCanonicalKey()
				+ (field.getIsFinal() ? " is final" : " is not owned by a generated class");
		if (field.getPropertySet() == "set" && !occurrence.getHasPropertyStorageAccess())
			throw "native static field write through a property setter is not supported: " + stored.key;
		return stored.type;
	}

	/**
		Render one write from `split` as an OCaml expression with the value Haxe gives
		the write. `right` is the right operand rendered as `update.operand` asks (null
		for `++`/`--`), and `rightCarrier` names its nullable primitive carrier when it
		has one.
	**/
	public function write(update:Stage3OcamlStaticWrite, right:Null<String>, rightCarrier:Null<String>, currentModule:String,
			names:Null<Stage3OcamlLocalNames>):String {
		final stored = find(update.target);
		final cell = reference(stored, currentModule);
		if (names == null)
			throw "native static field write requires a local naming owner: " + stored.key;
		final carrier = Stage3OcamlNullablePrimitive.innerPrimitive(stored.type);
		if (update.op == "++" || update.op == "--") {
			// A typed cell holds the number itself; an erased cell holds a nullable number's carrier.
			final number = switch stored.cell {
				case Typed(ocamlType): ocamlType == "int" ? Stage3OcamlNullablePrimitive.INT : ocamlType == "float" ? Stage3OcamlNullablePrimitive.FLOAT : null;
				case Erased: carrier;
			};
			final kind = if (number == Stage3OcamlNullablePrimitive.INT) {
				EmitterNumericUpdate.EmitterNumericUpdateKind.IntStep;
			} else if (number == Stage3OcamlNullablePrimitive.FLOAT) {
				EmitterNumericUpdate.EmitterNumericUpdateKind.FloatStep;
			} else {
				throw unsupported(update.op, stored);
			};
			return EmitterNumericUpdate.local({
				ident: cell,
				kind: kind,
				increment: update.op == "++",
				postfix: update.postfix,
				carrier: stored.cell.match(Erased) ? carrier : null
			});
		}
		if (right == null)
			throw "native static field assignment requires its right operand: " + stored.key;
		if (update.op == "=") {
			final bound = names.internalName("__hx_static_value");
			final kept = switch stored.cell {
				case Typed(_): bound;
				case Erased: "Obj.repr " + bound;
			};
			return "(let " + bound + " = (" + right + ") in (" + cell + " := " + kept + "; " + bound + "))";
		}
		final kind = Stage3OcamlLocalCompoundValue.isArithmeticOperator(update.op) ? Stage3OcamlLocalCompoundValue.kindOf(stored.type) : null;
		// An erased cell holds the nullable carrier directly; any other erased type has no arithmetic form.
		if (kind == null || (stored.cell.match(Erased) && carrier == null))
			throw unsupported(update.op, stored);
		return Stage3OcamlLocalCompoundValue.value({
			ident: cell,
			op: update.op,
			kind: kind,
			carrier: stored.cell.match(Erased) ? carrier : null,
			old: "(!" + cell + ")",
			right: right,
			rightCarrier: kind == StringUpdate ? null : rightCarrier,
			names: names
		});
	}

	function find(occurrence:TypedBackendFieldOccurrence):Null<StoredStatic> {
		final field = occurrence.getField();
		if (!field.getIsStatic())
			return null;
		final stored = byField.get(field.getCanonicalKey());
		if (stored == null)
			return null;
		// A static is named by its bare name or a type path; Haxe has no value receiver for it.
		if (occurrence.getReceiver() == ValueReceiver)
			throw "native static field access through a value receiver is not supported: " + stored.key;
		return stored;
	}

	static function operandFor(type:TyType, op:String, value:HxExpr):Stage3OcamlStaticOperand {
		if (op != "=")
			return switch Stage3OcamlLocalCompoundValue.kindOf(type) {
				case StringUpdate: StringAppend;
				case FloatUpdate: FloatValue;
				case _: Plain;
			};
		final floating = TyAliasExpansion.reveal(type).getSemanticKey() == "primitive:Float"
			|| Stage3OcamlNullablePrimitive.numericInner(type) == Stage3OcamlNullablePrimitive.FLOAT;
		return floating && !value.match(ENull) ? FloatValue : Plain;
	}

	static function reference(stored:StoredStatic, currentModule:String):String {
		return stored.module == currentModule ? stored.ident : stored.module + "." + stored.ident;
	}

	static function cellFor(type:TyType):Stage3OcamlStaticCell {
		final revealed = TyAliasExpansion.reveal(type);
		if (revealed.isNullable())
			return Erased;
		return switch revealed.getSemanticKey() {
			case "primitive:Int": Typed("int");
			case "primitive:Float": Typed("float");
			case "primitive:Bool": Typed("bool");
			case "primitive:String": Typed("string");
			case _: Erased;
		};
	}

	/** Haxe's default value of an uninitialized static field of a static-target basic type. */
	static function typedDefault(ocamlType:String):String {
		return switch ocamlType {
			case "int": "0";
			case "float": "0.";
			case "bool": "false";
			case _: "(Obj.magic HxRuntime.hx_null : " + ocamlType + ")";
		};
	}

	static function unsupported(op:String, stored:StoredStatic):String {
		return "unsupported OCaml static field update: " + op + " on " + stored.type.getDisplay() + " (" + stored.key + ")";
	}
}
