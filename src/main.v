module main
import net
import io
import compress.gzip
import networking
import player
import core
import utils


fn main() {
    logger := utils.Logger.new()
    logger.log(utils.LogLevel.info, 'Welcome to Kadicon !')

    config := utils.Config.load()
    logger.log(utils.LogLevel.info, 'Server Name: ${config.server_name}')
    logger.log(utils.LogLevel.info, 'MOTD: ${config.motd}')

    // Listen on TCP
    mut bind_addr := '0.0.0.0:${config.port}'
    mut server := net.listen_tcp(.ip, bind_addr) or {
        logger.log(utils.LogLevel.error, 'Failed to bind to $bind_addr !')
        return
    }

    logger.log(utils.LogLevel.info, 'Listening on $bind_addr')

    mut player_list := player.PlayerList.new()
    mut world := core.World.new(256, 64, 256)
    
    if config.flat_world {
        world.generate_flat_world()
    } else {
        world.generate_world(config.seed)
    }


    for {
		mut socket := server.accept()!
        spawn handle_client(mut socket, mut &player_list, mut &world, &config)
	}
}

fn handle_client(mut socket net.TcpConn, mut player_list &player.PlayerList, mut world &core.World, config &utils.Config) {
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

    mut data_queue := []u8

	for {
		mut available_data := []u8{len: 1024}
		len := reader.read(mut available_data) or { return }
        data_queue << available_data[..len]

        for {
            packet_id := data_queue[0]
            mut packet_size := 0
            mut packet_type := networking.C2S_PacketType.from(packet_id) or {
                logger.log(utils.LogLevel.error, 'Invalid packet type: ${packet_id}')
                return
            }

            match packet_type {
                .player_identification {
                    packet_size = 131
                }

                .set_block {
                    packet_size = 9
                }

                .player_position_and_orientation {
                    packet_size = 10
                }

                .message {
                    packet_size = 66
                }
            }

            if data_queue.len < packet_size {
                break
            }

            // Resize packet data to the expected size
            mut packet_data := data_queue.clone()
            packet_data = packet_data[..packet_size]
            data_queue = data_queue[packet_size..] // Remove the processed packet data


            mut packet := networking.Packet.from_bytes(packet_data) or {
                logger.log(utils.LogLevel.error, 'Failed to parse packet: $err')
                return
            }


            
            match packet_type {
                .player_identification {
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
                    response_packet = response_packet.append_string(config.server_name)
                    response_packet = response_packet.append_string(config.motd)
                    response_packet = response_packet.append_byte(new_player.op)

                    socket.write(response_packet.to_bytes()) or {
                        logger.log(utils.LogLevel.warning, 'Failed to send server identification packet: $err')
                        disconnect_player(mut socket, mut player_list)
                        return
                    }


                    mut level_initialize_packet := networking.Packet{
                        packet_type: u8(networking.S2C_PacketType.level_initialize)
                    }

                    socket.write(level_initialize_packet.to_bytes()) or {
                        logger.log(utils.LogLevel.warning, 'Failed to send level initialize packet: $err')
                        disconnect_player(mut socket, mut player_list)
                        return
                    }


                    // Compress the world data using pure gzip no headers or anything
                    mut compressed_world := gzip.compress(world.get_data()) or {
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
                            logger.log(utils.LogLevel.warning, 'Failed to send level data chunk packet: $err')
                            disconnect_player(mut socket, mut player_list)
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
                        logger.log(utils.LogLevel.warning, 'Failed to send level finalize packet: $err')
                        disconnect_player(mut socket, mut player_list)
                        return
                    }


                    player_list.set_player_position(new_player.id, 128.0, 30.0, 128.0) or {
                        logger.log(utils.LogLevel.warning, 'Failed to set player position: $err')
                        disconnect_player(mut socket, mut player_list)
                        return
                    }

                    mut position_update_packet := networking.Packet{
                        packet_type: u8(networking.S2C_PacketType.set_player_position_and_orientation)
                    }

                    position_update_packet = position_update_packet.append_signed_byte(-1)
                    position_update_packet = position_update_packet.append_signed_fixed_short(128)
                    position_update_packet = position_update_packet.append_signed_fixed_short(30)
                    position_update_packet = position_update_packet.append_signed_fixed_short(128)
                    position_update_packet = position_update_packet.append_byte(0)
                    position_update_packet = position_update_packet.append_byte(0)

                    socket.write(position_update_packet.to_bytes()) or {
                        logger.log(utils.LogLevel.warning, 'Failed to send position update packet: $err')
                        disconnect_player(mut socket, mut player_list)
                        return
                    }


                    mut welcome_message_packet := networking.Packet{
                        packet_type: u8(networking.S2C_PacketType.message)
                    }

                    welcome_message_packet = welcome_message_packet.append_signed_byte(-1)
                    welcome_message_packet = welcome_message_packet.append_string('$username joined the game')

                    mut all_players := player_list.get_all_players()
                    for mut player in all_players {
                        player.socket.write(welcome_message_packet.to_bytes()) or {
                            logger.log(utils.LogLevel.warning, 'Failed to send welcome message packet: $err')
                            disconnect_player(mut player.socket, mut player_list)
                            continue
                        }
                    }

                    logger.log(utils.LogLevel.info, '$username joined the game')


                    mut spawn_player_packet := networking.Packet{
                        packet_type: u8(networking.S2C_PacketType.spawn_player)
                    }

                    spawn_player_packet = spawn_player_packet.append_signed_byte(new_player.id)
                    spawn_player_packet = spawn_player_packet.append_string(new_player.username)
                    spawn_player_packet = spawn_player_packet.append_signed_fixed_short(new_player.x)
                    spawn_player_packet = spawn_player_packet.append_signed_fixed_short(new_player.y)
                    spawn_player_packet = spawn_player_packet.append_signed_fixed_short(new_player.z)
                    spawn_player_packet = spawn_player_packet.append_byte(new_player.yaw)
                    spawn_player_packet = spawn_player_packet.append_byte(new_player.pitch)

                    mut other_players := player_list.get_all_players_except(new_player.id)
                    for mut other_player in other_players {
                        other_player.socket.write(spawn_player_packet.to_bytes()) or {
                            logger.log(utils.LogLevel.warning, 'Failed to send spawn player packet to player ${other_player.username}: $err')
                            disconnect_player(mut other_player.socket, mut player_list)
                            continue
                        }

                        mut spawn_other_player_packet := networking.Packet{
                            packet_type: u8(networking.S2C_PacketType.spawn_player)
                        }

                        spawn_other_player_packet = spawn_other_player_packet.append_signed_byte(other_player.id)
                        spawn_other_player_packet = spawn_other_player_packet.append_string(other_player.username)
                        spawn_other_player_packet = spawn_other_player_packet.append_signed_fixed_short(other_player.x)
                        spawn_other_player_packet = spawn_other_player_packet.append_signed_fixed_short(other_player.y)
                        spawn_other_player_packet = spawn_other_player_packet.append_signed_fixed_short(other_player.z)
                        spawn_other_player_packet = spawn_other_player_packet.append_byte(other_player.yaw)
                        spawn_other_player_packet = spawn_other_player_packet.append_byte(other_player.pitch)

                        socket.write(spawn_other_player_packet.to_bytes()) or {
                            logger.log(utils.LogLevel.warning, 'Failed to send spawn other player packet to new player: $err')
                            disconnect_player(mut socket, mut player_list)
                            continue
                        }
                    }


                    send_ping = true
                }

                .set_block {
                    block_x := packet.read_short() or { logger.log(utils.LogLevel.error, 'Failed to read block X: $err') return }
                    block_y := packet.read_short() or { logger.log(utils.LogLevel.error, 'Failed to read block Y: $err') return }
                    block_z := packet.read_short() or { logger.log(utils.LogLevel.error, 'Failed to read block Z: $err') return }
                    action := packet.read_byte() or { logger.log(utils.LogLevel.error, 'Failed to read action: $err') return }
                    mut block_type := packet.read_byte() or { logger.log(utils.LogLevel.error, 'Failed to read block type: $err') return }

                    if action == 0x01 {
                        world.set_block(block_x, block_y, block_z, block_type) or {
                            logger.log(utils.LogLevel.error, 'Failed to set block at ($block_x, $block_y, $block_z): $err')
                            return
                        }
                    } else {
                        world.set_block(block_x, block_y, block_z, 0x00) or {
                            logger.log(utils.LogLevel.error, 'Failed to remove block at ($block_x, $block_y, $block_z): $err')
                            return
                        }

                        block_type = 0x00
                    }


                    mut block_update_packet := networking.Packet{
                        packet_type: u8(networking.S2C_PacketType.set_block)
                    }

                    block_update_packet = block_update_packet.append_short(block_x)
                    block_update_packet = block_update_packet.append_short(block_y)
                    block_update_packet = block_update_packet.append_short(block_z)
                    block_update_packet = block_update_packet.append_byte(block_type)

                    mut all_players := player_list.get_all_players()
                    for mut player in all_players {
                        player.socket.write(block_update_packet.to_bytes()) or {
                            logger.log(utils.LogLevel.warning, 'Failed to send block update packet to player ${player.username}: $err')
                            disconnect_player(mut player.socket, mut player_list)
                            continue
                        }
                    }
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


                    mut position_update_packet := networking.Packet{
                        packet_type: u8(networking.S2C_PacketType.set_player_position_and_orientation)
                    }

                    position_update_packet = position_update_packet.append_signed_byte(affected_player_id)
                    position_update_packet = position_update_packet.append_signed_fixed_short(new_x)
                    position_update_packet = position_update_packet.append_signed_fixed_short(new_y)
                    position_update_packet = position_update_packet.append_signed_fixed_short(new_z)
                    position_update_packet = position_update_packet.append_byte(new_yaw)
                    position_update_packet = position_update_packet.append_byte(new_pitch)

                    mut other_players := player_list.get_all_players_except(real_affected_player.id)
                    for mut other_player in other_players {
                        other_player.socket.write(position_update_packet.to_bytes()) or {
                            logger.log(utils.LogLevel.warning, 'Failed to send position update packet to player ${other_player.username}: $err')
                            disconnect_player(mut other_player.socket, mut player_list)
                            continue
                        }
                    }
                }

                .message {
                    mut sender_id := packet.read_signed_byte() or { logger.log(utils.LogLevel.error, 'Failed to read sender ID: $err'); return }
                    mut message := packet.read_string() or { logger.log(utils.LogLevel.error, 'Failed to read message: $err'); return }
                    logger.log(utils.LogLevel.info, 'Message from player $sender_id: $message')

                    real_affected_player := player_list.get_player_by_socket(socket) or {
                        logger.log(utils.LogLevel.error, 'Player not found for socket: $err')
                        return
                    }
                    sender_id = player_list.get_player_id(real_affected_player)


                    mut message_packet := networking.Packet{
                        packet_type: u8(networking.S2C_PacketType.message)
                    }

                    message_packet = message_packet.append_signed_byte(sender_id)
                    message_packet = message_packet.append_string('$real_affected_player.username: $message')

                    mut all_players := player_list.get_all_players()
                    for mut player in all_players {
                        player.socket.write(message_packet.to_bytes()) or {
                            logger.log(utils.LogLevel.warning, 'Failed to send welcome message packet: $err')
                            disconnect_player(mut player.socket, mut player_list)
                            continue
                        }
                    }
                }
            }

            if send_ping {
                mut ping_packet := networking.Packet{
                    packet_type: u8(networking.S2C_PacketType.ping)
                }

                socket.write(ping_packet.to_bytes()) or {
                    logger.log(utils.LogLevel.warning, 'Failed to send ping packet: $err')
                    disconnect_player(mut socket, mut player_list)
                    return
                }
            }

            break
        }
	}
}

fn disconnect_player(mut socket net.TcpConn, mut player_list &player.PlayerList) {
    if player := player_list.get_player_by_socket(socket) {
        logger := utils.Logger.new()
        logger.log(utils.LogLevel.info, '${player.username} left the game')
        player_list.remove_player(player.id)

        mut disconnect_packet := networking.Packet{
            packet_type: u8(networking.S2C_PacketType.despawn_player)
        }

        disconnect_packet = disconnect_packet.append_signed_byte(player.id)


        mut leave_chat_packet := networking.Packet{
            packet_type: u8(networking.S2C_PacketType.message)
        }

        leave_chat_packet = leave_chat_packet.append_signed_byte(-1)
        leave_chat_packet = leave_chat_packet.append_string('${player.username} left the game')


        mut all_players := player_list.get_all_players()
        for mut other_player in all_players {
            other_player.socket.write(disconnect_packet.to_bytes()) or {
                logger.log(utils.LogLevel.warning, 'Failed to send disconnect packet to player ${other_player.username}: $err')
                continue
            }

            other_player.socket.write(leave_chat_packet.to_bytes()) or {
                logger.log(utils.LogLevel.warning, 'Failed to send leave chat packet to player ${other_player.username}: $err')
                continue
            }
        }
    }

    socket.close() or {}
}
