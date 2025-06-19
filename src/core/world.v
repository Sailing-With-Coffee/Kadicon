module core


pub struct World {
pub mut:
	x_size int
	y_size int
	z_size int

	blocks []u8
}


pub fn World.new(xs int, ys int, zs int) World {
	return World{
		x_size: xs
		y_size: ys
		z_size: zs

		blocks: []u8{len: int(xs * ys * zs)}
	}
}

pub fn (mut w World) generate_world() {
	for x in 0 .. w.x_size {
		for z in 0 .. w.z_size {
			for y in 0 .. w.y_size {
				idx := x + z * w.x_size + y * w.x_size * w.z_size

				if y < 10 {
					w.blocks[idx] = 0x03 // Dirt
				} else if y == 10 {
					w.blocks[idx] = 0x02 // Grass
				} else {
					w.blocks[idx] = 0x00 // Air
				}
			}
		}
    }
}

pub fn (mut w World) set_block(x int, y int, z int, block_type u8) ! {
	if x >= w.x_size || y >= w.y_size || z >= w.z_size {
		return error('Block coordinates out of bounds !')
	}

	idx := x + z * w.x_size + y * w.x_size * w.z_size
	w.blocks[idx] = block_type
}

pub fn (w World) get_block(x int, y int, z int) !u8 {
	if x >= w.x_size || y >= w.y_size || z >= w.z_size {
		return error('Block coordinates out of bounds !')
	}

	idx := x + z * w.x_size + y * w.x_size * w.z_size
	return w.blocks[idx]
}

pub fn (w World) get_data() []u8 {
	// Returns the bytes representation of the world prefixed with its length as a 4 bytes big endian integer
	mut data := []u8{len: 4 + w.blocks.len}

	len := u32(w.blocks.len)
	data[0] = u8((len >> 24) & 0xFF)
	data[1] = u8((len >> 16) & 0xFF)
	data[2] = u8((len >> 8) & 0xFF)
	data[3] = u8(len & 0xFF)
	
	for i in 0 .. w.blocks.len {
		data[4 + i] = w.blocks[i]
	}

	return data
}