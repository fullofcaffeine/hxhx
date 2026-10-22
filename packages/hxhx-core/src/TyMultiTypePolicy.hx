/** One declared specialization parameter and its explicit abstract-following policy. */
typedef TyMultiTypeParameter = {
	final parameter:TyTypeParameterId;
	final followAbstracts:Bool;
};

/** Resolve multi-type metadata against its declaring binders once, before target selection. */
class TyMultiTypePolicy {
	final parameters:Array<TyMultiTypeParameter>;

	function new(parameters:Array<TyMultiTypeParameter>) {
		this.parameters = parameters.copy();
	}

	public function getParameters():Array<TyMultiTypeParameter>
		return parameters.copy();

	/** Unrelated annotations remain opaque; metadata expressions use the ordinary Haxe parser. */
	public static function fromMetadata(metadata:Array<String>, binders:Array<TyTypeParameterId>):Null<TyMultiTypePolicy> {
		for (entry in metadata) {
			var text = StringTools.trim(entry);
			while (StringTools.startsWith(text, "@") || StringTools.startsWith(text, ":"))
				text = text.substr(1);
			final open = text.indexOf("(");
			if (StringTools.trim(open < 0 ? text : text.substr(0, open)) != "multiType")
				continue;
			final expressions = switch HxParser.parseCompleteExprText(text) {
				case EIdent("multiType"): [for (binder in binders) HxExpr.EIdent(binder.getName())];
				case ECall(EIdent("multiType"), arguments): arguments;
				case _: throw "multi-type metadata requires its parameter list";
			};
			final selected = new Array<TyMultiTypeParameter>();
			for (expression in expressions) {
				final parameter = switch expression {
					case EIdent(name) | EEnumValue(name): {name: name, follow: false};
					case ECall(EIdent("__hxhx_expr_meta"),
						[EString("followWithAbstracts"), EString(""), (EIdent(name) | EEnumValue(name))]): {name: name, follow: true};
					case _: throw "unsupported multi-type parameter metadata";
				};
				for (binder in binders)
					if (binder.getName() == parameter.name)
						selected.push({parameter: binder, followAbstracts: parameter.follow});
			}
			return new TyMultiTypePolicy(selected);
		}
		return null;
	}
}
