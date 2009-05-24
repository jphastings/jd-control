spec = Gem::Specification.new do |s| 
  s.name = "jd-control"
  s.version = "1.0.1"
  s.author = "JP Hastings-Spital"
  s.email = "jd-control@projects.kedakai.co.uk"
  s.homepage = "http://projects.kedakai.co.uk/jd-control/"
  s.platform = Gem::Platform::RUBY
  s.description = "Control JDownloader from ruby via the 'Remote Control' plugin"
  s.summary = "Control JDownloader from ruby via the 'Remote Control' plugin"
  s.files = ["jd-control.rb","extensions.rb"]
  s.require_paths = ["."]
  s.add_dependency("httparty")
  s.has_rdoc = true
end
