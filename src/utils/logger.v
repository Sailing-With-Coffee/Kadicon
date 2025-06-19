module utils
import time


pub enum LogLevel as u8 {
	debug = 0
	info = 1
	warning = 2
	error = 3
}

pub struct Logger {}

pub fn Logger.new() Logger {
	return Logger{}
}

pub fn (l Logger) log(level LogLevel, msg string) {
	timestamp := time.now().format_ss()
	formatted := '[$timestamp] [${level.str().to_upper()}] $msg\n'

	print(formatted)
}