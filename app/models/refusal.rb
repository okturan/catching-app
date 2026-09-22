# A request declined on purpose, with a message for the person who made it.
# Any other exception is a bug, and is left to look like one.
class Refusal < StandardError; end
