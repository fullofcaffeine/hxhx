package hxhx.macro;

import backend.ocaml.Stage3OcamlMacroPluginEntry;
import backend.ocaml.Stage3OcamlMacroPluginEntry.MacroPluginParameter;
import haxe.macro.Expr.ExprDef;

/** One call argument as the plugin receives it. */
enum ProjectMacroArgument {
	/** The authored syntax of an `Expr` parameter; the session exports it with its position. */
	Syntax(expression:HxExpr);

	/** The checked constant of a `String`, `Int`, `Float`, or `Bool` parameter. */
	Constant(value:ExprDef);
}

/**
	Match the arguments of one selected project macro call to the macro's parameters.

	Why
	- Upstream Haxe 4.3.7 passes an argument as syntax only when its parameter is `haxe.macro.Expr`.
	  For any other parameter the argument must be a constant, which the macro receives as a value
	  (`src/typing/macroContext.ml`, `type_macro`, lines 723-797).
	- A wrong argument is a compile error at the call, never an ordinary call, so the compiler checks
	  it before it records or sends the call.

	What (the upstream rule, for the parameter types hxhx supports)
	- A constant is a `String`, `Int`, `Float`, or `Bool` literal, optionally in parentheses
	  (`Texpr.type_constant_value`, `src/core/texpr.ml` lines 577-605). `-1` is a constant because the
	  upstream parser folds the sign into the literal; `-(1)` is not.
	- The constant's type must unify with the parameter type; an `Int` constant may fill a `Float`
	  parameter. Otherwise upstream reports `<Constant type> should be <Parameter type>`.
	- An argument that is not a constant is typed as `haxe.macro.Expr` for the error
	  (`macroContext.ml` line 766), so upstream reports `haxe.macro.Expr should be <Parameter type>`.
	- Type errors add `... For function argument '<name>'` (`src/typing/callUnification.ml` line 14).
	- A missing argument reports `Not enough arguments, expected <name>:<Type>, ...` (an `Expr`
	  parameter prints as `Dynamic`) and an extra one `Too many arguments` (`src/core/error.ml`
	  lines 296-299).

	Not yet (each is reported, never guessed): `null`, array and object constants, and
	single-quoted strings that contain `$`. hxhx's parser has already turned such a string into
	concatenation, so it is reported as a non-constant, where upstream passes the raw text.
	Messages carry the call file, not upstream's line and character range: argument nodes own no
	exact positions yet (haxe_ocaml-9sj5p.2).
**/
class ProjectMacroArguments {
	/** The arguments for declaration `key` in call order, or throws the upstream-worded error. */
	public static function bind(key:String, declaration:HxFunctionDecl, authored:Array<HxExpr>, filePath:String):Array<ProjectMacroArgument> {
		final parameters = Stage3OcamlMacroPluginEntry.parameters(key, declaration);
		final names = [
			for (argument in HxFunctionDecl.getArgs(declaration))
				HxFunctionArg.getName(argument)
		];
		// Upstream unifies an `Expr` parameter as `Dynamic` (`macroContext.ml` line 732), so its messages print it so.
		final types = [
			for (parameter in parameters)
				switch parameter {
					case SyntaxParameter:
						"Dynamic";
					case ConstantParameter(type):
						type;
				}
		];
		final prefix = filePath + ": expression macro " + key + ": ";
		if (authored.length < parameters.length) {
			final missing = [
				for (index in authored.length...parameters.length)
					names[index] + ":" + types[index]
			];
			throw prefix + "Not enough arguments, expected " + missing.join(", ");
		}
		if (authored.length > parameters.length)
			throw prefix + "Too many arguments";
		final out = new Array<ProjectMacroArgument>();
		for (index in 0...parameters.length) {
			switch parameters[index] {
				case SyntaxParameter:
					out.push(Syntax(authored[index]));
				case ConstantParameter(type):
					final mismatch = (found:String) -> prefix + found + " should be " + type + "\n" + filePath + ": ... For function argument '"
						+ names[index] + "'";
					switch constantOf(authored[index]) {
						case null:
							throw mismatch("haxe.macro.Expr");
						case NotSupported(kind):
							throw prefix + "function argument '" + names[index] + "' receives " + kind
								+ "; null, array, and object constants are not supported yet";
						case Value(found, _) if (found != type && !(found == "Int" && type == "Float")):
							throw mismatch(found);
						case Value(_, value):
							out.push(Constant(value));
					}
			}
		}
		return out;
	}

	/** The constant an argument is, or `null` when it is not one. */
	static function constantOf(expression:HxExpr):Null<ArgumentConstant> {
		return switch expression {
			case EParenthesized(inner, _): constantOf(inner);
			case EString(value): Value("String", EConst(CString(value, DoubleQuotes)));
			case EInt(value): Value("Int", EConst(CInt(Std.string(value), null)));
			case EFloat(value): Value("Float", EConst(CFloat(Std.string(value), null)));
			case EBool(value): Value("Bool", EConst(CIdent(value ? "true" : "false")));
			case EUnop(Negate, Prefix, EInt(value)): Value("Int", EConst(CInt(Std.string(-value), null)));
			case EUnop(Negate, Prefix, EFloat(value)): Value("Float", EConst(CFloat(Std.string(-value), null)));
			case ENull: NotSupported("null");
			case EArrayDecl(values) if (values.filter(value -> constantOf(value) == null).length == 0): NotSupported("an array constant");
			case EAnon(_, values) if (values.filter(value -> constantOf(value) == null).length == 0): NotSupported("an object constant");
			case _: null;
		};
	}
}

/** A constant call argument: its Haxe type and wire syntax, or a constant hxhx cannot pass yet. */
private enum ArgumentConstant {
	Value(type:String, value:ExprDef);
	NotSupported(kind:String);
}
