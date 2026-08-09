The default contract is that raw literal chunks cannot name private runtime
modules. Structured interpolated expressions retain their own checked
authority through a raw-boundary record. If a real public use case requires a
private helper, add an explicit checked placeholder tied to a raw-boundary
occurrence and requirement; never grant broad namespace access.
