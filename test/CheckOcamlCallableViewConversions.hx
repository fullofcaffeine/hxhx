#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.callableShape;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.crossing;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.shape as genericShape;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.shapeId;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueShape;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.describe;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.typeExpr;
#end

/** Checks ordinary callback conversion direction on the retained, upstream-typed source fixture. */
class CheckOcamlCallableViewConversions {
	/** Supplies an origin only after its actual typed producer is retained in a local write plan. */
	public static macro function selectedProducer(localName:String):haxe.macro.Expr {
		final owner = switch (Context.getType("Main")) {
			case TInst(reference, []): reference.get();
			case _: throw "missing stored callback fixture";
		};
		final body = owner.statics.get().filter(field -> field.name == "main")[0].expr();
		if (body == null)
			throw "missing stored callback body";
		return Context.makeExpr(CheckOcamlCallableLocalPlan.selectOrigin(body, localName), Context.currentPos());
	}

	/** Identity selection uses the fixture's typed initializer, independently of its carrier. */
	public static macro function selectedOrigin(localName:String):haxe.macro.Expr {
		final owner = switch (Context.getType("Main")) {
			case TInst(reference, []): reference.get();
			case _: throw "missing stored callback fixture";
		};
		final body = owner.statics.get().filter(field -> field.name == "main")[0].expr();
		var selected:Null<reflaxe.ocaml.lowered.OcamlCallableOriginKind> = null;
		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TVar(local, value) if (local.name == localName && value != null):
					selected = reflaxe.ocaml.lowered.OcamlCallableOrigin.classify(value);
				case _:
			}
			TypedExprTools.iter(expression, visit);
		}
		if (body != null)
			visit(body);
		if (selected == null)
			throw "fixture initializer is not an admitted callback origin: " + localName;
		return Context.makeExpr(selected, Context.currentPos());
	}

	/** Native annotations come from a registered signature rather than a test-written arrow type. */
	public static macro function selectedCarrier(localName:String):haxe.macro.Expr {
		final owner = switch (Context.getType("Main")) {
			case TInst(reference, []): reference.get();
			case _: throw "missing stored callback fixture";
		};
		final body = owner.statics.get().filter(field -> field.name == "main")[0].expr();
		var selected:Null<reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueShape> = null;
		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TVar(local, _) if (local.name == localName):
					selected = callableShape(local.t);
				case _:
			}
			TypedExprTools.iter(expression, visit);
		}
		if (body != null)
			visit(body);
		if (selected == null)
			throw "fixture callback signature was not selected";
		final registry = new OcamlRepresentationRegistry();
		registry.beginProgram("callable-view-fixture");
		final decision = registry.selectCallableView(selected, InternalValue);
		final descriptor = registry.requireCallableView(decision.id, decision.revision, "callable-view-fixture");
		return Context.makeExpr(typeExpr(descriptor), Context.currentPos());
	}

	/** Supplies a source-bound local plan's conversion to the native syntax test. */
	public static macro function selectedView(localName:String):haxe.macro.Expr {
		final owner = switch (Context.getType("Main")) {
			case TInst(reference, []): reference.get();
			case _: throw "missing stored callback fixture";
		};
		final body = owner.statics.get().filter(field -> field.name == "main")[0].expr();
		if (body == null)
			throw "missing stored callback body";
		return Context.makeExpr(CheckOcamlCallableLocalPlan.select(body, localName), Context.currentPos());
	}

	#if macro
	public static function install():Void {
		Context.getType("Main");
		Context.onAfterTyping(_ -> verify());
	}

	static function verify():Void {
		final owner = switch (Context.getType("Main")) {
			case TInst(reference, []): reference.get();
			case _: throw "missing stored callback fixture";
		};
		final main = owner.statics.get().filter(field -> field.name == "main")[0].expr();
		if (main == null)
			throw "missing stored callback body";
		final expected:Map<String, String> = [
			"source" => "Identity",
			"first" => "AdaptFunction([BoxValue],Identity)",
			"second" => "AdaptFunction([BoxValue],Identity)",
			"alias" => "Identity",
			"higherSource" => "Identity",
			"higherView" => "AdaptFunction([AdaptFunction([UnboxValue],BoxValue)],AdaptFunction([BoxValue],UnboxValue))"
		];
		var count = 0;
		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TVar(local, value) if (value != null && expected.exists(local.name)):
					final source = callableShape(value.t);
					final destination = callableShape(local.t);
					if (source == null || destination == null || Std.string(crossing(source, destination)) != expected.get(local.name))
						throw "wrong callable storage conversion for " + local.name;
					count++;
				case _:
			}
			TypedExprTools.iter(expression, visit);
		}
		visit(main);
		if (count != 6)
			throw "stored callback conversion coverage changed";

		final dynamicType = Context.resolveType(macro :Dynamic, Context.currentPos());
		final dynamicShape = callableShape(dynamicType);
		if (dynamicShape == null || shapeId(dynamicShape) != "Dynamic" || genericShape(dynamicType) != null)
			throw "ordinary Dynamic changed generic declaration admission";
		for (unsupported in [
			Context.makeMonomorph(),
			Context.resolveType(macro :Dynamic<Int>, Context.currentPos()),
			Context.resolveType(macro :(?value:Int) -> Int, Context.currentPos()),
			Context.resolveType(macro :Null<Int->Int>, Context.currentPos()),
			Context.resolveType(macro :Array<Dynamic>, Context.currentPos())
		])
			if (callableShape(unsupported) != null)
				throw "unproved callable storage acquired a representation";
		final unresolvedCallback:Type = TFun([{name: "value", opt: false, t: Context.makeMonomorph()}], dynamicType);
		if (callableShape(unresolvedCallback) != null)
			throw "unresolved callback input was replaced with Dynamic";
		checkConversion(macro :Dynamic->Dynamic, macro :Int->Dynamic, "AdaptFunction([BoxValue],Identity)");
		checkConversion(macro :Int->Int, macro :Dynamic->Dynamic, "AdaptFunction([UnboxValue],BoxValue)");
		checkConversion(macro :Dynamic->Dynamic, macro :Bool->Bool, "AdaptFunction([BoxBoolean],UnboxBoolean)");
		checkConversion(macro :Dynamic->Dynamic, macro :Null<Bool>->Null<Bool>, "AdaptFunction([BoxNullableBoolean],UnboxNullableBoolean)");
		checkConversion(macro :Int->Int, macro :String->Int, "null");
		checkConversion(macro :Int->Int, macro :Int->Int->Int, "null");
		checkRegistry();
		CheckOcamlCallableOrigins.verify(main);
		Sys.println("OCAML_CALLABLE_VIEW_CONVERSION:PASS");
	}

	/** Program reset and copied signature mutation must not change a registered callback layout. */
	static function checkRegistry():Void {
		final shape = callableShape(Context.resolveType(macro :Dynamic->Dynamic, Context.currentPos()));
		if (shape == null)
			throw "missing callback signature";
		final registry = new OcamlRepresentationRegistry();
		expectRejected(() -> registry.selectCallableView(shape, InternalValue));
		registry.beginProgram("callable-view-fixture");
		final decision = registry.selectCallableView(shape, InternalValue);
		final descriptor = registry.requireCallableView(decision.id, decision.revision, "callable-view-fixture");
		if (descriptor.semanticTypeId != "(Dynamic)->Dynamic")
			throw "callback representation changed its source signature";
		switch (descriptor.shape) {
			case FunctionValue(arguments, _):
				arguments[0] = Integer;
			case _:
				throw "callback descriptor lost its function shape";
		}
		expectRejected(() -> typeExpr(descriptor));
		if (registry.requireCallableView(decision.id, decision.revision, "callable-view-fixture").semanticTypeId != "(Dynamic)->Dynamic")
			throw "a detached descriptor changed registry-owned storage";
		// The caller also retains its input array after selection. Mutating it
		// must not rewrite the registry's private signature.
		switch (shape) {
			case FunctionValue(arguments, _):
				arguments[0] = Integer;
			case _:
				throw "callback input lost its function shape";
		}
		if (registry.requireCallableView(decision.id, decision.revision, "callable-view-fixture").semanticTypeId != "(Dynamic)->Dynamic")
			throw "a caller-owned signature changed registry-owned storage";
		for (domain in [MutableLocalStorage, CapturedLocalStorage]) {
			final stored = registry.selectCallableView(shape, domain);
			if (stored.storageMutationPolicy != SharedLocalCell)
				throw "mutable callback storage lost its shared local cell";
			if (registry.requireCallableView(stored.id, stored.revision, "callable-view-fixture").semanticTypeId != "(Int)->Dynamic")
				throw "mutable callback storage changed its invocation signature";
		}
		expectRejected(() -> registry.requireCallableView(decision.id, "changed", "callable-view-fixture"));
		expectRejected(() -> registry.requireCallableView(decision.id, decision.revision, "other-program"));
		expectRejected(() -> registry.selectCallableView(shape, InstanceField));
		expectRejected(() -> registry.selectCallableView(shape, ArrayElement));
		for (unsupported in [
			FunctionValue([EffectOnly], Integer),
			FunctionValue([Erased("foreign|T")], Integer),
			FunctionValue([ArrayValue(Integer)], Integer)
		])
			expectRejected(() -> describe(unsupported));
		registry.beginProgram("next-program");
		expectRejected(() -> registry.requireCallableView(decision.id, decision.revision, "callable-view-fixture"));
		expectRejected(() -> registry.requireCallableView(decision.id, decision.revision, "next-program"));
		Sys.println("OCAML_CALLABLE_VIEW_REPRESENTATION:PASS");
	}

	static function expectRejected(action:Void->Void):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf("reflaxe.ocaml [ocaml-") == 0)
				return;
			throw error;
		}
		throw "unproved callback representation was accepted";
	}

	/** Function arguments reverse direction while the result keeps source-to-destination direction. */
	static function checkConversion(source:haxe.macro.Expr.ComplexType, destination:haxe.macro.Expr.ComplexType, expected:String):Void {
		final from = callableShape(Context.resolveType(source, Context.currentPos()));
		final to = callableShape(Context.resolveType(destination, Context.currentPos()));
		if (from == null || to == null || Std.string(crossing(from, to)) != expected)
			throw "wrong callback conversion direction: " + expected;
	}
	#end
}
