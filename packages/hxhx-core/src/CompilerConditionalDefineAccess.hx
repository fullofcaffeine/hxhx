/** How a conditional expression consulted one compile-time definition. **/
enum CompilerConditionalDefineAccess {
	/** Only whether the definition exists can affect the result. **/
	Presence;

	/** The definition's value can affect the result. **/
	Value;
}
