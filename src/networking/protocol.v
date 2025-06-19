module networking


pub fn get_protocol_version() u8 {
	return 0x07
}

pub enum C2S_PacketType as u8{
	player_identification = 0x00
	set_block = 0x05
	player_position_and_orientation = 0x08
	message = 0x0D
}

pub enum S2C_PacketType as u8{
	server_identification = 0x00
	ping = 0x01
	level_initialize = 0x02
	level_data_chunk = 0x03
	level_finalize = 0x04
	set_block = 0x06
	spawn_player = 0x07
	set_player_position_and_orientation = 0x08
	position_and_orientation_update = 0x09
	position_update = 0x0A
	orientation_update = 0x0B
	despawn_player = 0x0C
	message = 0x0D
	player_disconnect = 0x0E
	update_user_type = 0x0F
}