/** Declarations shared by the arity cases. Each case module imports this one. */
class Box<A, B> {
	public function new() {}
}

typedef Pair<A, B> = Box<A, B>;

class Def<A, B = String> {
	public function new() {}
}

abstract Wrap<T>(Int) {
	public function new(v:Int)
		this = v;
}

abstract Bare(Int) {}

class P {
	public function new(x:Int, y:Int) {}
}

class Opt {
	public function new(x:Int, ?y:Int) {}
}

class Rest {
	public function new(x:Int, ...more:Int) {}
}

class Child extends P {}

class G<T> {
	public function new(v:T) {}
}

class GC<T> extends G<T> {}
class NoCtor {}
class NoCtorChild extends NoCtor {}
interface IFace {}

extern class Ext {
	@:overload(function(a:Int, b:Int):Void {})
	public function new(a:String);
}

class Shown {
	public function new(x:Int, f:Int->Void, g:(Int, String) -> Bool, h:() -> Void, a:{a:Int, b:String}, z:Int = 2, ?o:Int, k:(Int->Void)->Int) {}
}

class NoArg {
	public function new() {}
}

class Pair2<T> {
	public function new(v:T, w:T) {}
}

class Q {
	public function new(a:P, b:Int) {}
}

typedef S1 = {x:Int};
typedef S2 = {y:Int};

class Holder<T> {
	public function new() {}
}

@:generic class Const<@:const T> {
	public function new() {}
}

@:generic class Const2<@:const A, @:const B> {
	public function new() {}
}

class One<T> {
	public function new() {}
}

@:genericBuild(ArityMacros.anyArguments())
class Multi<Rest> {}

@:genericBuild(ArityMacros.anyArguments())
class TwoBuilt<A, B> {}

@:genericBuild(ArityMacros.anyArguments())
class Lead<B, Rest> {}

@:genericBuild(ArityMacros.anyArguments())
class Tail<Rest, B> {}

@:genericBuild(ArityMacros.anyArguments())
class Mid<A, Rest, B> {}

@:genericBuild(ArityMacros.anyArguments())
class DefaultBeforeRest<A, B = Int, Rest> {}

@:genericBuild(ArityMacros.anyArguments())
class DefaultAfterRest<A, Rest, C = Int> {}

class NullablePair<T> {
	public function new(v:Null<T>, w:T) {}
}

@:build(ArityMacros.addConstructor())
class Built {}

@:autoBuild(ArityMacros.addConstructor())
class AutoBase {}

class AutoChild extends AutoBase {}
