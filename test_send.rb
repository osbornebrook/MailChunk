#!/usr/bin/ruby

require 'net/smtp'
require 'optparse'
require 'socket'

options = {}

optparse = OptionParser.new do|opts|
  # Set a banner, displayed at the top
  # of the help screen.
  opts.banner = "Usage: test_send.rb [options] recipient"

  options[:verbose] = false
  opts.on( '-v', '--verbose', 'Output more information' ) do
    options[:verbose] = true
  end

  options[:num] = 1
  opts.on( '-n', '--num Float', 'Number of emails to send' ) do |n|
    options[:num] = n
  end

  options[:from_email] = 'sonofgod@upstairs.net'
  opts.on('-f', '--from-email', 'Email address of sender') do |f|
    options[:from_email] = f
  end

  options[:from_name] = 'Jesus Christ'
  opts.on('-F', '--from-name', 'Display name of sender') do |f|
    options[:from_name] = f
  end

  # This displays the help screen, all programs are
  # assumed to have this option.
  opts.on( '-h', '--help', 'Display this screen' ) do
    puts opts
    exit
  end
end

optparse.parse!

recipient = ARGV.shift

if !recipient || recipient == ''
  recipient = 'team@osbornebrook.co.uk'
  # puts opts
  # exit
end

(1..options[:num].to_i).each do |n|
  message = <<MAIL
Date: #{Time.now.to_s}
From: #{options[:from_name]} <#{options[:from_email]}>
To: You <#{recipient}>
Subject: Testing MAIL
Precedence: bulk

This is the message number #{n}. Can you read it? NOW!!!

MAIL
  Net::SMTP.start('localhost', 2025, "tester.com", nil, nil, :plain) do |smtp|
    if smtp.send_message(message, options[:from_email], recipient)
      puts "Send email to #{recipient}"
    end
  end
end
