package reflaxe.ocaml.target;

import haxe.crypto.Sha256;

/** Statements separate function control from the type of an expression's value. **/
enum OcamlTargetStatementKind {
	ExpressionStatement;
	ReturnStatement;
	BlockStatement;
}

/**
	Immutable source statements shared by the stock and native compiler hosts.

	A return carries its payload's exact type; host annotations on the control
	node are not value types. This contract currently admits terminal returns.
	It rejects an early return instead of dropping subsequent source effects.
**/
class OcamlTargetStatementFact {
	public static inline final SCHEMA_REVISION = "reflaxe-ocaml-target-statement-v1";

	public final path:String;
	public final kind:OcamlTargetStatementKind;
	public final expression:Null<OcamlTargetExpressionFact>;

	final children:Array<OcamlTargetStatementFact>;
	final canonicalIdentity:String;

	function new(path:String, kind:OcamlTargetStatementKind, expression:Null<OcamlTargetExpressionFact>, children:Array<OcamlTargetStatementFact>) {
		this.path = OcamlTargetExpressionPath.require(path);
		this.kind = kind;
		this.expression = expression;
		this.children = children.copy();
		final parts:Array<Null<String>> = [
			SCHEMA_REVISION,
			path,
			switch (kind) {
				case ExpressionStatement:
					"ExpressionStatement";
				case ReturnStatement:
					"ReturnStatement";
				case BlockStatement:
					"BlockStatement";
			},
			expression == null ? null : expression.getCanonicalIdentity(),
			Std.string(children.length)
		];
		for (index in 0...children.length) {
			final child = children[index];
			if (child == null || child.path != OcamlTargetExpressionPath.indexed(path, "block-item", index))
				throw "OCaml target statement child path does not match source order";
			parts.push(child.getCanonicalIdentity());
		}
		canonicalIdentity = Sha256.encode(OcamlTargetDeclarationCodec.encode(parts));
	}

	public static function evaluate(expression:OcamlTargetExpressionFact):OcamlTargetStatementFact {
		if (expression == null)
			throw "OCaml target expression statement requires a value expression";
		return new OcamlTargetStatementFact(expression.path, ExpressionStatement, expression, []);
	}

	public static function returnValue(path:String, value:Null<OcamlTargetExpressionFact>):OcamlTargetStatementFact {
		if (value != null && value.path != OcamlTargetExpressionPath.child(path, "return-value"))
			throw "OCaml target return payload path does not match its statement";
		return new OcamlTargetStatementFact(path, ReturnStatement, value, []);
	}

	public static function block(path:String, children:Array<OcamlTargetStatementFact>):OcamlTargetStatementFact
		return new OcamlTargetStatementFact(path, BlockStatement, null, children);

	public function copyChildren():Array<OcamlTargetStatementFact>
		return children.copy();

	public function getCanonicalIdentity():String
		return canonicalIdentity;

	public function copyStaticCalls():Array<OcamlTargetStaticCallFact> {
		final result = expression == null ? [] : expression.copyStaticCalls();
		for (child in children)
			for (call in child.copyStaticCalls())
				result.push(call);
		return result;
	}

	/** Check exact return payload types and require every return to be terminal. **/
	public function admitsFunctionResult(resultType:String):Bool {
		return admitsFlow(resultType, true) && (resultType == "Void" || endsInReturn());
	}

	function admitsFlow(resultType:String, terminal:Bool):Bool {
		return switch (kind) {
			case ExpressionStatement: true;
			case ReturnStatement: terminal && (expression == null ? resultType == "Void" : expression.semanticTypeDisplay == resultType);
			case BlockStatement:
				var valid = true;
				for (index in 0...children.length)
					if (!children[index].admitsFlow(resultType, terminal && index == children.length - 1))
						valid = false;
				valid;
		};
	}

	public function endsInReturn():Bool {
		return switch (kind) {
			case ReturnStatement: true;
			case ExpressionStatement: false;
			case BlockStatement: children.length > 0 && children[children.length - 1].endsInReturn();
		};
	}

	/** Seed parameters before checking source locals with the expression validator. **/
	public function validateBindings(ownerIdentity:String, parameters:Array<OcamlTargetBindingFact>):Void {
		final scope:Map<String, Bool> = [];
		final identities:Map<String, Bool> = [];
		for (parameter in parameters) {
			final identity = parameter.getCanonicalIdentity();
			if (identities.exists(identity))
				throw "OCaml target function contains a duplicate parameter binding";
			scope.set(identity, true);
			identities.set(identity, true);
		}
		validateNode(ownerIdentity, [scope], identities);
	}

	function validateNode(ownerIdentity:String, scopes:Array<Map<String, Bool>>, identities:Map<String, Bool>):Void {
		if (expression != null) {
			validateOwner(expression, ownerIdentity);
			OcamlTargetExpressionFact.validateNode(expression, scopes, identities);
		}
		if (kind == BlockStatement) {
			scopes.push([]);
			for (child in children)
				child.validateNode(ownerIdentity, scopes, identities);
			scopes.pop();
		}
	}

	static function validateOwner(expression:OcamlTargetExpressionFact, ownerIdentity:String):Void {
		if (expression.binding != null && expression.binding.ownerIdentity != ownerIdentity)
			throw "OCaml target function contains a binding from another owner";
		for (child in expression.copyChildren())
			validateOwner(child, ownerIdentity);
	}
}
