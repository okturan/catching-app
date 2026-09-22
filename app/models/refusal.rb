# A request the app declines on purpose, with a message written for the
# person who made it. Controllers show the message and move on; any other
# exception is a bug, and is left to look like one.
class Refusal < StandardError; end
