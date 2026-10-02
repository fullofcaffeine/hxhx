/** Separate generic owners prove that equal parameter names do not imply equal identities. */
class First<T> {}

/** This owner's T must survive substitutions belonging to First. */
class Second<T> {}

/** A compound type checks that substitution reaches a record field. */
typedef Box<T> = {value:T};
