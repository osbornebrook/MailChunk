require 'socket'
require 'gserver'
require 'optparse'
require 'yaml'

args = {:smtp => {}}

optparse = OptionParser.new do|opts|
  # Set a banner, displayed at the top
  # of the help screen.
  opts.banner = "Usage: mailchunk [CONF] recipient"
  
  opts.on('-c', '--config FILE', 'Configuration file') do |c|
    config_file = c
  end

  args[:verbose] = false
  opts.on( '-v', '--verbose', 'Output more information' ) do
    args[:verbose] = true
  end
  
  args[:debug] = false
  opts.on( '-d', '--debug', 'Dont send to postfix, output to console' ) do
    args[:debug] = true
  end
  
  opts.on( '-t', '--time SECONDS', 'interval to chunks to outgoing server' ) do |t|
    args[:send_interval] = t unless t.nil?
  end
  
  opts.on( '-h', '--host HOST', 'SMTP server to actually send the messages to' ) do |h|
    args[:smtp][:host] = h unless t.nil?
  end
  
  opts.on( '-p', '--port port', 'SMTP server to actually send the messages to' ) do |p|
    args[:smtp][:port] = p unless t.nil?
  end

  # This displays the help screen, all programs are
  # assumed to have this option.
  opts.on( '--help', 'Display this screen' ) do
    puts opts
    exit
  end
end

optparse.parse!

config_file ||= 'config.yaml' #default config file
config = YAML.load_file(config_file)

config = config.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}
config[:smtp] = config[:smtp].inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}

config[:smtp].merge!(args[:smtp])
args.delete(:smtp)

CONF = config.merge(args)

class MailChunk < GServer

  def initialize(*args)
    super(*args)
    
    # TODO - Config file... :)
    # CONF[:buffer_size] (was @@queue_size_spool) = 3 # how many emails to accept in memory before sending to spool  file
    # CONF[:chunk_size] (was @@queue_size = 10) # how many messages to send in a post fix shot
    # CONF[:send_interval]@@queue_timeout = 5 # how long to wait for more messages before sending queue?
    @@helo_domain = CONF[:smtp][:helo_domain] || Socket.gethostname
    # if true will output messages to console instead of sending to postfix
    @@verbose = CONF[:verbose]
    # Class variables
    
    @@buffer = []
    @@chunk = []

  end
  
  def serve(io)
    Thread.current["data_mode"] = false
    io.print "220 #{@@helo_domain} SMTP MailChunk Proxy\r\n"
    msg = ''
    loop do
      if IO.select([io], nil, nil, 0.1)
        data = io.readpartial(4096)
        msg << data unless data.match(/EHLO|HELO|QUIT/)
        ok, op = process_line(data)
        io.print op
        break unless ok
      end
      break if io.closed?
    end
    io.close
    puts msg if @@verbose
    add_to_queue(msg)    
  end

  def send_interval
    CONF[:send_interval]
  end

  def add_to_queue(msg) 

    Thread.critical = true
    @@buffer << msg
    Thread.critical = false
    puts "Added msg to queue. Size: #{@@buffer.length}"

    # REFACTOR based on size of messages hash
    if @@buffer.length >= CONF[:buffer_size] 
      write_chunk
    end

  end

  def write_chunk
    # Send current messages to spool file (in this case the @@chunk array)
    Thread.critical = true
    puts "spooling #{@@buffer.length} messages"
    @@chunk += @@buffer
    @@buffer = []
    Thread.critical = false
  end 
    
      
  def send_messages
    write_chunk
    if @@chunk.length > 0
      begin
        p = TCPSocket.new(CONF[:smtp][:host], CONF[:smtp][:port]) unless CONF[:debug]
      rescue
        puts "Error connecting to postfix on #{CONF[:smtp][:host]}:#{CONF[:smtp][:port]}"
      else
        # load all messages (from spool) and add current messages
        messages = []
        Thread.critical = true
        messages = @@chunk.shift(CONF[:chunk_size])
        Thread.critical = false
        if messages.length > 0
          sendspool = "HELO #{@@helo_domain}\r\n#{messages.join()}QUIT\r\n"
          puts sendspool if CONF[:debug] 
        end
        unless CONF[:debug]
          p.print(sendspool)
          puts p.gets(nil)
          p.close
        end
      end
    end
  end

  def process_line(line)
    if (line =~ /^(HELO|EHLO)/)
      return true, "220 and..?\r\n"
    end
    if (line =~ /^QUIT/)
      return false, "221 bye\r\n"
    end
    if (line =~ /^MAIL FROM\:/)
      return true, "220 OK\r\n"
    end
    if (line =~ /^RCPT TO\:/)
      return true, "220 OK\r\n"
    end
    if (line =~ /^DATA/)
      @data_mode = true
      return true, "354 Enter message, ending with \".\" on a line by itself\r\n"
    end
    if (@data_mode) && (line.chomp =~ /^\.$/)
      @data_mode = false
      return true, "220 OK\r\n"
    end
    if @data_mode
      # puts line 
      return true, ""
    else
      return true, "500 ERROR\r\n"
    end
  end

end

a = MailChunk.new(2025)
a.start
loop do
  sleep a.send_interval
  a.send_messages
  puts "#{a.send_interval} seconds has passed ;)"
  break if a.stopped?
end

# a.join