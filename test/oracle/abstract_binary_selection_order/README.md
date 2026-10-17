# Abstract binary operator selection

These independently authored cases compare operator selection with Haxe 4.3.7.
Earlier applicable declarations win, including equal signatures. The left
abstract is searched before the right abstract. A commutative declaration can
reverse its arguments. An incompatible compound result must fail instead of
selecting a later declaration with a convenient result type.

Run the complete contract from the repository root:

```sh
haxe test/m14_abstract_binary_selection_order_test.hxml
```

Each small program runs with upstream Haxe before the local binding assertion.
The native cases also compile and run with the C++ target. They check the
selected operator, operand order, single evaluation, and typed input immutability.
The method-effects case covers input and output conversion methods, reversed
arguments, compound result conversion, bodyless operators, and inline receiver
updates. A throwing conversion must stop before the next operand runs. These
cases load their real dependencies, including the exception providers.
The existing shared abstract binary test includes this contract.
