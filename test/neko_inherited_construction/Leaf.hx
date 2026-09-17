/** A third level must retain the same receiver through both superclass calls. */
class Leaf extends Derived {
	public var leafValue:Int = Base.mark("leaf-field", 13);

	public function new() {
		Sys.println("leaf-before");
		super();
		Sys.println("leaf-after");
	}
}
