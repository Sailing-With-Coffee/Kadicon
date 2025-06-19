module networking
import math


pub struct Packet {
pub mut:
 	packet_type u8
	data []u8
}


// Unsigned byte (0 to 255)
pub fn (mut p Packet) append_byte(value u8) Packet {
	mut new_data := p.data.clone()
	new_data << value

	return Packet{
		packet_type: p.packet_type,
		data: new_data
	}
}

pub fn (mut p Packet) read_byte() !u8 {
	if p.data.len < 1 {
		return error('Not enough data to read a byte')
	}

	value := p.data[0]
	p.data = p.data[1..] // Remove the first byte after reading
	return value
}

// Signed byte (-128 to 127)
pub fn (mut p Packet) append_signed_byte(value i8) Packet {
	mut new_data := p.data.clone()
	new_data << u8(value & 0xFF)

	return Packet{
		packet_type: p.packet_type,
		data: new_data
	}
}

pub fn (mut p Packet) read_signed_byte() !i8 {
	if p.data.len < 1 {
		return error('Not enough data to read a signed byte')
	}

	value := i8(p.data[0])
	p.data = p.data[1..] // Remove the first byte after reading
	return value
}

// Signed fixed-point, 5 fractional bits (-4 to 3.96875)
pub fn (mut p Packet) append_signed_fixed_byte(value f32) Packet {
	if value < -4.0 || value > 3.96875 {
		panic('Value out of range for signed fixed-point: $value')
	}

	mut new_data := p.data.clone()
	mut fixed_value := i8(int(math.round(value * 32.0)))
	new_data << u8(fixed_value & 0xFF)

	return Packet{
		packet_type: p.packet_type,
		data: new_data
	}
}

pub fn (mut p Packet) read_signed_fixed_byte() !f32 {
	if p.data.len < 1 {
		return error('Not enough data to read a signed fixed-point byte')
	}

	value := i8(p.data[0])
	p.data = p.data[1..] // Remove the first byte after reading
	return f32(value) / 32.0 // Convert back to float
}

// Signed integer (-32768 to 32767)
pub fn (mut p Packet) append_short(value i16) Packet {
	mut new_data := p.data.clone()
	new_data << u8(value >> 8)
	new_data << u8(value & 0xFF)

	return Packet{
		packet_type: p.packet_type,
		data: new_data
	}
}

pub fn (mut p Packet) read_short() !i16 {
	if p.data.len < 2 {
		return error('Not enough data to read a short')
	}

	value := i16((u16(p.data[0]) << 8) | u16(p.data[1]))
	p.data = p.data[2..] // Remove the first two bytes after reading
	return value
}

// Signed fixed-point, 5 fractional bits (-1024 to 1023.96875)
pub fn (mut p Packet) append_signed_fixed_short(value f32) Packet {
	if value < -1024.0 || value > 1023.96875 {
		panic('Value out of range for signed fixed-point: $value')
	}

	mut new_data := p.data.clone()
	mut fixed_value := i16(int(math.round(value * 32.0)))
	new_data << u8(fixed_value >> 8)
	new_data << u8(fixed_value & 0xFF)

	return Packet{
		packet_type: p.packet_type,
		data: new_data
	}
}

pub fn (mut p Packet) read_signed_fixed_short() !f32 {
	if p.data.len < 2 {
		return error('Not enough data to read a signed fixed-point short')
	}

	value := i16((u16(p.data[0]) << 8) | u16(p.data[1]))
	p.data = p.data[2..] // Remove the first two bytes after reading
	return f32(value) / 32.0 // Convert back to float
}

// UTF-8 encoded string padded with spaces (0x20), length is always 64
pub fn (mut p Packet) append_string(value string) Packet {
	if value.len > 64 {
		panic('String too long for packet: $value')
	}

	mut padded := value.bytes()
	padded << u8(0x20)

	for _ in padded.len .. 64 {
		padded << u8(0x20)
	}

	mut new_data := p.data.clone()
	new_data << padded

	return Packet{
		packet_type: p.packet_type,
		data: new_data
	}
}

pub fn (mut p Packet) read_string() !string {
	if p.data.len < 64 {
		return error('Not enough data to read a string')
	}

	mut value := []u8{len: 64}
	for i in 0 .. 64 {
		value[i] = p.data[i]
	}

	p.data = p.data[64..] // Remove the first 64 bytes after reading
	return value.bytestr().trim_space()
}

// Level binary data padded with null bytes (0x00) only if length is less than 1024
pub fn (mut p Packet) append_level_data(value []u8) Packet {
	if value.len > 1024 {
		panic('Level binary data too long for packet: ${value.len} bytes')
	}

	mut padded := value.clone()
	for _ in padded.len .. 1024 {
		padded << u8(0x00)
	}

	mut new_data := p.data.clone()
	new_data << padded

	return Packet{
		packet_type: p.packet_type,
		data: new_data
	}
}


// Convert the packet to a byte array for sending over the network
pub fn (mut p Packet) to_bytes() []u8 {
	mut bytes := [p.packet_type]
	bytes << p.data
	return bytes
}

pub fn Packet.from_bytes(data []u8) !Packet {
	if data.len < 1 {
		return error('Packet data is too short !')
	}

	packet_type := data[0]
	if packet_type > 255 {
		return error('Invalid packet type: $packet_type')
	}

	mut packet_data := []u8{len: data.len - 1}
	for i in 1 .. data.len {
		packet_data[i - 1] = data[i]
	}

	return Packet{
		packet_type: packet_type,
		data: packet_data
	}
}