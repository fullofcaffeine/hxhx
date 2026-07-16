/**
	Stable structural tags for typed expressions.

	Payloads live on `TypedExpr` itself. Keeping this enum payload-free lets the
	OCaml bootstrap target emit the recursively typed node as one record instead
	of creating a module or declaration cycle between a node and its kind.
**/
enum TypedExprTag {
	NullValue;
	BoolValue;
	StringValue;
	IntValue;
	FloatValue;
	EnumValue;
	ThisValue;
	SuperValue;
	LocalRead;
	NameRead;
	FieldRead;
	Call;
	MacroExpr;
	MacroType;
	Lambda;
	SwitchExpr;
	NewValue;
	Unary;
	Binary;
	Assign;
	CompoundAssign;
	Ternary;
	Anonymous;
	ArrayComprehension;
	ArrayDecl;
	ArrayAccess;
	Range;
	Cast;
	Untyped;
	Opaque;
	Block;
	Temporary;
}

/**
	One semantically typed expression node.

	Every child is stored structurally in `expressions`; no parsed expression can
	hide beneath a typed parent. Scalar payloads use dedicated fields selected by
	`tag`. Static factories are the only construction API so each shape has one
	canonical layout.

	`position` is null when the parser did not retain a position for this exact
	nested expression. Callers must not substitute a parent position and pretend
	it is precise. The semantic type is always present; unresolved bootstrap cases
	use `TyType.unknown()` explicitly.
**/
class TypedExpr {
	final tag:TypedExprTag;
	final type:TyType;
	final position:Null<HxPos>;
	final texts:Array<String>;
	final expressions:Array<TypedExpr>;
	final patterns:Array<HxSwitchPattern>;
	final boolValue:Bool;
	final intValue:Int;
	final floatValue:Float;
	final declaration:Null<TyDeclarationInfo>;
	final unaryOperator:Null<HxUnaryOperator>;
	final unaryFixity:Null<HxUnaryFixity>;
	final opaqueKind:Null<TypedOpaqueExprKind>;

	function new(tag:TypedExprTag, type:TyType, position:Null<HxPos>, ?texts:Array<String>, ?expressions:Array<TypedExpr>, ?patterns:Array<HxSwitchPattern>,
			boolValue:Bool = false, intValue:Int = 0, floatValue:Float = 0.0, ?declaration:TyDeclarationInfo, ?unaryOperator:HxUnaryOperator,
			?unaryFixity:HxUnaryFixity, ?opaqueKind:TypedOpaqueExprKind) {
		this.tag = tag;
		this.type = type == null ? TyType.unknown() : type;
		this.position = position;
		this.texts = texts == null ? [] : texts.copy();
		this.expressions = expressions == null ? [] : expressions.copy();
		this.patterns = patterns == null ? [] : patterns.copy();
		this.boolValue = boolValue;
		this.intValue = intValue;
		this.floatValue = floatValue;
		this.declaration = declaration;
		this.unaryOperator = unaryOperator;
		this.unaryFixity = unaryFixity;
		this.opaqueKind = opaqueKind;
	}

	public static function nullValue(type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(NullValue, type, position);

	public static function boolLiteral(value:Bool, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(BoolValue, type, position, null, null, null, value);

	public static function stringLiteral(value:String, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(StringValue, type, position, [value == null ? "" : value]);

	public static function intLiteral(value:Int, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(IntValue, type, position, null, null, null, false, value);

	public static function floatLiteral(value:Float, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(FloatValue, type, position, null, null, null, false, 0, value);

	public static function enumValue(name:String, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(EnumValue, type, position, [name]);

	public static function thisValue(type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(ThisValue, type, position);

	public static function superValue(type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(SuperValue, type, position);

	public static function localRead(name:String, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(LocalRead, type, position, [name]);

	public static function nameRead(name:String, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(NameRead, type, position, [name]);

	public static function fieldRead(object:TypedExpr, field:String, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(FieldRead, type, position, [field], [object]);

	public static function call(callee:TypedExpr, arguments:Array<TypedExpr>, declaration:Null<TyDeclarationInfo>, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(Call, type, position, null, [callee].concat(arguments == null ? [] : arguments), null, false, 0, 0.0, declaration);

	public static function macroExpr(expression:TypedExpr, wrappers:Array<String>, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(MacroExpr, type, position, wrappers, [expression]);

	public static function macroType(typeText:String, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(MacroType, type, position, [typeText]);

	public static function lambda(arguments:Array<String>, body:TypedExpr, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(Lambda, type, position, arguments, [body]);

	public static function switchExpr(scrutinee:TypedExpr, patterns:Array<HxSwitchPattern>, branches:Array<TypedExpr>, type:TyType,
			position:Null<HxPos>):TypedExpr
		return new TypedExpr(SwitchExpr, type, position, null, [scrutinee].concat(branches == null ? [] : branches), patterns);

	public static function newValue(typePath:String, arguments:Array<TypedExpr>, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(NewValue, type, position, [typePath], arguments);

	public static function unary(op:HxUnaryOperator, fixity:HxUnaryFixity, expression:TypedExpr, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(Unary, type, position, null, [expression], null, false, 0, 0.0, null, op, fixity);

	public static function binary(op:String, left:TypedExpr, right:TypedExpr, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(Binary, type, position, [op], [left, right]);

	public static function assign(target:TypedExpr, value:TypedExpr, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(Assign, type, position, null, [target, value]);

	public static function compoundAssign(op:String, target:TypedExpr, value:TypedExpr, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(CompoundAssign, type, position, [op], [target, value]);

	public static function ternary(condition:TypedExpr, whenTrue:TypedExpr, whenFalse:TypedExpr, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(Ternary, type, position, null, [condition, whenTrue, whenFalse]);

	public static function anonymous(fieldNames:Array<String>, fieldValues:Array<TypedExpr>, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(Anonymous, type, position, fieldNames, fieldValues);

	public static function arrayComprehension(name:String, iterable:TypedExpr, guard:Null<TypedExpr>, value:TypedExpr, type:TyType,
			position:Null<HxPos>):TypedExpr {
		final children = [iterable];
		if (guard != null)
			children.push(guard);
		children.push(value);
		return new TypedExpr(ArrayComprehension, type, position, [name], children, null, guard != null);
	}

	public static function arrayDecl(values:Array<TypedExpr>, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(ArrayDecl, type, position, null, values);

	public static function arrayAccess(array:TypedExpr, index:TypedExpr, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(ArrayAccess, type, position, null, [array, index]);

	public static function range(start:TypedExpr, end:TypedExpr, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(Range, type, position, null, [start, end]);

	public static function castValue(expression:TypedExpr, typeHint:String, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(Cast, type, position, [typeHint], [expression]);

	public static function untypedValue(expression:TypedExpr, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(Untyped, type, position, null, [expression]);

	public static function opaque(kind:TypedOpaqueExprKind, raw:String, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(Opaque, type, position, [raw], null, null, false, 0, 0.0, null, null, null, kind);

	/** Ordered expression sequence used by shared semantic lowering. **/
	public static function block(expressions:Array<TypedExpr>, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(Block, type, position, null, expressions);

	/** Compiler-owned temporary declaration; its source type hint remains representation input. **/
	public static function temporary(name:String, typeHint:String, initializer:TypedExpr, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(Temporary, type, position, [name, typeHint == null ? "" : typeHint], [initializer]);

	public function getTag():TypedExprTag
		return tag;

	public function getType():TyType
		return type;

	public function getPosition():Null<HxPos>
		return position;

	public function getTexts():Array<String>
		return texts.copy();

	public function getExpressions():Array<TypedExpr>
		return expressions.copy();

	public function getPatterns():Array<HxSwitchPattern>
		return patterns.copy();

	public function getBoolValue():Bool
		return boolValue;

	public function getIntValue():Int
		return intValue;

	public function getFloatValue():Float
		return floatValue;

	public function getDeclaration():Null<TyDeclarationInfo>
		return declaration;

	public function getUnaryOperator():Null<HxUnaryOperator>
		return unaryOperator;

	public function getUnaryFixity():Null<HxUnaryFixity>
		return unaryFixity;

	public function getOpaqueKind():Null<TypedOpaqueExprKind>
		return opaqueKind;

	/** Rebuild this immutable node with new children while preserving its exact semantic payload. **/
	public function withExpressions(children:Array<TypedExpr>):TypedExpr
		return new TypedExpr(tag, type, position, texts, children, patterns, boolValue, intValue, floatValue, declaration, unaryOperator, unaryFixity,
			opaqueKind);

	/** Re-label one structurally identical expression for a shared semantic view such as abstract `this`. **/
	public function withType(semanticType:TyType):TypedExpr
		return new TypedExpr(tag, semanticType, position, texts, expressions, patterns, boolValue, intValue, floatValue, declaration, unaryOperator,
			unaryFixity, opaqueKind);
}
