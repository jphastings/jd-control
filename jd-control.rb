# Control JDownloader from a ruby script via the 'Remote Control' plugin
#
# Allows you to start, stop and pause the download queue, add new downloads and
# tinker with the bandwidth limits of the program.
require 'yaml'
require 'extensions'
require 'rubygems'
require 'httparty'

module JDownloader
  # Allows control of JDownloader via the 'Remote Control' plugin
  class Control
    attr_accessor :limit
    attr_reader :version, :speed
    include HTTParty
      
    # The ip address of the computer running JDownloader (probably 127.0.0.1)
    def initialize(host = "127.0.0.1",port = 5000) # Can't remember the default port!
      self.class.base_uri "http://#{host}:#{port}/"
    end
    
    # Returns the JDownloader version
    def version
      self.class.get("/get/version")
    end
    
    # Returns current download speed
    def speed
      self.class.get("/get/speed").to_i
    end
    
    # Returns the current speed limit (KBps)
    def limit
      self.class.get("/get/speedlimit").to_i
    end
    
    # Sets the download speed limit (KBps)
    def limit=(kBps)
      raise "Requires Integer KBps value" if not kBps.is_a?(Integer)
      self.class.get("/action/set/download/limit/#{kBps}").to_i
    end
    
    # Starts the downloader queue
    def start
      return self.class.get("/action/start") == "Downloads started"
    end
    
    # Stops the downloader queue
    def stop
      return self.class.get("/action/stop") == "Downloads stopped"
    end
    
    # Pauses the downloader queue (how is this different to stop?)
    def pause
      return self.class.get("/action/pause") == "Downloads paused"
    end
    
    # Creates a new package with the given array of links
    def download(links)
      links = [links] if links.is_a?(String)
      self.class.get("/action/add/links/grabber0/start1/"+links.join(" "))
    end
    
    # Lists the details of any download or downloads (by id) or all downloads.
    def download(downloadids = nil)
      downloadids = [downloadids] if downloadids.is_a?(Integer)
      
      dls = parse_packages(self.class.get("/get/downloads/alllist"))
      if downloadids.nil?
        return dls
      else
        return dls.delete_if {|id, package| not downloadids.include?(id)}
      end
    end
    alias :downloads :download
    
    private
    def parse_packages(string)
      Hash[*string.scan(/<package package_name="(.*?)" package_id="([0-9]+?)" package_percent="([0-9]+?\.[0-9]+?)" package_linksinprogress="([0-9]+?)" package_linkstotal="([0-9]+?)" package_ETA="((?:[0-9]+:)?[0-9]{2}:(?:-1|[0-9]{2}))" package_speed="([0-9]+?) ([G|M|K]B)\/s" package_loaded="([0-9]+?\.?[0-9]*?) ([G|M|K]B)" package_size="([0-9]+?\.[0-9]+?) ([G|M|K]B)" package_todo="([0-9]+?\.?[0-9]*?) ([G|M|K]B)" ?> ?(.*?)<\/package>/).collect { |p|
          m = nil
          [p[1].to_i, Package.new({
            :name => p[0],
            :id => p[1].to_i,
            :links => {
              :in_progress => p[3].to_i,
              :in_total => p[4].to_i
            },
            :eta => (p[5] == "00:-1") ? nil : p[5].split(":").reverse.inject(0) { |sum, element| m = ((m.nil?) ? 1 : m*60 ); sum + element.to_i*m },
            :speed => p[6].to_i * parse_bytes(p[7]),
            :completed => p[2].to_f/100,
            :size => {
              :loaded => p[8].to_i * parse_bytes(p[9]),
              :total => p[10].to_i * parse_bytes(p[11]),
              :todo => p[12].to_i * parse_bytes(p[13])
            },
            :files => Hash[*p[14].scan(/<file file_name="(.*?)" file_id="([0-9]+?)" file_package="([0-9]+?)" file_percent="([0-9]+?\.[0-9]+?)" file_hoster="(.*?)" file_status="(.*?)" file_speed="(-1|[0-9]+?)" ?>/).collect { |f|
              [f[1].to_i,{
                :name => f[0],
                :id => f[1].to_i,
                :package_id => f[2].to_i,
                :completed => f[3].to_f/100,
                :hoster => f[4],
                :status => parse_status(f[5]),
                :speed => (f[6] == "-1") ? nil : f[6].to_i
              }]
            }.flatten]
            
          })]
        }.flatten
      ]
    end
    
    def parse_bytes(bytes)
      case bytes
      when "GB"
        return 1048576
      when "MB"
        return 1024
      when "KB"
        return 1
      else
        raise "Unknown unit: #{bytes}"
      end
    end
    
    def parse_status(status)
      case status
      when "[finished]"
        {
          :description => :finished
        }
      when /^Wait ([0-9]{2}):([0-9]{2}) min(?:\. for (.+))?$/
        {
          :description => :wait,
          :wait => $3,
          :time => $1.to_i * 60 + $2.to_i
        }
      when "[wait for new ip]"
        {
          :description => :wait,
          :wait => :new_ip
        }
      when /ETA ([0-9]{2}):([0-9]{2}) @ ([0-9]+) ([M|K]B)\/s \([0-9]+\/[0-9]+\)/ # What are these last two digitas? Download slots used and available?
        {
          :description => :in_progress,
          :time => $1.to_i * 60 + $2.to_i,
          :speed => $3.to_i * parse_bytes($4)
        }
      when ""
        {
          :description => :wait,
          :wait => :queued
        }
      else
        status
      end
    end
  end
  
  # JDownloader packages can be accessed as objects, they're almost totally intuitive
  class Package
    attr_reader :name, :id, :eta, :speed, :completed, :size, :files
    def initialize(p)
      @name = p[:name]
      @id = p[:id]
      @package = p[:package_id]
      @eta = (p[:completed] >= 1.0) ? "finished" : (p[:eta].nil?)? "unknown" : ETA.new(p[:eta])
      @speed = p[:speed]
      @completed = Percentage.new(p[:completed])
      @file = p[:files]
    end
    
    def inspect
      "#{@completed} of '#{@name}' ETA #{@eta}"
    end
  end
end