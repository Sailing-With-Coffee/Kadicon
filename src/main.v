import net
import io
import networking
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

    for {
		mut socket := server.accept()!
		spawn handle_client(mut socket)
	}
}

fn handle_client(mut socket net.TcpConn) {
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


                mut response_packet := networking.Packet{
                    packet_type: u8(networking.S2C_PacketType.server_identification)
                }

                response_packet = response_packet.append_byte(networking.get_protocol_version())
                response_packet = response_packet.append_string('A Minecraft Server')
                response_packet = response_packet.append_string('Powered by Kadicon')
                response_packet = response_packet.append_byte(0x00)

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


                send_ping = true
            }

            .set_block {
                logger.log(utils.LogLevel.info, 'Set block packet received')
            }

            .player_position_and_orientation {
                logger.log(utils.LogLevel.info, 'Player position and orientation packet received')
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

            logger.log(utils.LogLevel.info, 'Ping packet sent to client')
        }
	}
}