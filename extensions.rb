# Some crafty extenions to native ruby classes to allow some more intuitive
# mehtods and behaviours
#
# All collected from my github gists: http://gist.github.com/jphastings
require 'time'
require 'delegate'

class Time
  # Gives a 'fuzzy' output of the distance to the time stored.
  # 
  # eg. 'in 28 minutes' or '23 hours ago'
  def roughly
    diff = self.to_i - Time.now.to_i
    ago = diff < 0
    diff = diff.abs
    case diff
    when 0
      return "now"
    when 1...60
      unit = "second"
    when 60...3600
      diff = (diff/60).round
      unit = "minute"
    when 3600...86400
      diff = (diff/3600).round
      unit = "hour"
    when 86400...604800
      diff = (diff/86400).round
      unit = "day"
    when 604800...2592000
      diff = (diff/604800).round
      unit = "week"
    when 2592000...31557600
      diff = (diff/2592000).round
      unit = "month"
    else
      diff = (diff/31557600).round
      unit = "year"
    end
    unit += "s" if diff != 1
    return (ago) ? "#{diff} #{unit} ago" : "in #{diff} #{unit}"
  end
end

# Allows relative times, most frequently used in times of arrival etc.
class ETA < Time
  # Takes a number of seconds until the event
  def self.new(seconds)
    raise "ETA requires a number of seconds" if not seconds.is_a?(Numeric)
    ETA.at Time.now + seconds
  end
  
  # Requires http://gist.github.com/116290
  def to_s
    self.roughly
  end
  alias :inspect :to_s
  
  # Gives a full textual representation of the time expected time of arrival (Time.rfc2822)
  def eta
    self.rfc2822
  end

  # Has the eta passed?
  def arrived?
    self.to_i < Time.now.to_i
  end
end

# Allows percentages to be inspected and stringified in human form "33.3%", but kept in a float format for mathmatics
class Percentage < DelegateClass(Float)
  def to_s(decimalplaces = 0)
    (((self * 10**(decimalplaces+2)).round)/10**decimalplaces).to_s+"%"
  end
  alias :inspect :to_s
end