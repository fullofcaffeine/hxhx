class DateTools:
    @staticmethod
    def seconds(n):
        return (n * 1000.0)

    @staticmethod
    def minutes(n):
        return (n * 60.0 * 1000.0)

    @staticmethod
    def hours(n):
        return (n * 60.0 * 60.0 * 1000.0)

    @staticmethod
    def days(n):
        return (n * 24.0 * 60.0 * 60.0 * 1000.0)
