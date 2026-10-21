import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.ocaml.ast.OcamlDeclarationSignature.OcamlDeclarationSignature;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.lowered.OcamlMethodDispatchSignature;
import reflaxe.ocaml.lowered.OcamlMethodDispatchSignature.selectMethodSignature;
import reflaxe.ocaml.lowered.OcamlMethodDispatchSignature.requireMethodSignature;
import reflaxe.ocaml.lowered.OcamlMethodDispatchSignature.requireMethodNativeSignature;
import reflaxe.ocaml.lowered.OcamlMethodViewConversionPlan;

/** Checks method-view admission and signature identity before native generation. */
class CheckSignatures {
	public static function run():Void {
		final declarations:Map<String, ClassType> = [];
		for (type in Context.getModule("SignatureCases"))
			switch (type) {
				case TInst(reference, _):
					declarations.set(reference.get().name, reference.get());
				case _:
			}
		function field(owner:String, name:String):ClassField {
			for (field in declarations.get(owner).fields.get())
				if (field.name == name)
					return field;
			throw "missing signature fixture " + owner + "." + name;
		}
		function select(owner:String, name:String, parameters:Array<OcamlTypeExpr>, result:OcamlTypeExpr,
				module:String = "Fixture"):Null<OcamlMethodDispatchSignature> {
			return selectMethodSignature(field(owner, name), {parameters: parameters, result: result}, module);
		}
		function require(condition:Bool, message:String):Void {
			if (!condition)
				Context.fatalError(message, Context.currentPos());
		}
		require(OcamlMethodViewConversionPlan.methodFields(Context.getType("SignatureCases.ClosedView")) != null, "closed ordinary method view was rejected");
		for (name in ["IteratorView", "IterableView", "PairIteratorView"])
			require(OcamlMethodViewConversionPlan.methodFields(Context.getType("SignatureCases." + name)) == null,
				"specialized iterator view was intercepted: " + name);
		final first = select("First", "convert", [TIdent("int")], TIdent("string"));
		final second = select("Second", "convert", [TIdent("int")], TIdent("string"));
		require(first != null && second != null, "closed signatures were rejected");
		requireMethodSignature(first);
		requireMethodSignature(second);
		require(first.key == second.key, "aliases or parameter names changed the key");
		requireMethodNativeSignature(first, {parameters: [TIdent("int")], result: TIdent("string")}, "Fixture");
		final changedSignatures:Array<OcamlDeclarationSignature> = [
			{parameters: [TIdent("bool")], result: TIdent("string")},
			{parameters: [TIdent("int")], result: TIdent("Obj.t")},
			{parameters: [], result: TIdent("string")}
		];
		for (changed in changedSignatures) {
			var rejectedNative = false;
			try {
				requireMethodNativeSignature(first, changed, "Fixture");
			} catch (_:String) {
				rejectedNative = true;
			}
			require(rejectedNative, "changed native implementation retained its signature key");
		}
		final boolMethod = select("Different", "convert", [TIdent("bool")], TIdent("string"));
		require(boolMethod != null && boolMethod.key != first.key, "different argument type shared a key");
		final sameCarrier = select("Different", "convert", [TIdent("int")], TIdent("string"));
		require(sameCarrier != null && sameCarrier.key != first.key, "source type identity was discarded when native carriers matched");
		final renamed = select("Different", "renamed", [TIdent("int")], TIdent("string"));
		require(renamed != null && renamed.key != first.key, "different method name shared a key");
		final changedCarrier = select("First", "convert", [TIdent("int")], TIdent("Obj.t"));
		require(changedCarrier != null && changedCarrier.key != first.key, "different native result shared a key");
		require(select("First", "convert", [], TIdent("string")) == null, "wrong native arity was accepted");
		require(select("Different", "optional", [TIdent("Obj.t")], TIdent("string")) == null, "optional method was admitted");
		require(select("Different", "generic", [TIdent("Obj.t")], TIdent("Obj.t")) == null, "generic method was admitted");
		require(select("Different", "unresolved", [TIdent("Obj.t")], TIdent("string")) == null, "Dynamic method was admitted");
		final local = select("Nominal", "payload", [], TIdent("t"), "Payload");
		final qualified = select("Nominal", "payload", [], TIdent("Payload.t"), "Caller");
		require(local != null && qualified != null && local.key == qualified.key, "local and qualified native names differ");
		first.parameterCarriers[0] = "named:bool";
		var rejected = false;
		try {
			requireMethodSignature(first);
		} catch (_:String) {
			rejected = true;
		}
		require(rejected, "changed detached signature retained lookup permission");
		Sys.println("METHOD_DISPATCH_SIGNATURE:PASS");
	}
}
