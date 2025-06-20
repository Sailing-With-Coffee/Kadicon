module core
import noise as fnl
import math


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

pub fn (mut w World) generate_flat_world() {
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

pub fn (mut w World) generate_world(seed int) {
	mut fast := fnl.new_noise()
	fast.set_seed(seed)

	for x in 0 .. w.x_size {
		for z in 0 .. w.z_size {
			// Increase frequency for more variation, reduce flat areas
			base := fast.get_noise_2(f64(x) * 0.12, f64(z) * 0.12)
			detail := fast.get_noise_2(f64(x) * 0.36, f64(z) * 0.36) * 0.5
			fine := fast.get_noise_2(f64(x) * 0.9, f64(z) * 0.9) * 0.2
			ridge := f64(math.abs(fast.get_noise_2(f64(x) * 0.24, f64(z) * 0.24))) * 0.4
			mut noise_val := base + detail + fine + ridge
			// Clamp noise_val to [-1, 1]
			noise_val = if noise_val < -1 { -1 } else if noise_val > 1 { 1 } else { noise_val }
			// Map noise [-1,1] to height range, e.g. 2..(w.y_size-2)
			min_h := 2
			max_h := w.y_size - 2
			h := int(((noise_val + 1) / 2) * f64(max_h - min_h)) + min_h
			for y in 0 .. w.y_size {
				idx := x + z * w.x_size + y * w.x_size * w.z_size
				if y < h - 2 {
					w.blocks[idx] = 0x03 // Dirt below surface
				} else if y == h - 2 || y == h - 1 {
					w.blocks[idx] = 0x02 // Grass at surface
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