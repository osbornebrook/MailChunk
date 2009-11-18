#!/usr/bin/ruby

require 'socket'
require 'gserver'
require 'optparse'

CONF = {}

optparse = OptionParser.new do|opts|
  # Set a banner, displayed at the top
  # of the help screen.
  opts.banner = "Usage: mailchunk [CONF] recipient"

  CONF[:verbose] = false
  opts.on( '-v', '--verbose', 'Output more information' ) do
    CONF[:verbose] = true
  end
  
  CONF[:debug] = false
  opts.on( '-d', '--debug', 'Dont send to postfix, output to console' ) do
    CONF[:debug] = true
  end
  
  CONF[:smtp_host] = 'localhost'
  opts.on( '-h', '--host HOST', 'SMTP server to actually send the messages to' ) do |h|
    CONF[:smtp_host] = h
  end
  
  CONF[:smtp_port] = '25'
  opts.on( '-p', '--port port', 'SMTP server to actually send the messages to' ) do |p|
    CONF[:smtp_port] = p
  end

  # This displays the help screen, all programs are
  # assumed to have this option.
  opts.on( '--help', 'Display this screen' ) do
    puts opts
    exit
  end
end

optparse.parse!

class MailChunk < GServer

  def initialize(*args)
    super(*args)
    
    # TODO - Config file... :)
    @@queue_size_spool = 3 # how many emails to accept in memory before sending to spool  file
    @@queue_size = 10
    @@queue_timeout = 5 # how long to wait for more messages before sending queue?
    @@helo_domain = Socket.gethostname
    # if true will output messages to console instead of sending to postfix
    @@verbose = false
    # Class variables
    
    @@spool = []
    @@messages = []

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
    # test_send(msg)
    add_to_queue(msg)    
  end

  def queue_timeout
    @@queue_timeout
  end

  def add_to_queue(msg)
    # loop while @@sending 

    Thread.critical = true
    @@spool << msg
    Thread.critical = false
    puts "Added msg to queue. Size: #{@@spool.length}"

    # REFACTOR based on size of messages hash
    if @@spool.length >= @@queue_size_spool 
      spool_messages
    end

  end

  def spool_messages
    # Send current messages to spool file (in this case the @@messages array)
    Thread.critical = true
    puts "spooling #{@@spool.length} messages"
    @@messages += @@spool
    @@spool = []
    Thread.critical = false
  end 
    
      
  def send_messages
    spool_messages
    if @@messages.length > 0
      begin
        p = TCPSocket.new(CONF[:smtp_host], CONF[:smtp_port]) unless CONF[:debug]
      rescue
        puts "Error connecting to postfix on #{CONF[:smtp_host]}:#{CONF[:smtp_port]}"
      else
        # load all messages (from spool) and add current messages
        messages = []
        Thread.critical = true
        messages = @@messages.shift(@@queue_size)
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
  sleep a.queue_timeout
  a.send_messages
  puts "#{a.queue_timeout} seconds has passed ;)"
  break if a.stopped?
end

# a.join