/**
	Stable structural tags for typed statements.

	Payloads live on the self-recursive `TypedStmt` record. This avoids separate
	OCaml modules for mutually recursive statement kinds and catch branches.
**/
enum TypedStmtTag {
	Block;
	Var;
	If;
	ForIn;
	ForKeyValue;
	While;
	DoWhile;
	Switch;
	Try;
	Break;
	Continue;
	Throw;
	ReturnVoid;
	Return;
	Expression;
}

/**
	One structurally typed statement with the best exact source position.

	Expressions and nested statements are always structural typed nodes. Catch
	information is stored in parallel immutable arrays whose lengths are validated
	at construction. Local-variable metadata has its own immutable array so
	annotations such as `@:nullSafety(Off)` cannot be confused with names or type
	hints.
**/
class TypedStmt {
	final tag:TypedStmtTag;
	final position:Null<HxPos>;
	final names:Array<String>;
	final expressions:Array<TypedExpr>;
	final statements:Array<TypedStmt>;
	final patterns:Array<HxSwitchPattern>;
	final catchNames:Array<String>;
	final catchTypeHints:Array<String>;
	final metadata:Array<String>;
	final localBindings:Array<TyLocalBinding>;

	function new(tag:TypedStmtTag, position:Null<HxPos>, ?names:Array<String>, ?expressions:Array<TypedExpr>, ?statements:Array<TypedStmt>,
			?patterns:Array<HxSwitchPattern>, ?catchNames:Array<String>, ?catchTypeHints:Array<String>, ?metadata:Array<String>,
			?localBindings:Array<TyLocalBinding>) {
		this.tag = tag;
		this.position = position;
		this.names = names == null ? [] : names.copy();
		this.expressions = expressions == null ? [] : expressions.copy();
		this.statements = statements == null ? [] : statements.copy();
		this.patterns = patterns == null ? [] : patterns.copy();
		this.catchNames = catchNames == null ? [] : catchNames.copy();
		this.catchTypeHints = catchTypeHints == null ? [] : catchTypeHints.copy();
		this.metadata = metadata == null ? [] : metadata.copy();
		this.localBindings = localBindings == null ? [] : localBindings.copy();
		if (tag == Try && (this.statements.length != this.catchNames.length + 1 || this.catchNames.length != this.catchTypeHints.length))
			throw "typed try statement has inconsistent catch payloads";
	}

	public static function block(statements:Array<TypedStmt>, position:Null<HxPos>):TypedStmt
		return new TypedStmt(Block, position, null, null, statements);

	public static function variable(name:String, typeHint:String, initializer:Null<TypedExpr>, position:Null<HxPos>, ?metadata:Array<String>,
			?binding:TyLocalBinding):TypedStmt
		return new TypedStmt(Var, position, [name, typeHint], initializer == null ? [] : [initializer], null, null, null, null, metadata,
			binding == null ? [] : [binding]);

	public static function ifStmt(condition:TypedExpr, whenTrue:TypedStmt, whenFalse:Null<TypedStmt>, position:Null<HxPos>):TypedStmt {
		final branches = [whenTrue];
		if (whenFalse != null)
			branches.push(whenFalse);
		return new TypedStmt(If, position, null, [condition], branches);
	}

	public static function forIn(name:String, iterable:TypedExpr, body:TypedStmt, position:Null<HxPos>, ?binding:TyLocalBinding):TypedStmt
		return new TypedStmt(ForIn, position, [name], [iterable], [body], null, null, null, null, binding == null ? [] : [binding]);

	public static function forKeyValue(keyName:String, valueName:String, iterable:TypedExpr, body:TypedStmt, position:Null<HxPos>,
			?bindings:Array<TyLocalBinding>):TypedStmt
		return new TypedStmt(ForKeyValue, position, [keyName, valueName], [iterable], [body], null, null, null, null, bindings);

	public static function whileStmt(condition:TypedExpr, body:TypedStmt, position:Null<HxPos>):TypedStmt
		return new TypedStmt(While, position, null, [condition], [body]);

	public static function doWhile(body:TypedStmt, condition:TypedExpr, position:Null<HxPos>):TypedStmt
		return new TypedStmt(DoWhile, position, null, [condition], [body]);

	public static function switchStmt(scrutinee:TypedExpr, patterns:Array<HxSwitchPattern>, bodies:Array<TypedStmt>, position:Null<HxPos>,
			?bindings:Array<TyLocalBinding>):TypedStmt
		return new TypedStmt(Switch, position, null, [scrutinee], bodies, patterns, null, null, null, bindings);

	public static function tryStmt(body:TypedStmt, catchNames:Array<String>, catchTypeHints:Array<String>, catchBodies:Array<TypedStmt>, position:Null<HxPos>,
			?bindings:Array<TyLocalBinding>):TypedStmt
		return new TypedStmt(Try, position, null, null, [body].concat(catchBodies == null ? [] : catchBodies), null, catchNames, catchTypeHints, null,
			bindings);

	public static function breakStmt(position:Null<HxPos>):TypedStmt
		return new TypedStmt(Break, position);

	public static function continueStmt(position:Null<HxPos>):TypedStmt
		return new TypedStmt(Continue, position);

	public static function throwStmt(expression:TypedExpr, position:Null<HxPos>):TypedStmt
		return new TypedStmt(Throw, position, null, [expression]);

	public static function returnVoid(position:Null<HxPos>):TypedStmt
		return new TypedStmt(ReturnVoid, position);

	public static function returnValue(expression:TypedExpr, position:Null<HxPos>):TypedStmt
		return new TypedStmt(Return, position, null, [expression]);

	public static function expressionStmt(expression:TypedExpr, position:Null<HxPos>):TypedStmt
		return new TypedStmt(Expression, position, null, [expression]);

	public function getTag():TypedStmtTag
		return tag;

	public function getPosition():Null<HxPos>
		return position;

	public function getNames():Array<String>
		return names.copy();

	public function getExpressions():Array<TypedExpr>
		return expressions.copy();

	public function getStatements():Array<TypedStmt>
		return statements.copy();

	public function getPatterns():Array<HxSwitchPattern>
		return patterns.copy();

	public function getCatchNames():Array<String>
		return catchNames.copy();

	public function getCatchTypeHints():Array<String>
		return catchTypeHints.copy();

	public function getMetadata():Array<String>
		return metadata.copy();

	/** Local declarations introduced by this statement in canonical source order. **/
	public function getLocalBindings():Array<TyLocalBinding>
		return localBindings.copy();

	/** Rebuild this immutable statement after a shared recursive expression pass. **/
	public function withChildren(newExpressions:Array<TypedExpr>, newStatements:Array<TypedStmt>):TypedStmt
		return new TypedStmt(tag, position, names, newExpressions, newStatements, patterns, catchNames, catchTypeHints, metadata, localBindings);
}
