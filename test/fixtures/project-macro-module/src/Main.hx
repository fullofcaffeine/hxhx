import projectmacro.ProjectMacro;

/** Runtime check proving the compile-time project macro produced the expected value. **/
class Main {
	static function main():Void {
		Sys.println(ProjectMacro.message());
	}
}
