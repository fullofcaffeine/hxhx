class Vector(Array):
    def __init__(self, length):
        super().__init__([None] * max(0, int(length)))

    @staticmethod
    def fromArrayCopy(array):
        vector = Vector(0)
        vector.extend(list(array))
        return vector
