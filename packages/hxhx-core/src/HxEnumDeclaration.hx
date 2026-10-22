/** Source constructor order and arity, independent of any generated field or record shape. */
typedef HxEnumConstructorDeclaration = {
	final name:String;
	final arity:Int;
};

/**
	Retain the parser's enum declaration when adapters expose class-shaped members.
	An ordinary class cannot become an enum by declaring a reserved-looking field.
	Copies prevent consumers from changing constructor order after parsing.
 */
class HxEnumDeclaration {
	final constructors:Array<HxEnumConstructorDeclaration>;
	final identity:String;

	public function new(constructors:Array<HxEnumConstructorDeclaration>) {
		if (constructors == null)
			throw "enum declaration requires its constructor inventory";
		this.constructors = [];
		final seen = new haxe.ds.StringMap<Bool>();
		final parts = ["parsed-enum-declaration-v1"];
		for (constructor in constructors) {
			if (constructor == null || constructor.name == null || constructor.name.length == 0 || constructor.arity < 0 || seen.exists(constructor.name))
				throw "enum declaration requires unique names and nonnegative constructor arities";
			seen.set(constructor.name, true);
			this.constructors.push({name: constructor.name, arity: constructor.arity});
			parts.push(constructor.name);
			parts.push(Std.string(constructor.arity));
		}
		identity = CompilerCacheIdentity.encode(parts);
	}

	public function getConstructors():Array<HxEnumConstructorDeclaration>
		return [
			for (constructor in constructors)
				{name: constructor.name, arity: constructor.arity}
		];

	public function getCanonicalIdentity():String
		return identity;
}
