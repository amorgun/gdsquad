class_name Logging extends Node

enum LogLevel {
	DEBUG,
	INFO,
	WARNING,
	ERROR,
}
var current_level := LogLevel.DEBUG

signal message_added(text: String, level: LogLevel)

func log(level: LogLevel, fmt: String, args: Array = []) -> void:
	if current_level <= level:
		message_added.emit(fmt % args, level)

func debug(fmt: String, args: Array = []) -> void: self.log(LogLevel.DEBUG, fmt, args)
func info(fmt: String, args: Array = []) -> void: self.log(LogLevel.INFO, fmt, args)
func warning(fmt: String, args: Array = []) -> void: self.log(LogLevel.WARNING, fmt, args)
func error(fmt: String, args: Array = []) -> void: self.log(LogLevel.ERROR, fmt, args)
