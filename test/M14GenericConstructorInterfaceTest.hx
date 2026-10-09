/** Applied interface arguments constrain constructor inference before publication. */
class M14GenericConstructorInterfaceTest {
	static function main():Void {
		M14GenericConstructorSelfTest.check("InterfaceCases", "interface\n");
		M14GenericConstructorSelfTest.check("InheritedInterfaceCases", "interface\n", false);
		M14GenericConstructorOverloadTest.reject("InterfaceConflictCases", "String should be Int");
	}
}
