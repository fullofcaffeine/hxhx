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
		validateShape();
		canonicalIdentity = Sha256.encode(OcamlTargetDeclarationRequest.encode(identityParts()));
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
		return new OcamlTargetExpressionFact(path, VariableDeclarationExpression, binding.semanticTypeDisplay, null, binding, [initializer]);
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

	function validateShape():Void {
		switch (kind) {
			case LiteralExpression:
				if (literal == null || binding != null || children.length != 0)
					invalidShape("literal");
			case LocalReadExpression:
				if (literal != null || binding == null || children.length != 0)
					invalidShape("local read");
			case VariableDeclarationExpression:
				if (literal != null || binding == null || children.length != 1)
					invalidShape("variable declaration");
				if (binding.declarationPath != OcamlTargetExpressionPath.child(path, "binding"))
					throw "OCaml target variable binding path does not match its declaration";
				if (children[0].path != OcamlTargetExpressionPath.child(path, "initializer"))
					throw "OCaml target variable initializer path does not match its declaration";
			case BlockExpression:
				if (literal != null || binding != null)
					invalidShape("block");
				for (index in 0...children.length)
					if (children[index].path != OcamlTargetExpressionPath.indexed(path, "block-item", index))
						throw "OCaml target block child path does not match its source order";
		}
	}

	function identityParts():Array<Null<String>> {
		final parts = new Array<Null<String>>();
		parts.push(SCHEMA_REVISION);
		parts.push(path);
		parts.push(Std.string(kind));
		parts.push(semanticTypeDisplay);
		parts.push(literal == null ? null : literal.getCanonicalIdentity());
		parts.push(binding == null ? null : binding.getCanonicalIdentity());
		parts.push(Std.string(children.length));
		for (child in children)
			parts.push(child.getCanonicalIdentity());
		return parts;
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
				validateNode(node.children[0], scopes, identities);
				final local = node.binding;
				if (local == null)
					throw "OCaml target variable declaration lost its binding";
				final identity = local.getCanonicalIdentity();
				if (identities.exists(identity))
					throw "OCaml target expression contains a duplicate source binding";
				identities.set(identity, true);
				scopes[scopes.length - 1].set(identity, true);
			case BlockExpression:
				scopes.push(new Map<String, Bool>());
				for (child in node.children)
					validateNode(child, scopes, identities);
				scopes.pop();
		}
	}

	static function isVisible(identity:String, scopes:Array<Map<String, Bool>>):Bool {
		var index = scopes.length;
		while (index > 0) {
			index--;
			if (scopes[index].exists(identity))
				return true;
		}
		return false;
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
