package reflaxe.ocaml.target;

import haxe.crypto.Sha256;

/** Expression shapes admitted by the first recursive shared-target tracer. **/
enum OcamlTargetExpressionKind {
	LiteralExpression;
	LocalReadExpression;
	VariableDeclarationExpression;
	BlockExpression;
}

/**
	One immutable expression tree copied independently by either compiler host.

	Revision 1 is deliberately small. It admits direct non-null literals,
	initialized source locals, reads of those locals, and lexical blocks. It does
	not approximate unsupported expressions or admit compiler temporaries.
**/
class OcamlTargetExpressionFact {
	public static final SCHEMA_REVISION = "reflaxe-ocaml-target-expression-v1";

	public final path:String;
	public final kind:OcamlTargetExpressionKind;
	public final semanticTypeDisplay:String;
	public final literal:Null<OcamlTargetLiteralFact>;
	public final binding:Null<OcamlTargetBindingFact>;

	final children:Array<OcamlTargetExpressionFact>;
	final canonicalIdentity:String;

	function new(path:String, kind:OcamlTargetExpressionKind, semanticTypeDisplay:String, literal:Null<OcamlTargetLiteralFact>,
			binding:Null<OcamlTargetBindingFact>, children:Array<OcamlTargetExpressionFact>) {
		this.path = OcamlTargetExpressionPath.require(path);
		if (kind == null)
			throw "OCaml target expression requires a kind";
		this.kind = kind;
		this.semanticTypeDisplay = required(semanticTypeDisplay, "semantic type");
		this.literal = literal;
		this.binding = binding;
		this.children = children == null ? [] : children.copy();
		validateShape(this.path, this.kind, this.semanticTypeDisplay, this.literal, this.binding, this.children);
		canonicalIdentity = Sha256.encode(OcamlTargetDeclarationCodec.encode(identityParts(this.path, this.kind, this.semanticTypeDisplay, this.literal,
			this.binding, this.children)));
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
			binding:Null<OcamlTargetBindingFact>, children:Array<OcamlTargetExpressionFact>):Array<Null<String>> {
		final parts = new Array<Null<String>>();
		parts.push(SCHEMA_REVISION);
		parts.push(path);
		parts.push(kindName(kind));
		parts.push(semanticTypeDisplay);
		parts.push(literal == null ? null : literal.getCanonicalIdentity());
		parts.push(binding == null ? null : binding.getCanonicalIdentity());
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
		};
	}

	static function validateNode(node:OcamlTargetExpressionFact, scopes:Array<Map<String, Bool>>, identities:Map<String, Bool>):Void {
		switch (node.kind) {
			case LiteralExpression:
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
