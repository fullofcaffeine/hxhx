import haxe.ds.StringMap;
import TyFieldConstant.TyFieldConstantKind;

/**
	Resolve enum-abstract values after shared typing knows the backing type.
	Declaration order supplies omitted Int values; omitted String values use the
	field name. Resolution retains unresolved evidence for unsupported expressions
	and cycles, so a backend cannot silently emit an invented value.
**/
class TyEnumAbstractConstants {
	final owner:TyNominalTypeId;
	final underlying:TyType;
	final declarations = new StringMap<HxFieldDecl>();
	final previous = new StringMap<String>();
	final resolved = new StringMap<TyFieldConstant>();
	final active = new StringMap<Bool>();

	public function new(owner:TyNominalTypeId, underlying:TyType, fields:Array<HxFieldDecl>) {
		this.owner = owner;
		this.underlying = underlying;
		var prior:Null<String> = null;
		for (field in fields) {
			if (HxFieldDecl.getMetadata(field).indexOf("__hxhx_enum_abstract_value") < 0)
				continue;
			final name = HxFieldDecl.getName(field);
			if (declarations.exists(name))
				throw "duplicate enum-abstract value " + owner.getCanonicalName() + "." + name;
			declarations.set(name, field);
			if (prior != null)
				previous.set(name, prior);
			prior = name;
		}
	}

	function unresolved(name:String, reason:String):TyFieldConstant
		return new TyFieldConstant(Unresolved(owner.getCanonicalName() + "." + name + ": " + reason));

	/** Resolve lazily so declaration references and omitted successors share one result. */
	public function resolve(name:String):TyFieldConstant {
		final cached = resolved.get(name);
		if (cached != null)
			return cached;
		final field = declarations.get(name);
		if (field == null)
			return unresolved(name, "constant declaration is not available");
		if (active.exists(name))
			return unresolved(name, "cyclic constant initializer");
		active.set(name, true);
		final initializer = HxFieldDecl.getInit(field);
		final value = if (initializer != null) {
			evaluate(name, initializer);
		} else if (HxFieldDecl.getInitText(field).length > 0) {
			unresolved(name, "initializer could not be parsed");
		} else {
			switch (underlying.getSemanticKey()) {
				case "primitive:String": new TyFieldConstant(StringValue(name));
				case "primitive:Int":
					final prior = previous.get(name);
					if (prior == null) new TyFieldConstant(IntValue(0)) else switch (resolve(prior).getKind()) {
						case IntValue(value): new TyFieldConstant(IntValue(value + 1));
						case _: unresolved(name, "preceding Int constant is unresolved");
					}
				case _: unresolved(name, "implicit value requires String or Int backing type");
			}
		};
		final checked = switch ([underlying.getSemanticKey(), value.getKind()]) {
			case ["primitive:String", StringValue(_)] | ["primitive:Int", IntValue(_)] | ["primitive:Bool", BoolValue(_)]: value;
			case [_, Unresolved(_)]: value;
			case _: unresolved(name, "initializer does not match the supported backing type " + underlying.getCanonicalDisplay());
		};
		active.remove(name);
		resolved.set(name, checked);
		return checked;
	}

	/** Evaluate literal and same-enum reference expressions without executing source code. */
	function evaluate(name:String, expression:HxExpr):TyFieldConstant {
		return switch (expression) {
			case EInt(value): new TyFieldConstant(IntValue(value));
			case EString(value): new TyFieldConstant(StringValue(value));
			case EBool(value): new TyFieldConstant(BoolValue(value));
			case EIdent(reference): resolve(reference);
			case EUnop(Negate, Prefix, inner):
				switch (evaluate(name, inner).getKind()) {
					case IntValue(value): new TyFieldConstant(IntValue(-value));
					case _: unresolved(name, "integer negation requires a resolved Int constant");
				}
			case _: unresolved(name, "constant expression requires shared evaluation support");
		};
	}
}
