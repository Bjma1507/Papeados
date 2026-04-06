extends Node
class_name Validator

'''
Helper class with static methods to validate server authority and other common checks across the game.
This class is not meant to be instantiated. Just call its static methods from anywhere in the code.
Ensure server authority before performing actions that should only be done on the server.

Args:
	node (Node): The node from which the method is being called. Used to check multiplayer authority 

Returns:
	bool: True if the node has server authority, false otherwise. Also prints an error message if the check fails.
'''
static func ensure_server(node: Node) -> bool:
	if not node.multiplayer.is_server():
		push_error("[%s] Esta acción solo puede ejecutarse en el servidor." % node.name)
		return false
	return true
