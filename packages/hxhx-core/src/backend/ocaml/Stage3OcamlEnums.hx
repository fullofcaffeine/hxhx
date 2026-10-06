package backend.ocaml;

import backend.ocaml.Stage3OcamlEnumPlan.Stage3OcamlEnumConstructor;
import TypedExactEnumConstructorSource.TypedExactEnumConstructorCall;

/**
	Emits ordinary enum values using the variants understood by HxEnum and HxType.

	Each compiler request supplies its exact typed declarations. Constructor calls
	select those declarations by identity; source qualifiers do not select runtime
	owners. Haxe constructor indexes retain declaration order, while OCaml numbers
	singletons and payload constructors separately.

	The native payload contract covers Int, Bool, String, and boxed ordinary enums. Other payload
	representations fail explicitly until their typed conversion is implemented.
**/
class Stage3OcamlEnums {
	final owners:Map<String, Stage3OcamlEnumPlan> = new Map();
	final byDeclaration:Map<HxClassDecl, Stage3OcamlEnumPlan> = new Map();
	final valueName:String->String;
	final quote:String->String;
	var nextCall:Int = 0;

	public function new(valueName:String->String, quote:String->String) {
		this.valueName = valueName;
		this.quote = quote;
	}

	/** Register only declarations whose parser and semantic enum identities agree. */
	public function add(projection:TypedBackendClassProjection, outputModule:String, packagePath:String):Void {
		final plan = Stage3OcamlEnumPlan.fromProjection(projection, outputModule, packagePath, valueName);
		if (plan == null)
			return;
		if (owners.exists(plan.owner))
			throw "OCaml enum owner registered twice: " + plan.owner;
		for (other in owners)
			if (other.runtimeName == plan.runtimeName || other.outputModule == plan.outputModule)
				throw "OCaml enum runtime or module name collision: " + plan.owner;
		owners.set(plan.owner, plan);
		byDeclaration.set(projection.getDeclaration(), plan);
	}

	/** Validate after all owners are registered so recursive enum payloads resolve exactly. */
	public function validate():Void {
		for (owner in owners)
			for (constructor in owner.constructors)
				payloadTypes(constructor);
	}

	/** Reject erased or unmodeled payloads instead of claiming a native variant exists. */
	function payloadTypes(constructor:Stage3OcamlEnumConstructor):Array<String> {
		return [
			for (payload in constructor.payloads)
				switch (payload) {
					case NativeInt:
						"int";
					case NativeBool:
						"bool";
					case NativeString:
						"string";
					case EnumBox(identity):
						if (!owners.exists(identity))
							throw "OCaml enum payload representation is not implemented: " + constructor.declaration + " / " + identity;
						"Obj.t";
				}
		];
	}

	/** Produce one enum module; ordinary classes continue through their own emitter. */
	public function render(projection:TypedBackendClassProjection):Null<String> {
		if (HxClassDecl.getEnumDeclaration(projection.getDeclaration()) == null)
			return null;
		final owner = byDeclaration.get(projection.getDeclaration());
		if (owner == null)
			throw "OCaml enum module is missing its request-owned declaration";
		final out = ["(* Generated from the exact typed enum declaration. *)", "type t ="];
		if (owner.constructors.length == 0)
			out.push("  |");
		for (constructor in owner.constructors) {
			final types = payloadTypes(constructor);
			out.push("  | Constructor_" + constructor.index + (types.length == 0 ? "" : " of " + types.join(" * ")));
		}
		var immediateTag = 0;
		var blockTag = 0;
		for (constructor in owner.constructors) {
			final types = payloadTypes(constructor);
			final args = [for (index in 0...types.length) "arg" + index];
			final parameters = [for (index in 0...types.length) "(" + args[index] + " : " + types[index] + ")"];
			final payload = args.copy();
			// Keep each payload construction fresh, including all-constant arguments.
			if (payload.length > 0)
				payload[0] = "Stdlib.Sys.opaque_identity " + payload[0];
			final variant = "Constructor_" + constructor.index + (payload.length == 0 ? "" : " (" + payload.join(", ") + ")");
			out.push("let " + constructor.targetName + " " + parameters.join(" ") + " : Obj.t = HxEnum.box_if_needed " + quote(owner.runtimeName)
				+ " (Obj.repr (" + variant + "))");
			final layout = types.length == 0 ? "HxType.EnumImmediate " + immediateTag++ : "HxType.EnumBlock " + blockTag++;
			out.push("let () = HxType.register_enum_ctor_layout " + quote(owner.runtimeName) + " " + quote(constructor.name) + " " + constructor.index
				+ " (" + layout + ")");
		}
		out.push("let () = ignore (HxType.enum_ " + quote(owner.runtimeName) + ")");
		return out.join("\n") + "\n";
	}

	/**
		Validate the selected constructor, then evaluate its arguments once in Haxe
		order. Nested lets avoid depending on OCaml's argument evaluation order.
	**/
	public function call(selected:TypedExactEnumConstructorCall, emit:HxExpr->String, names:Stage3OcamlLocalNames):String {
		final owner = owners.get(selected.owner);
		if (owner == null || owner.moduleIdentity != selected.modulePath)
			throw "OCaml enum call has no exact program owner: " + selected.owner;
		for (constructor in owner.constructors) {
			if (constructor.name != selected.constructor)
				continue;
			if (constructor.payloads.length == 0)
				throw "OCaml enum call selected a singleton field";
			if (constructor.declaration != selected.declaration || constructor.payloads.length != selected.arguments.length)
				throw "OCaml enum call disagrees with its exact constructor declaration";
			final callId = nextCall++;
			final args = [
				for (index in 0...selected.arguments.length)
					names.internalName("__hx_enum_arg_" + callId + "_" + index)
			];
			final bindings = [
				for (index in 0...args.length)
					"let " + args[index] + " = (" + emit(selected.arguments[index]) + ") in "
			];
			return "(" + bindings.join("") + owner.outputModule + "." + constructor.targetName + " " + args.join(" ") + ")";
		}
		throw "OCaml enum call selected an absent constructor: " + selected.constructor;
	}
}
