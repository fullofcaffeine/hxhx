private class ParseProblem extends haxe.Exception {}

private enum RecoveryExpression {
	Unsupported(detail:String);
}

private enum RecoveryStatement {
	Expression(expression:RecoveryExpression, position:Int);
}

class Main {
	/** Matches the parser's typed-catch recovery and enum-construction shape. */
	static function recover(action:() -> Void):Array<RecoveryStatement> {
		inline function tokenLabel(value:Int):String {
			return switch (value) {
				case 0: "eof";
				case 1: "}";
				case _: "other(" + String.fromCharCode(value) + ")";
			};
		}
		inline function oneLine(text:String):String {
			if (text == null)
				return "";
			return StringTools.replace(StringTools.replace(text, "\n", " "), "\r", " ");
		}
		inline function errorDetail(message:String):String {
			return "problem:" + oneLine(tokenLabel(1)) + ":" + oneLine(message);
		}
		final output = new Array<RecoveryStatement>();
		try {
			action();
			0;
		} catch (error:ParseProblem) {
			output.push(Expression(Unsupported(errorDetail(error.message)), 0));
			0;
		} catch (error:String) {
			output.push(Expression(Unsupported(errorDetail(error)), 0));
			0;
		}
		return output;
	}

	static function main():Void {
		Sys.println("typed=" + recover(() -> throw new ParseProblem("typed")).length);
		Sys.println("text=" + recover(() -> throw "text").length);
	}
}
