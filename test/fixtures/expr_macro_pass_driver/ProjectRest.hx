/** A project macro with the same rest-argument shape as `python.Syntax.arrayAccess`. */
class ProjectRest {
	static function main():Void {
		final values:Dynamic = [1, 2];
		macros.Macros.access(values, 0);
	}
}
