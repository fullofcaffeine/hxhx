/** Executable proof for implicit null defaults outside the exact representation registry. */
class Main {
	static function main():Void {
		final holder = new ChildHolder();
		Sys.println("defaults=" + (holder.inheritedValue == null) + "/" + (holder.dynamicValue == null) + "/" + (holder.classValue == null) + "/"
			+ (holder.enumValue == null));
	}
}

/** Parent declaration used to prove an inherited reference default. */
class ParentHolder {
	public var inheritedValue:Dynamic;

	public function new() {}
}

/** Child record with dynamic, class, and enum fields that have no initializer. */
class ChildHolder extends ParentHolder {
	public var dynamicValue:Dynamic;
	public var classValue:ReferenceValue;
	public var enumValue:DefaultChoice;

	public function new() {
		super();
	}
}
