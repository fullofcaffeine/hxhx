import left.Parent;
import right.Parent as OtherParent;

/** Independently authored namespace cases, executable with upstream Haxe. */
class Main {
	static var selected:Class<Parent> = Parent;

	static function classValue():Class<Parent> {
		return Parent;
	}

	static function aliasValue():Class<OtherParent> {
		return OtherParent;
	}

	static function qualifiedValue():Class<right.Parent> {
		return right.Parent;
	}

	static function localValue(Parent:Class<OtherParent>):Class<OtherParent> {
		return Parent;
	}

	static function typeOperand(value:Parent, Parent:Class<OtherParent>):Bool {
		return value is Parent;
	}

	static function valueOperand(value:Parent, Parent:Class<OtherParent>):Bool {
		return Std.isOfType(value, Parent);
	}

	static function enumValue():Choice {
		return Choice.One;
	}

	static function main():Void {
		final value = new Parent();
		Sys.println(classValue() == left.Parent);
		Sys.println(aliasValue() == right.Parent);
		Sys.println(qualifiedValue() == right.Parent);
		Sys.println(localValue(right.Parent) == right.Parent);
		Sys.println(typeOperand(value, right.Parent));
		Sys.println(valueOperand(value, right.Parent));
		Sys.println(FieldValues.read() == left.Parent);
		Sys.println(selected == left.Parent);
		Sys.println(enumValue() == Choice.One);
		Sys.println(EnumValues.read() == EnumValues.Token.Parent);
	}
}

/** A value field must win over the imported type with the same spelling. */
class FieldValues {
	static var Parent:Class<left.Parent> = left.Parent;

	public static function read():Class<left.Parent> {
		return Parent;
	}
}

enum Choice {
	One;
}
