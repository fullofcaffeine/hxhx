import haxe.macro.Expr;

/** A small tree whose constructors take values produced by statements. */
enum Tree {
	Leaf(value:Int);
	Named(label:String);
	Branch(items:Array<Tree>);
	Pair(left:Tree, right:Tree);
	Triple(first:Int, second:String, third:Int);
}

/** Mirrors the shape of `haxe.macro.Expr.ExprDef` without the macro package. */
enum Constant {
	ConstText(value:String);
	ConstNumber(value:String);
}

enum Definition {
	DefConst(value:Constant);
	DefArray(values:Array<Node>);
	DefCall(callee:Node, arguments:Array<Node>);
}

typedef Node = {expr:Definition, label:String};

/**
	Each constructor argument below needs statements before its value exists:
	a comprehension, a block, a conditional, a switch, a try, or a closure call.
	Upstream Haxe evaluates the arguments left to right and then constructs the
	enum value, so the printed order and results must match `haxe --interp`.
 */
class Main {
	static function note(label:String, value:Int):Int {
		Sys.println("eval " + label);
		return value;
	}

	static function text(label:String):String {
		Sys.println("eval " + label);
		return label;
	}

	static function fail(flag:Bool):Int {
		if (flag)
			throw "boom";
		return 1;
	}

	static function show(tree:Tree):String {
		return switch tree {
			case Leaf(value): "Leaf(" + value + ")";
			case Named(label): "Named(" + label + ")";
			case Branch(items): "Branch[" + [for (item in items) show(item)].join(",") + "]";
			case Pair(left, right): "Pair(" + show(left) + "," + show(right) + ")";
			case Triple(first, second, third): "Triple(" + first + "," + second + "," + third + ")";
		}
	}

	static function showConstant(constant:Constant):String {
		return switch constant {
			case ConstText(value): "text:" + value;
			case ConstNumber(value): "number:" + value;
		}
	}

	static function showNode(node:Node):String {
		return switch node.expr {
			case DefConst(value): showConstant(value);
			case DefArray(values): "array[" + [for (value in values) showNode(value)].join(",") + "]";
			case DefCall(callee, arguments): "call "
				+ showNode(callee)
				+ "("
				+ [for (value in arguments) showNode(value)].join(",") + ")";
		}
	}

	static function showExpr(expr:Expr):String {
		return switch expr.expr {
			case EConst(CString(value, _)): "string:" + value;
			case EConst(CInt(value)): "int:" + value;
			case EConst(CIdent(value)): "ident:" + value;
			case EArrayDecl(values): "array[" + [for (value in values) showExpr(value)].join(",") + "]";
			case ECall(callee, arguments): "call " + showExpr(callee) + "(" + [for (value in arguments) showExpr(value)].join(",") + ")";
			case _: "other";
		}
	}

	static function userTrees():Void {
		final values = [1, 2, 3];
		final flag = values.length > 2;
		Sys.println(show(Branch([for (value in values) Leaf(value * 10)])));
		Sys.println(show(Tree.Branch([for (value in values) if (value != 2) Tree.Leaf(value)])));
		Sys.println(show(Leaf({
			final doubled = values[1] * 2;
			doubled + 1;
		})));
		Sys.println(show(Named(if (flag) "long" else "short")));
		Sys.println(show(Leaf(switch values[0] {
			case 1: 100;
			case _: 0;
		})));
		Sys.println(show(Leaf(try fail(true) catch (error:String) -1)));
		Sys.println(show(Leaf(try fail(false) catch (error:String) -1)));
		Sys.println(show(Leaf((function() {
			var total = 0;
			for (index in 0...values.length)
				total += values[index];
			return total;
		})())));
		final mapped = values.map(value -> Pair(Leaf(value), Named("n" + value)));
		Sys.println([for (tree in mapped) show(tree)].join(" "));
		Sys.println(show(Triple(note("first", 1), {
			Sys.println("block second");
			text("second");
		}, if (flag) note("third", 3) else 0)));
		Sys.println(show(Pair(Leaf(note("left", 1)), Branch([for (value in values) Leaf(note("item" + value, value))]))));
		Sys.println(show(Pair(Branch([Pair(Leaf(1), Branch([for (value in values) Named("x" + value)]))]), Leaf({
			Sys.println("nested block");
			7;
		}))));
	}

	static function mirroredDefinitions():Void {
		final names = ["a", "b"];
		final array:Node = {expr: DefArray([for (name in names) {expr: DefConst(ConstText(name)), label: name}]), label: "array"};
		Sys.println(showNode(array));
		final callee:Node = {expr: DefConst(ConstText("f")), label: "callee"};
		final call:Node = {
			expr: Definition.DefCall(callee, [
				{
					final items:Array<Node> = [];
					for (name in names)
						items.push({expr: DefConst(ConstNumber(name)), label: name});
					{expr: Definition.DefArray(items), label: "items"};
				}
			]),
			label: "call"
		};
		Sys.println(showNode(call));
		final constants = [1, 2].map(value -> Definition.DefConst(ConstNumber(Std.string(value))));
		Sys.println([for (definition in constants) showNode({expr: definition, label: "c"})].join(" "));
	}

	static function macroExpressions():Void {
		final names = ["a", "b"];
		final p:Position = null;
		final array:Expr = {expr: haxe.macro.Expr.ExprDef.EArrayDecl([for (name in names) {expr: EConst(CString(name, DoubleQuotes)), pos: p}]), pos: p};
		Sys.println(showExpr(array));
		final bare:Expr = {expr: EArrayDecl([for (name in names) {expr: ExprDef.EConst(CIdent(name)), pos: p}]), pos: p};
		Sys.println(showExpr(bare));
		final callee:Expr = {expr: EConst(CIdent("f")), pos: p};
		final call:Expr = {
			expr: ExprDef.ECall(callee, [
				{
					final items:Array<Expr> = [];
					for (name in names)
						items.push({expr: EConst(CString(name, DoubleQuotes)), pos: p});
					{expr: ExprDef.EArrayDecl(items), pos: p};
				}
			]),
			pos: p
		};
		Sys.println(showExpr(call));
		final constants = [1, 2].map(value -> haxe.macro.Expr.ExprDef.EConst(CInt(Std.string(value))));
		Sys.println([for (definition in constants) showExpr({expr: definition, pos: p})].join(" "));
	}

	static function main():Void {
		userTrees();
		mirroredDefinitions();
		macroExpressions();
	}
}
