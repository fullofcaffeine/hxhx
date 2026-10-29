/** An omitted constructor must forward inherited defaults. */
class DefaultDerived extends Base {
	public var extra:Int = Base.mark("default-field", 2);
}
