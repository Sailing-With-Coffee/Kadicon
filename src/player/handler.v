module player
import rand
import net


pub struct Player {
pub mut:
	id i8
	username string
	verification_key string
	op u8

	x f32
	y f32
	z f32

	pitch u8
	yaw u8

	socket &net.TcpConn
}

pub fn Player.new(name string, key string, sock &net.TcpConn) Player {
	new_id := i8(rand.int_in_range(0, 127) or { panic('Failed to generate player ID') })

	return Player{
		id: new_id,
		username: name,
		verification_key: key,
		op: 0x00, // Default operator level
		x: 0.0,
		y: 0.0,
		z: 0.0,
		pitch: 0,
		yaw: 0,
		socket: sock,
	}
}


pub fn (mut p Player) set_position(x f32, y f32, z f32) {
	p.x = x
	p.y = y
	p.z = z
}

pub fn (mut p Player) set_orientation(pitch u8, yaw u8) {
	p.pitch = pitch
	p.yaw = yaw
}

pub fn (mut p Player) set_op_level(op u8) {
	p.op = op
}

pub fn (p Player) get_username() string {
	return p.username
}

pub fn (p Player) get_id() i8 {
	return p.id
}

pub fn (p Player) get_x() f32 {
	return p.x
}

pub fn (p Player) get_y() f32 {
	return p.y
}

pub fn (p Player) get_z() f32 {
	return p.z
}

pub fn (p Player) get_pitch() u8 {
	return p.pitch
}

pub fn (p Player) get_yaw() u8 {
	return p.yaw
}