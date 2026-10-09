package reflaxe.ocaml.target;

import haxe.crypto.Sha256;

/** Expression shapes admitted by the first recursive shared-target tracer. **/
enum OcamlTargetExpressionKind {
	LiteralExpression;
	LocalReadExpression;
	VariableDeclarationExpression;
	BlockExpression;
	StaticCallExpression;
	ConditionalExpression;
	NullableIntNullExpression;
	BoxNullableIntExpression;
	UnwrapNullableIntExpression;
	TestNullableIntNullExpression;
}

/**
	One immutable expression tree copied independently by either compiler host.

	Revision 5 represents nullable integers and their explicit conversions.
	Direct non-null literals, initialized locals, local reads, and lexical blocks
	retain their value types. Function control lives in OcamlTargetStatementFact.
**/
class OcamlTargetExpressionFact {
	public static final SCHEMA_REVISION = "reflaxe-ocaml-target-expression-v5";

	public final path:String;
	public final kind:OcamlTargetExpressionKind;
	public final semanticTypeDisplay:String;
	public final literal:Null<OcamlTargetLiteralFact>;
	public final binding:Null<OcamlTargetBindingFact>;
	public final staticCall:Null<OcamlTargetStaticCallFact>;

	final children:Array<OcamlTargetExpressionFact>;
	final canonicalIdentity:String;

	function new(path:String, kind:OcamlTargetExpressionKind, semanticTypeDisplay:String, literal:Null<OcamlTargetLiteralFact>,
			binding:Null<OcamlTargetBindingFact>, children:Array<OcamlTargetExpressionFact>, ?staticCall:OcamlTargetStaticCallFact) {
		this.path = OcamlTargetExpressionPath.require(path);
		if (kind == null)
			throw "OCaml target expression requires a kind";
		this.kind = kind;
		this.semanticTypeDisplay = required(semanticTypeDisplay, "semantic type");
		this.literal = literal;
		this.binding = binding;
		this.staticCall = staticCall;
		this.children = children == null ? [] : children.copy();
		if ((kind == StaticCallExpression) != (staticCall != null))
			throw "OCaml target expression has inconsistent static call facts";
		validateShape(this.path, this.kind, this.semanticTypeDisplay, this.literal, this.binding, this.children);
		canonicalIdentity = Sha256.encode(OcamlTargetDeclarationCodec.encode(identityParts(this.path, this.kind, this.semanticTypeDisplay, this.literal,
			this.binding, this.children, this.staticCall)));
	}

	public static function literalExpression(path:String, literal:OcamlTargetLiteralFact):OcamlTargetExpressionFact {
		if (literal == null)
			throw "OCaml target literal expression requires a literal fact";
		return new OcamlTargetExpressionFact(path, LiteralExpression, literal.semanticTypeDisplay, literal, null, []);
	}

	public static function localRead(path:String, semanticTypeDisplay:String, binding:OcamlTargetBindingFact):OcamlTargetExpressionFact {
		if (binding == null)
			throw "OCaml target local read requires a binding fact";
		return new OcamlTargetExpressionFact(path, LocalReadExpression, semanticTypeDisplay, null, binding, []);
	}

	public static function variableDeclaration(path:String, binding:OcamlTargetBindingFact, initializer:OcamlTargetExpressionFact):OcamlTargetExpressionFact {
		if (binding == null || initializer == null)
			throw "OCaml target variable declaration revision 1 requires a binding and initializer";
		return new OcamlTargetExpressionFact(path, VariableDeclarationExpression, "Void", null, binding, [initializer]);
	}

	public static function block(path:String, semanticTypeDisplay:String, children:Array<OcamlTargetExpressionFact>):OcamlTargetExpressionFact
		return new OcamlTargetExpressionFact(path, BlockExpression, semanticTypeDisplay, null, null, children);

	/** A contextual null uses the existing nullable Int representation, never integer zero. **/
	public static function nullableIntNull(path:String):OcamlTargetExpressionFact
		return new OcamlTargetExpressionFact(path, NullableIntNullExpression, "Null<Int>", null, null, []);

	/** Keep representation changes explicit instead of relabeling the operand's type. **/
	public static function boxNullableInt(path:String, operand:OcamlTargetExpressionFact):OcamlTargetExpressionFact
		return new OcamlTargetExpressionFact(path, BoxNullableIntExpression, "Null<Int>", null, null, [operand]);

	/** Null must be checked before converting a nullable representation to an Int value. **/
	public static function unwrapNullableInt(path:String, operand:OcamlTargetExpressionFact):OcamlTargetExpressionFact
		return new OcamlTargetExpressionFact(path, UnwrapNullableIntExpression, "Int", null, null, [operand]);

	public static function testNullableIntNull(path:String, operand:OcamlTargetExpressionFact):OcamlTargetExpressionFact
		return new OcamlTargetExpressionFact(path, TestNullableIntNullExpression, "Bool", null, null, [operand]);

	/** Keep condition and alternatives distinct so lowering cannot evaluate both branches. **/
	public static function conditional(path:String, semanticTypeDisplay:String, condition:OcamlTargetExpressionFact, whenTrue:OcamlTargetExpressionFact,
			whenFalse:OcamlTargetExpressionFact):OcamlTargetExpressionFact {
		if (condition == null || whenTrue == null || whenFalse == null)
			throw "OCaml target conditional requires a condition and both branches";
		return new OcamlTargetExpressionFact(path, ConditionalExpression, semanticTypeDisplay, null, null, [condition, whenTrue, whenFalse]);
	}

	public static function directStaticCall(path:String, call:OcamlTargetStaticCallFact, arguments:Array<OcamlTargetExpressionFact>):OcamlTargetExpressionFact {
		if (call == null || arguments == null || arguments.length != call.copyArgumentTypeDisplays().length)
			throw "OCaml target static call arguments do not match its declaration";
		final types = call.copyArgumentTypeDisplays();
		for (index in 0...arguments.length)
			if (arguments[index] == null
				|| arguments[index].semanticTypeDisplay != types[index]
				|| arguments[index].path != OcamlTargetExpressionPath.indexed(path, "argument", index))
				throw "OCaml target static call requires exact ordered argument facts";
		return new OcamlTargetExpressionFact(path, StaticCallExpression, call.returnTypeDisplay, null, null, arguments, call);
	}

	/** Preserve source occurrence order when checking the enclosing program's call references. **/
	public function copyStaticCalls():Array<OcamlTargetStaticCallFact> {
		final result = new Array<OcamlTargetStaticCallFact>();
		if (staticCall != null)
			result.push(staticCall);
		for (child in children)
			for (call in child.copyStaticCalls())
				result.push(call);
		return result;
	}

	public function copyChildren():Array<OcamlTargetExpressionFact>
		return children.copy();

	public function getCanonicalIdentity():String
		return canonicalIdentity;

	/** Reject dangling reads, duplicate declarations, and non-structural child paths. **/
	public function validateClosedBindings():Void {
		final scopes = new Array<Map<String, Bool>>();
		final identities = new Map<String, Bool>();
		validateNode(this, scopes, identities);
	}

	static function validateShape(path:String, kind:OcamlTargetExpressionKind, semanticTypeDisplay:String, literal:Null<OcamlTargetLiteralFact>,
			binding:Null<OcamlTargetBindingFact>, children:Array<OcamlTargetExpressionFact>):Void {
		switch (kind) {
			case NullableIntNullExpression:
				if (literal != null || binding != null || children.length != 0 || semanticTypeDisplay != "Null<Int>")
					invalidShape("nullable Int null");
			case BoxNullableIntExpression | UnwrapNullableIntExpression | TestNullableIntNullExpression:
				if (literal != null || binding != null || children.length != 1 || children[0] == null)
					invalidShape("nullable Int operation");
				final inputType = kind == BoxNullableIntExpression ? "Int" : "Null<Int>";
				final resultType = kind == BoxNullableIntExpression ? "Null<Int>" : kind == UnwrapNullableIntExpression ? "Int" : "Bool";
				if (children[0].path != OcamlTargetExpressionPath.child(path, "operand")
					|| children[0].semanticTypeDisplay != inputType
					|| semanticTypeDisplay != resultType)
					throw "OCaml target nullable Int operation requires its exact operand path and types";
			case ConditionalExpression:
				if (literal != null || binding != null || children.length != 3)
					invalidShape("conditional");
				final roles = ["condition", "then", "else"];
				for (index in 0...children.length)
					if (children[index].path != OcamlTargetExpressionPath.child(path, roles[index]))
						throw "OCaml target conditional child path does not match its role";
				if (children[0].semanticTypeDisplay != "Bool"
					|| children[1].semanticTypeDisplay != semanticTypeDisplay
					|| children[2].semanticTypeDisplay != semanticTypeDisplay)
					throw "OCaml target conditional requires a Boolean condition and exact branch result types";
				if (children[1].kind != BlockExpression || children[2].kind != BlockExpression)
					throw "OCaml target conditional requires scoped branches";
			case StaticCallExpression:
				if (literal != null || binding != null)
					invalidShape("static call");
			case LiteralExpression:
				if (literal == null) {
					invalidShape("literal");
				} else {
					if (binding != null || children.length != 0)
						invalidShape("literal");
					if (!isDirectLiteral(literal))
						throw "OCaml target expression revision 1 requires an exact direct literal type";
				}
			case LocalReadExpression:
				if (binding == null) {
					invalidShape("local read");
				} else {
					if (literal != null || children.length != 0)
						invalidShape("local read");
					if (binding.semanticTypeDisplay != semanticTypeDisplay)
						throw "OCaml target expression revision 1 does not admit local-read conversions";
				}
			case VariableDeclarationExpression:
				if (binding == null) {
					invalidShape("variable declaration");
				} else {
					if (literal != null || children.length != 1)
						invalidShape("variable declaration");
					if (binding.declarationPath != OcamlTargetExpressionPath.child(path, "binding"))
						throw "OCaml target variable binding path does not match its declaration";
					final initializer = onlyChild(children, "variable declaration");
					if (initializer.path != OcamlTargetExpressionPath.child(path, "initializer"))
						throw "OCaml target variable initializer path does not match its declaration";
					if (initializer.semanticTypeDisplay != binding.semanticTypeDisplay)
						throw "OCaml target expression revision 1 does not admit local-initializer conversions";
				}
			case BlockExpression:
				if (literal != null || binding != null)
					invalidShape("block");
				var index = 0;
				var resultType = "Void";
				for (child in children) {
					if (child.path != OcamlTargetExpressionPath.indexed(path, "block-item", index))
						throw "OCaml target block child path does not match its source order";
					resultType = child.semanticTypeDisplay;
					index++;
				}
				if (semanticTypeDisplay != resultType)
					throw "OCaml target expression block result does not match its final child";
		}
	}

	static function isDirectLiteral(value:OcamlTargetLiteralFact):Bool {
		return switch (value.kind) {
			case IntValue: value.semanticTypeDisplay == "Int";
			case BoolValue: value.semanticTypeDisplay == "Bool";
			case StringValue: value.semanticTypeDisplay == "String";
			case NullValue | ThisValue | SuperValue: false;
		};
	}

	static function identityParts(path:String, kind:OcamlTargetExpressionKind, semanticTypeDisplay:String, literal:Null<OcamlTargetLiteralFact>,
			binding:Null<OcamlTargetBindingFact>, children:Array<OcamlTargetExpressionFact>, staticCall:Null<OcamlTargetStaticCallFact>):Array<Null<String>> {
		final parts = new Array<Null<String>>();
		parts.push(SCHEMA_REVISION);
		parts.push(path);
		parts.push(kindName(kind));
		parts.push(semanticTypeDisplay);
		parts.push(literal == null ? null : literal.getCanonicalIdentity());
		parts.push(binding == null ? null : binding.getCanonicalIdentity());
		parts.push(staticCall == null ? null : staticCall.getCanonicalIdentity());
		parts.push(Std.string(children.length));
		for (child in children)
			parts.push(child.getCanonicalIdentity());
		return parts;
	}

	/** Returns the protocol spelling without target-specific enum stringification. **/
	static function kindName(kind:OcamlTargetExpressionKind):String {
		return switch (kind) {
			case LiteralExpression: "LiteralExpression";
			case LocalReadExpression: "LocalReadExpression";
			case VariableDeclarationExpression: "VariableDeclarationExpression";
			case BlockExpression: "BlockExpression";
			case StaticCallExpression: "StaticCallExpression";
			case ConditionalExpression: "ConditionalExpression";
			case NullableIntNullExpression: "NullableIntNullExpression";
			case BoxNullableIntExpression: "BoxNullableIntExpression";
			case UnwrapNullableIntExpression: "UnwrapNullableIntExpression";
			case TestNullableIntNullExpression: "TestNullableIntNullExpression";
		};
	}

	@:allow(reflaxe.ocaml.target.OcamlTargetStatementFact)
	static function validateNode(node:OcamlTargetExpressionFact, scopes:Array<Map<String, Bool>>, identities:Map<String, Bool>):Void {
		switch (node.kind) {
			case LiteralExpression | NullableIntNullExpression:
			case StaticCallExpression | ConditionalExpression | BoxNullableIntExpression | UnwrapNullableIntExpression | TestNullableIntNullExpression:
				for (child in node.children) {
					scopes.push([]);
					validateNode(child, scopes, identities);
					scopes.pop();
				}
			case LocalReadExpression:
				final local = node.binding;
				if (local == null || !isVisible(local.getCanonicalIdentity(), scopes))
					throw "OCaml target expression contains a local read without a visible source binding";
			case VariableDeclarationExpression:
				if (scopes.length == 0)
					throw "OCaml target variable declaration requires a lexical block";
				validateNode(onlyChild(node.children, "variable declaration"), scopes, identities);
				final local = node.binding;
				if (local == null)
					throw "OCaml target variable declaration lost its binding";
				final identity = local.getCanonicalIdentity();
				if (identities.exists(identity))
					throw "OCaml target expression contains a duplicate source binding";
				identities.set(identity, true);
				currentScope(scopes).set(identity, true);
			case BlockExpression:
				scopes.push(new Map<String, Bool>());
				for (child in node.children)
					validateNode(child, scopes, identities);
				scopes.pop();
		}
	}

	static function isVisible(identity:String, scopes:Array<Map<String, Bool>>):Bool {
		for (scope in scopes)
			if (scope.exists(identity))
				return true;
		return false;
	}

	static function currentScope(scopes:Array<Map<String, Bool>>):Map<String, Bool> {
		var current:Null<Map<String, Bool>> = null;
		for (scope in scopes)
			current = scope;
		if (current == null)
			throw "OCaml target variable declaration requires a lexical block";
		return current;
	}

	static function onlyChild(children:Array<OcamlTargetExpressionFact>, label:String):OcamlTargetExpressionFact {
		var selected:Null<OcamlTargetExpressionFact> = null;
		for (child in children) {
			if (selected != null)
				invalidShape(label);
			selected = child;
		}
		if (selected == null)
			invalidShape(label);
		return selected;
	}

	static function invalidShape(label:String):Void
		throw "OCaml target expression has an invalid " + label + " shape";

	static function required(value:String, label:String):String {
		final normalized = value == null ? "" : StringTools.trim(value);
		if (normalized.length == 0)
			throw "OCaml target expression requires " + label;
		return normalized;
	}
}
