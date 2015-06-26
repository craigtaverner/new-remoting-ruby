require 'socket'
require './lib/pack_stream'
require 'stringio'
require './lib/session'

INIT = 0x01

def send_raw_message(socket, message)
  puts "C: #{message.inspect}"
  socket.sendmsg(message)

  socket
end

def send_message(socket, message)
  io = ChunkWriterIO.new
  io.write(message)
  io.flush(true)
  io.rewind
  send_raw_message(socket, io.read)
end

def send_packed_objects(socket, *objects)
  message = objects.map {|o| PackStream::Packer.new(o).packed_stream }.join

  send_message(socket, message)
end

def flush_response(response)
  result = []

  while (chunk_size = response.recv(2).unpack('s>*')[0]) > 0
    chunk = response.recv(chunk_size)

    response_stream = StringIO.new(chunk)

    unpacker = PackStream::Unpacker.new(response_stream)

    values = []

    while value = unpacker.unpack_value!
      values << value
    end

    result << values
  end

  result
end


session = Neo4j::Session.new(logger_level: Logger::DEBUG)

puts 'query: ', session.query("CREATE (a:Person {name:'Alice'}), (b:Person {name:'Bob'}) RETURN a, b").inspect



