/** The macro must receive this loop before ordinary name and value checks. */
class Main {
	static function main():Void {
		Sys.println(SyntaxArguments.inspect(while (unresolvedCondition) {
			unresolvedTick(unresolvedCondition);
		}));
	}
}
