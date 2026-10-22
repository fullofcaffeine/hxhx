// Non-ASCII text before the declarations: café ☕ 🙂.
#if false
// Inactive text also retains physical positions: café ☕ 🙂.
#end

/** The range starts at the class keyword, after this comment and metadata. */
@:keep private class Hidden {
	public var text:String = "}";

	public function new() {}
}

/** Interface positions follow the same keyword-to-closing-brace contract. */
interface HasValue {
	public function value():Int;
}

/** An empty class still has a real declaration range. */
class Empty {}

/** Extern classes retain a source declaration even without an implementation. */
extern class Foreign {
	public function new();
}

/** The parser merges the module helper into this class without changing its range. */
class SourceClasses {
	static function main():Void {}
}

/** A separate module member must not extend the preceding class range. */
function moduleHelper():Int
	return 1;

// Trailing trivia is outside every declaration range.
