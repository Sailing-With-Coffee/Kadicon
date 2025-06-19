module utils
import os


pub struct Config {
pub mut:
	server_name string
	motd string
	port int
}

pub fn Config.load() Config {
	// Load config file at server.properties
	config_path := os.join_path(os.getwd(), 'server.properties')
	if !os.exists(config_path) {
		// If the config file does not exist, create a default one
		default_config := Config{
			server_name: 'A Minecraft Server',
			motd: 'Powered by Kadicon',
			port: 25565,
		}

		/*
		Comments are prefixed with a # character
		Properties are set like name=value
		*/

		os.write_file(config_path, '# Default Server Configuration\n' +
			'server_name=${default_config.server_name}\n' +
			'motd=${default_config.motd}\n' +
			'port=${default_config.port}\n') or {
			panic('Failed to create default config file: $err')
		}
	}

	// Read the config file
	config_file := os.read_file(config_path) or {
		panic('Failed to read config file: $err')
	}

	// Parse the config file, line by line
	mut config := Config{}
	for line in config_file.split('\n') {
		if line.trim_space() == '' || line.starts_with('#') {
			continue
		}
		key_value := line.split('=')
		if key_value.len != 2 {
			continue
		}
		key := key_value[0].trim_space()
		value := key_value[1].trim_space()
		match key {
			'server_name' {
				config.server_name = value
			}
			'motd' {
				config.motd = value
			}
			'port' {
				config.port = value.int()
			}
			else {}
		}
	}

	return config
}
