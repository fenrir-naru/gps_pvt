# Ntrip (Networked Transport of RTCM via Internet Protocol)

require 'net/http'
require 'uri'
require_relative 'version'

module GPS_PVT
class Ntrip < Net::HTTP
  Net::HTTPResponse.class_eval{
    orig = singleton_method(:read_new)
    define_singleton_method(:read_new){|sock|
      # handle Ntrip(rev1), which does not comply with HTTP
      unless sock.respond_to?(:ntrip) then
        orig.call(sock)
      else
        str = sock.readline
        case str
        when /\A(?:(?:HTTP(?:\/(\d+\.\d+))?|([^\d\s]+))\s+)?(\d\d\d)(?:\s+(.*))?\z/in
          res = response_class($3).new($1 || '1.1', $3, $2 || $4)
          each_response_header(sock){|k,v|
            res.add_field k, v
          } unless res.message == 'ICY' # or 'SOURCETABLE' for Ntrip(rev1)
          res
        else
          raise Net::HTTPBadResponse, "wrong status line: #{str.dump}"
        end
      end
    }
  }
  def on_connect
    super
    @socket.define_singleton_method(:ntrip){true}
  end
  
  SOURCE_TBL_ITEMS = {
    :STR => [
        :type, :mountpoint, :identifier, :format, :format_details,
        :carrier, :nav_system, :network, :country, :latitude, :longitude,
        :nmea, :solution, :generator, :compression, :authentication, :fee, :bitrate],
    :CAS => [
        :type, :host, :port, :identifier, :operator,
        :nmea, :country, :latitude, :longitude, :fallback_host, :fallback_ip],
    :NET => [
        :type, :identifier, :operator, :authentication, :fee,
        :web_net, :web_str, :web_reg],
  }
  module MountPoints
    [:select, :reject, :merge, :clone, :dup].each{|f|
      define_method(f){|*args, &b| super(*args, &b).extend(MountPoints)}
    }
    D2R = Math::PI / 180
    def near_from(lat_deg, lng_deg)
      require 'gps_pvt/Coordinate'
      llh0 = Coordinate::LLH::new(D2R * lat_deg, D2R * lng_deg, 0)
      collect{|pt, prop|
        llh = Coordinate::LLH::new(*([:latitude, :longitude].collect{|k| D2R * prop[k].to_f} + [0]))
        [llh0.xyz.distance(llh.xyz), prop]
      }.sort{|a, b| a[0] <=> b[0]} # return [distance, property]
    end
  end
  def Ntrip.parse_source_table(str)
    res = {}
    str.lines.each{|line|
      values = line.chomp.split(/\s*;\s*/)
      type = values[0].to_sym
      next unless keys = SOURCE_TBL_ITEMS[type]
      next unless (values.size >= keys.size)
      entry = Hash[*(keys.zip(values).flatten(1))]
      entry[:misc] = values[(keys.size)..-1] if values.size > keys.size
      (res[type] ||= []) << entry
    }
    res.define_singleton_method(:mount_points, lambda{
      Hash[*((self[:STR] || []).collect{|entry|
        [entry[:mountpoint], entry]
      }.flatten(1))].extend(MountPoints)
    })
    res
  end
  def generate_request(path, header)
    req = Net::HTTP::Get.new(path, {
      'User-Agent' => "GPS_PVT NTRIP client/#{GPS_PVT::VERSION}",
      'Accept' => '*/*',
      'Ntrip-Version' => 'Ntrip/2.0',
    }.merge(header.select{|k, v| k.kind_of?(String)}))
    header.each{|k, v|
      next unless k.kind_of?(Symbol)
      req.send(k, *v)
    }
    req
  end
  def get_source_table(header = {}, &b)
    (b || proc{|str| Ntrip.parse_source_table(str)}).call(request(generate_request('/', header)).read_body)
  end
  def get_data(mount_point, header = {}, &b)
    request(generate_request("/#{mount_point}", header)){|res|
      res.read_body(&b)
    }
  end
end
end

require 'open-uri'

OpenURI.class_eval{
  check_options_orig = singleton_method(:check_options)
  define_singleton_method(:check_options){|options|
    uri = options.delete(:uri)
    case uri
    when URI::Ntrip
      options[:basic_auth] ||=
          options.delete(:http_basic_authentication) ||
          ([:user, :password].collect{|k|
            URI::decode_www_form_component(uri.send(k))
          } rescue nil)
      options['Ntrip-Version'] ||= "Ntrip/%3.1f"%[options.delete(:version)] if options[:version]
      options['User-Agent'] ||= options[:user_agent]
      options.select!{|k, v| v} #compact! Ruby >= 2.4.0
      true
    else
      check_options_orig.call(options)
    end
  }
  open_uri_orig = singleton_method(:open_uri)
  define_singleton_method(:open_uri){|name, *rest, &b|
    uri = URI::Generic === name ? name : URI.parse(name)
    (rest[-1].kind_of?(Hash) ? rest : (rest << {}))[-1][:uri] = uri
    open_uri_orig.call(uri, *rest, &b)
  }
  def OpenURI.open_ntrip(buf, target, proxy, options) # :nodoc:
    GPS_PVT::Ntrip.start(target.host, target.port){|ntrip|
      # get source table
      tbl_str = ntrip.get_source_table(options){|str| str}
      if target.root? then
        buf << tbl_str
        buf.io.rewind
        buf.io.define_singleton_method(:source_table){
          GPS_PVT::Ntrip::parse_source_table(tbl_str)
        }
        next
      end
      tbl = GPS_PVT::Ntrip::parse_source_table(tbl_str)
      
      # check mount point
      mnt_pt = target.mount_point
      prop = tbl.mount_points[mnt_pt]
      raise Net::ProtocolError::new("Mount point(#{mnt_pt}) not found") unless prop
      
      # set stream
      buf.instance_eval{
        @io, w = IO::pipe
        @io.define_singleton_method(:property){prop}
        Thread::new{
          begin
            ntrip.get_data(mnt_pt, options){|data| w << data}
          rescue Errno::EPIPE;
          rescue; raise
          ensure; w.close
          end
        }
      }
    }
  end
}
module URI
  class Ntrip < HTTP
    def root
      res = self.clone
      res.path = '/'
      res
    end
    def root?; self.path == '/'; end
    def mount_point
      self.path.sub(%r|^/|, '')
    end

    def buffer_open(buf, proxy, options)
      OpenURI.open_ntrip(buf, self, proxy, options)
    end
    include OpenURI::OpenRead
    def read_source_table(options = {})
      GPS_PVT::Ntrip::parse_source_table(self.root.read(options))
    end
  end
  if respond_to?(:register_scheme) then
    register_scheme('NTRIP', Ntrip)
  else
    @@schemes['NTRIP'] = Ntrip
  end
end
