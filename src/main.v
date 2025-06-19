import net
import io
import compress.gzip
import networking
import player
import utils


fn main() {
    logger := utils.Logger.new()
    logger.log(utils.LogLevel.info, 'Welcome to Kadicon !')

    // Listen on TCP 25565
    mut bind_addr := '0.0.0.0:25565'
    mut server := net.listen_tcp(.ip, bind_addr) or {
        logger.log(utils.LogLevel.error, 'Failed to bind to $bind_addr !')
        return
    }

    logger.log(utils.LogLevel.info, 'Listening on $bind_addr')

    mut player_list := player.PlayerList.new()

    for {
		mut socket := server.accept()!
        spawn handle_client(mut socket, mut &player_list)
	}
}

fn handle_client(mut socket net.TcpConn, mut player_list &player.PlayerList) {
	defer {
		socket.close() or { panic(err) }
	}

    mut send_ping := false
	client_addr := socket.peer_addr() or { return }
	logger := utils.Logger.new()
    logger.log(utils.LogLevel.info, 'New connection from ${client_addr}')

	mut reader := io.new_buffered_reader(reader: socket)
	defer {
		unsafe {
			reader.free()
		}
	}

	for {
		mut available_data := []u8{len: 1024}
		len := reader.read(mut available_data) or { return }

        mut packet := networking.Packet.from_bytes(available_data[..len]) or {
            logger.log(utils.LogLevel.error, 'Failed to parse packet: $err')
            return
        }

        mut packet_type := networking.C2S_PacketType.from(packet.packet_type) or {
            logger.log(utils.LogLevel.error, 'Invalid packet type: ${packet.packet_type}')
            return
        }

        
        match packet_type {
            .player_identification {
                logger.log(utils.LogLevel.info, 'Player identification packet received')

                protocol_version := packet.read_byte() or { logger.log(utils.LogLevel.error, 'Failed to read protocol version: $err'); return }
                username := packet.read_string() or { logger.log(utils.LogLevel.error, 'Failed to read username: $err'); return }
                verification_key := packet.read_string() or { logger.log(utils.LogLevel.error, 'Failed to read verification key: $err'); return }

                if protocol_version != networking.get_protocol_version() {
                    // Disconnect the client if the protocol version does not match
                    logger.log(utils.LogLevel.warning, 'Protocol version mismatch: expected ${networking.get_protocol_version()}, got $protocol_version')
                    socket.close() or { panic(err) }
                    return
                }


                mut new_player := player.Player.new(username, verification_key, socket)
                player_list.add_player(new_player)


                mut response_packet := networking.Packet{
                    packet_type: u8(networking.S2C_PacketType.server_identification)
                }

                response_packet = response_packet.append_byte(networking.get_protocol_version())
                response_packet = response_packet.append_string('A Minecraft Server')
                response_packet = response_packet.append_string('Powered by Kadicon')
                response_packet = response_packet.append_byte(new_player.op)

                socket.write(response_packet.to_bytes()) or {
                    logger.log(utils.LogLevel.error, 'Failed to send server identification packet: $err')
                    return
                }


                mut level_initialize_packet := networking.Packet{
                    packet_type: u8(networking.S2C_PacketType.level_initialize)
                }

                socket.write(level_initialize_packet.to_bytes()) or {
                    logger.log(utils.LogLevel.error, 'Failed to send level initialize packet: $err')
                    return
                }


                mut dummy_world := []u8{len: 4 + 256*64*256}
                // add big endian int length of the world data at the start

                dummy_world[0] = 0x00
                dummy_world[1] = 0x40
                dummy_world[2] = 0x00
                dummy_world[3] = 0x00

                for x in 0 .. 256 {
                    for z in 0 .. 256 {
                        for y in 0 .. 64 {
                            if y < 10 {
                                dummy_world[4 + x + z * 256 + y * 256 * 256] = 0x03 // Dirt
                            } else if y == 10 {
                                dummy_world[4 + x + z * 256 + y * 256 * 256] = 0x02 // Grass
                            } else {
                                dummy_world[4 + x + z * 256 + y * 256 * 256] = 0x00 // Air
                            }
                        }
                    }
                }

                // Compress the world data using pure gzip no headers or anything
                mut compressed_world := gzip.compress(dummy_world) or {
                    logger.log(utils.LogLevel.error, 'Failed to compress world data: $err')
                    return
                }

                // so basically we use compressed_world length, subtract 1024 every in a loop where we get the bytes corresponding and send them
                mut offset := 0
                chunk_size := 1024
                for offset < compressed_world.len {
                    mut level_data_chunk_packet := networking.Packet{
                        packet_type: u8(networking.S2C_PacketType.level_data_chunk)
                    }

                    // Calculate the size of the chunk to send
                    mut chunk_length := compressed_world.len - offset
                    if chunk_length > chunk_size {
                        chunk_length = chunk_size
                    }

                    level_data_chunk_packet = level_data_chunk_packet.append_short(i16(chunk_length))
                    level_data_chunk_packet = level_data_chunk_packet.append_level_data(compressed_world[offset .. offset + chunk_length])
                    level_data_chunk_packet = level_data_chunk_packet.append_byte(u8((offset + chunk_length) * 100 / compressed_world.len))

                    socket.write(level_data_chunk_packet.to_bytes()) or {
                        logger.log(utils.LogLevel.error, 'Failed to send level data chunk packet: $err')
                        return
                    }

                    offset += chunk_length
                }


                mut level_finalize_packet := networking.Packet{
                    packet_type: u8(networking.S2C_PacketType.level_finalize)
                }

                level_finalize_packet = level_finalize_packet.append_short(256)
                level_finalize_packet = level_finalize_packet.append_short(64)
                level_finalize_packet = level_finalize_packet.append_short(256)

                socket.write(level_finalize_packet.to_bytes()) or {
                    logger.log(utils.LogLevel.error, 'Failed to send level finalize packet: $err')
                    return
                }


                player_list.set_player_position(new_player.id, 128.0, 15.0, 128.0) or {
                    logger.log(utils.LogLevel.error, 'Failed to set player position: $err')
                    return
                }

                mut position_update_packet := networking.Packet{
                    packet_type: u8(networking.S2C_PacketType.set_player_position_and_orientation)
                }

                position_update_packet = position_update_packet.append_signed_byte(-1)
                position_update_packet = position_update_packet.append_signed_fixed_short(128)
                position_update_packet = position_update_packet.append_signed_fixed_short(15)
                position_update_packet = position_update_packet.append_signed_fixed_short(128)
                position_update_packet = position_update_packet.append_byte(0)
                position_update_packet = position_update_packet.append_byte(0)

                socket.write(position_update_packet.to_bytes()) or {
                    logger.log(utils.LogLevel.error, 'Failed to send position update packet: $err')
                    return
                }


                mut welcome_message_packet := networking.Packet{
                    packet_type: u8(networking.S2C_PacketType.message)
                }

                welcome_message_packet = welcome_message_packet.append_signed_byte(-1)
                welcome_message_packet = welcome_message_packet.append_string('Welcome, $username!')

                socket.write(welcome_message_packet.to_bytes()) or {
                    logger.log(utils.LogLevel.error, 'Failed to send welcome message packet: $err')
                    return
                }


                send_ping = true
            }

            .set_block {
                logger.log(utils.LogLevel.info, 'Set block packet received')
            }

            .player_position_and_orientation {
                mut affected_player_id := packet.read_signed_byte() or { logger.log(utils.LogLevel.error, 'Failed to read affected player ID: $err') return }
                new_x := packet.read_signed_fixed_short() or { logger.log(utils.LogLevel.error, 'Failed to read new X position: $err') return }
                new_y := packet.read_signed_fixed_short() or { logger.log(utils.LogLevel.error, 'Failed to read new Y position: $err') return }
                new_z := packet.read_signed_fixed_short() or { logger.log(utils.LogLevel.error, 'Failed to read new Z position: $err') return }
                new_yaw := packet.read_byte() or { logger.log(utils.LogLevel.error, 'Failed to read new yaw: $err') return }
                new_pitch := packet.read_byte() or { logger.log(utils.LogLevel.error, 'Failed to read new pitch: $err') return }

                real_affected_player := player_list.get_player_by_socket(socket) or {
                    logger.log(utils.LogLevel.error, 'Player not found for socket: $err')
                    return
                }
                affected_player_id = player_list.get_player_id(real_affected_player)

                player_list.set_player_position(affected_player_id, new_x, new_y, new_z) or {
                    logger.log(utils.LogLevel.error, 'Failed to set player position: $err')
                    return
                }

                player_list.set_player_orientation(affected_player_id, new_pitch, new_yaw) or {
                    logger.log(utils.LogLevel.error, 'Failed to set player orientation: $err')
                    return
                }
            }

            .message {
                logger.log(utils.LogLevel.info, 'Message packet received')
            }
        }

        if send_ping {
            mut ping_packet := networking.Packet{
                packet_type: u8(networking.S2C_PacketType.ping)
            }

            socket.write(ping_packet.to_bytes()) or {
                logger.log(utils.LogLevel.error, 'Failed to send ping packet: $err')
                return
            }
        }
	}
}