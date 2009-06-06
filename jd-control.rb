# Control JDownloader from a ruby script via the 'Remote Control' plugin
#
# Allows you to start, stop and pause the download queue, add new downloads and
# tinker with the bandwidth limits of the program.
require 'extensions'
require 'rubygems'
require 'httparty'
require 'tempfile'
require 'hpricot'

module JDownloader
  # Allows control of JDownloader via the 'Remote Control' plugin
  class Control
    attr_accessor :limit
    attr_reader :version, :speed
    include HTTParty
      
    # The ip address of the computer running JDownloader (probably 127.0.0.1)
    def initialize(host = "127.0.0.1",port = 10025)
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
    def add_link(links)
      links = [links] if links.is_a?(String)
      self.class.get("/action/add/links/grabber0/start1/"+links.join(" "))
    end
    
    alias :add_links :add_link
    
    # Will add a DLC to the download queue, pass the DLC or a local file
    def add_dlc(dlc_or_file)
      if dlc_or_file.is_a?(String)
        file = Tempfile.open('dlc') do |f|
          f.write dlc_or_file
        end
        dlc_or_file = file.path
      else
        raise "That file does not exist" if not File.exists?(dlc_or_file)
      end
      self.class.get("/action/add/container/#{dlc_or_file}")
    end
    
    # Lists the details of any download or downloads (by id) or all downloads.
    def packages(downloadids = nil)
      downloadids = [downloadids] if downloadids.is_a?(Integer)
      
      dls = parse_packages(self.class.get("/get/downloads/alllist"))
      if downloadids.nil?
        return dls
      else
        return dls.delete_if {|id, package| not downloadids.include?(id)}
      end
    end
    alias :package :packages
    
    private
    def parse_packages(string)
      return {} if string.nil?
      
      Hash[*Hpricot(string).search("package").collect { |package|
          m = nil
          [package.attributes['package_id'].to_i, Package.new({
            :name => package.attributes['package_name'],
            :id => package.attributes['package_id'].to_i,
            :links => {
              :in_progress => package.attributes['package_linksinprogress'].to_i,
              :in_total => package.attributes['package_linkstotal'].to_i
            },
            :eta => (package.attributes['package_ETA'] == "00:-1") ? nil : package.attributes['package_ETA'].split(":").reverse.inject(0) { |sum, element| m = ((m.nil?) ? 1 : m*60 ); sum + element.to_i*m },
            :speed => package.attributes['package_speed'].split(" ")[0].to_f * parse_bytes(package.attributes['package_speed'].split(" ")[1]),
            :completed => package.attributes['package_percent'].to_f/100,
            :size => {
              :loaded => package.attributes['package_loaded'].split(" ")[0].to_f * parse_bytes(package.attributes['package_loaded'].split(" ")[1]),
              :total => package.attributes['package_size'].split(" ")[0].to_f * parse_bytes(package.attributes['package_size'].split(" ")[1]),
              :todo => package.attributes['package_todo'].split(" ")[0].to_f * parse_bytes(package.attributes['package_todo'].split(" ")[1])
            },
            :files => Hash[*package.search("file").collect { |file|
              [file.attributes['file_id'].to_i,JDownloader::File.new({
                :name => file.attributes['file_name'],
                :id => file.attributes['file_id'].to_i,
                #:package_id => file.attributes['file_package'].to_i,
                :completed => file.attributes['file_percent'].to_f/100,
                :hoster => file.attributes['file_hoster'],
                :status => parse_status(file.attributes['file_status']),
                #:speed => (file.attributes['file_speed'] == "-1") ? nil : file.attributes['file_speed'].to_i
              })]
            }.flatten]
            
          })]
        }.flatten
      ]
    end
    
    def parse_bytes(bytes)
      case bytes
      when "GB","GB/s"
        return 1048576
      when "MB","MB/s"
        return 1024
      when "KB","KB/s"
        return 1
      when "B","B/s"
        return 1/1024
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
      when /^Wait ([0-9]{2})?:?([0-9]{2}):([0-9]{2}) min(?:\. for (.+))?$/
        {
          :description => :wait,
          :wait => $4,
          :time => ETA.new($1.to_i * 3600 + $2.to_i * 60 + $3.to_i)
        }
      when "Connecting..."
        {
          :description => :wait,
          :wait => :connecting
        }
      when "[wait for new ip]"
        {
          :description => :wait,
          :wait => :new_ip
        }
      when /^ETA ([0-9]{2})?:?([0-9]{2}):([0-9]{2}) @ ([0-9]+\.[0-9]+) ([G|M|K]?B)\/s \(([0-9]+)\/([0-9]+)\)$/ # What are these last two digitas? Download slots used and available?
        {
          :description => :in_progress,
          :time => ETA.new($1.to_i * 3600 + $2.to_i * 60 + $3.to_i),
          :speed => $4.to_f * parse_bytes($5),
          :slots => {
            :used => $6.to_i,
            :free => $7.to_i - $6.to_i,
            :total => $7.to_i
          }
        }
      when ""
        {
          :description => "Unknown"
        }
      else
        status
      end
    end
  end
  
  # JDownloader packages contain files, this class allows interrogation of the files
  class File
    attr_reader :name, :id, :hoster, :status, :completed, :speed, :eta
    def initialize(f)
      @name = f[:name]
      @id = f[:id]
      @hoster = f[:hoster]
      @status = f[:status]
      @completed = Percentage.new(f[:completed])
      @status = {:description => :finished} if @completed == 1
      @speed = f[:status][:speed] if not f[:status][:speed].nil?
      @eta = f[:status][:time] if not f[:status][:time].nil?
    end
    
    # Is the file waiting to be downloaded?
    def waiting?
      @status[:description] == :wait
    end
    
    # Is the file completed?
    def finished?
      @status[:description] == :finished
    end
    alias :completed? :finished?
    
    def inspect
      "#{@name}"
    end
  end
  
  # JDownloader packages can be accessed as objects, they're almost totally intuitive
  class Package
    attr_reader :name, :id, :eta, :speed, :completed, :size, :files, :status
    def initialize(p)
      @name = p[:name]
      @id = p[:id]
      #@package = p[:package_id]
      @eta = (p[:completed] >= 1.0) ? "finished" : (p[:eta].nil?)? "unknown" : ETA.new(p[:eta])
      @speed = p[:speed]
      @completed = Percentage.new(p[:completed])
      @files = p[:files]
    end
    
    def inspect
      "#{@completed} of '#{@name}' ETA #{@eta}"
    end
  end
end