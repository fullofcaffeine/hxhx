interface Ranked {
	function rank():Int;
}

class Person implements Ranked {
	final first:String;

	public function new(first:String)
		this.first = first;

	public function name():String
		return first;

	// Calls name() on its own instance through an implicit `this`.
	public function describe():String
		return "person " + name();

	public function rank():Int
		return 1;

	public function weight():Float
		return 1.5;

	public function senior():Bool
		return false;

	public function greet(other:String, times:Int):String
		return "hello " + other + " x" + times;

	public function shout():Void
		Sys.println("person shout " + first);

	public function label(?suffix:String):String
		return suffix == null ? "plain" : "plain " + suffix;

	public function score(bonus:Int = 2):Int
		return 100 + bonus;

	public function echo<T>(value:T):T
		return value;

	// The override adds a default value to the same optional Float argument.
	public function ratio(?x:Float):String
		return x == null ? "no ratio" : "ratio " + x;

	public function record(value:Int):Void
		Sys.println("person record " + value);

	// No class overrides tag(), so its calls stay direct.
	public function tag():String
		return "tag " + first;
}

// Overrides every method and calls each superclass implementation.
class Teacher extends Person {
	public function new(first:String)
		super(first);

	override public function name():String
		return "teacher " + super.name();

	override public function rank():Int
		return super.rank() + 10;

	override public function weight():Float
		return super.weight() * 1.5;

	override public function senior():Bool
		return !super.senior();

	override public function greet(other:String, times:Int):String
		return "teacher " + super.greet(other, times + 1);

	override public function label(?suffix:String):String
		return "teacher " + super.label(suffix);

	override public function score(bonus:Int = 5):Int
		return super.score(bonus) + 1000;

	override public function ratio(?x:Float = 2.5):String
		return "teacher " + super.ratio(x);

	// An expression body that starts with `super` (not a block).
	override public function record(value:Int):Void
		super.record(value * 2);

	// A method with its own type parameter.
	override public function echo<T>(value:T):T {
		Sys.println("teacher echo");
		return super.echo(value);
	}

	// A super call in statement position.
	override public function shout():Void {
		super.shout();
		Sys.println("teacher shout");
	}
}

// Inherits everything from Teacher without overriding.
class Assistant extends Teacher {
	public function new(first:String)
		super(first);
}

// The fourth level. super.name() reaches Teacher through Assistant, and
// super.tag() reaches Person, which no subclass overrides.
class Professor extends Assistant {
	public function new(first:String)
		super(first);

	override public function name():String
		return "prof " + super.name();

	override public function rank():Int
		return super.rank() * 3;

	override public function describe():String
		return "professor; " + super.describe();

	public function badge():String
		return super.tag() + " / " + super.weight();
}

// A final class that overrides nothing: calls on it stay direct.
final class Visitor extends Person {
	public function new(first:String)
		super(first);
}

class Holder {
	public var member:Person;

	public function new(member:Person)
		this.member = member;

	public function memberName():String
		return member.name();
}

class Main {
	static final lead:Person = new Teacher("sam");

	static function show(p:Person):Void {
		Sys.println(p.name() + " | " + p.describe() + " | " + p.rank() + " | " + Std.string(p.weight()) + " | " + p.senior() + " | " + p.greet("ann", 1)
			+ " | " + p.tag());
		p.shout();
	}

	static function viaInterface(r:Ranked):Int
		return r.rank();

	static function main() {
		final people = new Array<Person>();
		people.push(new Person("pat"));
		people.push(new Teacher("tom"));
		people.push(new Assistant("abe"));
		people.push(new Professor("pia"));
		people.push(new Visitor("vic"));
		for (p in people)
			show(p);

		// Locals typed as a superclass.
		final local:Person = new Professor("lou");
		Sys.println(local.name());
		final middle:Teacher = new Professor("mid");
		Sys.println(middle.name() + " " + middle.rank());
		final level3:Assistant = new Professor("ace");
		Sys.println(level3.describe());

		// A static field and an instance field.
		Sys.println(lead.name() + " " + lead.rank());
		final holder = new Holder(new Assistant("hal"));
		Sys.println(holder.member.name() + " / " + holder.memberName());
		holder.member = new Professor("hep");
		Sys.println(holder.member.name() + " / " + holder.memberName());

		// Array elements read by index.
		Sys.println(people[3].name() + " " + people[1].rank());

		// Method values capture the receiver's own override.
		final read = local.name;
		final score = middle.rank;
		Sys.println(read() + " " + score());

		// Optional arguments: each class applies its own default.
		Sys.println(local.label()
			+ " / "
			+ local.label("x")
			+ " / "
			+ local.score()
			+ " / "
			+ people[0].score() + " / " + people[0].label("y"));

		Sys.println(local.ratio() + " / " + local.ratio(0.5) + " / " + people[0].ratio() + " / " + people[0].ratio(0.25));

		local.record(4);
		people[0].record(4);

		// Generic methods: arguments and results are erased in both classes.
		Sys.println(local.echo("e") + " " + local.echo(7) + " " + people[0].echo(true));

		// Interface calls still reach the overriding class.
		Sys.println(viaInterface(local) + " " + viaInterface(new Teacher("int")));

		// Exact types.
		final prof = new Professor("pro");
		Sys.println(prof.badge() + " " + prof.name());
		final visitor = new Visitor("vee");
		Sys.println(visitor.name() + " " + visitor.rank());
	}
}
