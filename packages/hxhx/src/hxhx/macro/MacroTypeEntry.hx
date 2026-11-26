package hxhx.macro;

/** What one type handle names (`MacroTypeHandles`). */
enum MacroTypeEntry {
	/** A class, interface, enum, or abstract of the request's index. */
	Nominal(info:TyNominalInfo);

	/** `Int`, `Float`, `Bool`, `Void` (abstracts of `StdTypes`), or `String`; `info` when the index has it. */
	Primitive(name:String, info:Null<TyNominalInfo>);

	/** `StdTypes`' `Null<T>`. */
	NullAbstract(info:Null<TyNominalInfo>);

	Alias(definition:TyAliasDefinition);
	Anonymous(type:TyType);
	Mono(type:TyType);
	TypeParameter(type:TyType);

	/** The member (`statics` false) or static fields of a class; none for a type parameter. */
	Fields(info:Null<TyNominalInfo>, statics:Bool);
}
