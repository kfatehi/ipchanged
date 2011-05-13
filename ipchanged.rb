#!/usr/bin/env ruby
require 'rubygems'
require 'logger'
require 'yaml'
require 'open-uri'
require 'net/ssh'
@log = Logger.new("log.txt")
@log.level = Logger::INFO
HOSTFILEREGEX = /#ipchanged-begin\n(.*)\n#ipchanged-end/m
IPREGEX = /\b(?:\d{1,3}\.){3}\d{1,3}\b/
def do_start
  @SET = YAML::load File.open("settings.yaml")
  @log.error "No master address specified. Fix that." if @SET["master"].nil?
  @hostname = `hostname`.strip
  begin
    @ip = open("http://www.whatismyip.com/automation/n09230945.asp").read
    raise "Got invalid IP, trying again in 10 minutes" if !@ip.match(IPREGEX)
  rescue Exception => ex
    @log.error ex.backtrace
    @log.error "Couldn't interface with whatismyip.com"
    sleep 10*60
    do_start
  end
  do_check
end
def do_update
  @entries = []
  begin
    Net::SSH.start(@SET["master"], "root") do |ssh|
      @cur_file = ssh.exec!("cat /etc/hosts")
      @hosts = @cur_file.match(HOSTFILEREGEX)
      if @hosts.nil? # there is no #ipchanged entry, add me with it!
        @new_file = @cur_file+"\n\n#ipchanged-begin\n#{@ip} #{@hostname}\n#ipchanged-end"
      else
        @entries = @hosts[1].split("\n")
        if @entries.nil? # there is nothing in the #ipchanged list, add me!
          @entries << "#{@ip} #{@hostname}"
        else # there are existing entries in the #ipchanged list, process them
          @entries.each_with_index do |e,i| 
            if (e.match(IPREGEX)[0] == @SET["slave"]) || (e.include? @hostname)# found my old ip, update!
              @entries[i].gsub!(e.match(IPREGEX)[0], @ip) ; @found = true
            end
          end
          @entries << "#{@ip} #{@hostname}" if !@found 
        end
        @new_file = @cur_file.gsub(@hosts[0], "#ipchanged-begin\n#{@entries.join("\n")}\n#ipchanged-end")
      end
      ssh.exec!("echo \"#{@new_file}\" > /etc/hosts")
      @log.info "Updated master hosts file!"
    end
    return true
  rescue Exception => ex
    @log.error ex.backtrace
    @log.error "Could not SSH. Did you fix the public key?"
    return false
  end
end
def do_check
  if @SET["slave"] == @ip
    @log.debug "IP hasn't changed, I'll check again in 15 minutes."
  else
    @log.info "IP has changed (was #{@SET["slave"]}, now is: #{@ip})"
    @SET["slave"] = @ip # Set the slave IP in the settings to current IP
    File.open("settings.yaml", "w") {|f| f.write @SET.to_yaml} if do_update
  end
  sleep 15*60
  do_start
end
do_start