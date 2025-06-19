module player
import net


pub struct PlayerList {
pub mut:
	players []Player
}

pub fn PlayerList.new() PlayerList {
	return PlayerList{
		players: []Player{}
	}
}

pub fn (mut pl PlayerList) add_player(plr Player) {
	pl.players << plr
}

pub fn (mut pl PlayerList) remove_player(player_id i8) {
	for i, plr in pl.players {
		if plr.id == player_id {
			pl.players.delete(i)
			return
		}
	}
}

pub fn (pl PlayerList) get_player(player_id i8) ?Player {
	for plr in pl.players {
		if plr.id == player_id {
			return plr
		}
	}

	return none
}

pub fn (pl PlayerList) get_player_by_socket(socket &net.TcpConn) ?Player {
	for plr in pl.players {
		if plr.socket == socket {
			return plr
		}
	}

	return none
}

pub fn (pl PlayerList) get_all_players() []Player {
	return pl.players.clone()
}

pub fn (pl PlayerList) get_all_players_except(player_id i8) []Player {
	mut filtered_players := []Player{}
	for plr in pl.players {
		if plr.id != player_id {
			filtered_players << plr
		}
	}
	return filtered_players
}

pub fn (pl PlayerList) count() int {
	return pl.players.len
}

pub fn (pl PlayerList) set_player_position(player_id i8, x f32, y f32, z f32) ! {
	mut plr := pl.get_player(player_id) or {
		return error('Player with ID $player_id not found')
	}

	plr.set_position(x, y, z)
}

pub fn (pl PlayerList) set_player_orientation(player_id i8, pitch u8, yaw u8) ! {
	mut plr := pl.get_player(player_id) or {
		return error('Player with ID $player_id not found')
	}

	plr.set_orientation(pitch, yaw)
}

pub fn (pl PlayerList) set_player_op_level(player_id i8, op u8) ! {
	mut plr := pl.get_player(player_id) or {
		return error('Player with ID $player_id not found')
	}

	plr.set_op_level(op)
}

pub fn (pl PlayerList) get_player_username(player_id i8) ?string {
	plr := pl.get_player(player_id) or {
		return none
	}

	return plr.get_username()
}

pub fn (pl PlayerList) get_player_id(plr Player) i8 {
	return plr.get_id()
}

pub fn (pl PlayerList) get_player_x(player_id i8) !f32 {
	mut plr := pl.get_player(player_id) or {
		return error('Player with ID $player_id not found')
	}

	return plr.x
}

pub fn (pl PlayerList) get_player_y(player_id i8) !f32 {
	mut plr := pl.get_player(player_id) or {
		return error('Player with ID $player_id not found')
	}

	return plr.y
}

pub fn (pl PlayerList) get_player_z(player_id i8) !f32 {
	mut plr := pl.get_player(player_id) or {
		return error('Player with ID $player_id not found')
	}

	return plr.z
}

pub fn (pl PlayerList) get_player_pitch(player_id i8) !u8 {
	mut plr := pl.get_player(player_id) or {
		return error('Player with ID $player_id not found')
	}

	return plr.pitch
}

pub fn (pl PlayerList) get_player_yaw(player_id i8) !u8 {
	mut plr := pl.get_player(player_id) or {
		return error('Player with ID $player_id not found')
	}

	return plr.yaw
}