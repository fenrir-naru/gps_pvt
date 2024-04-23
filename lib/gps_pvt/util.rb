require 'tempfile'
require 'uri'

proc{
  # port[:baudrate], baudrate default is 115200
  Serial.class_eval{
    const_set(:SPEC, 
        if RubySerial::ON_WINDOWS then
          %r{^(?:\\\\.\\)?(COM\d+)(?::(\d+))?$}
        elsif RubySerial::ON_LINUX then
          %r{^(/dev/tty[^:]+)(?::(\d+))?$}
        else
          nil
        end)
  }
  Serial.class_eval{
    read_orig = instance_method(:read)
    define_method(:read){|len|
      buf = ''
      f = read_orig.bind(self)
      buf += f.call(len - buf.size) while buf.size < len
      buf
    }
    def eof?; false; end
  }
}.call if require 'rubyserial'

require 'open-uri'
require_relative 'ntrip'
require_relative 'supl'

class URI::Ntrip
  def read_format(options = {})
    pnt_list = self.read_source_table(options).mount_points
    case pnt_list[self.mount_point][:format]
    when /u-?b(?:lo)?x/i; :ubx
    when /RTCM ?3/i; :rtcm3
    else; nil
    end
  end
end

module GPS_PVT
module Util
  class << self
    def special_stream?(spec)
      ['-', (Serial::SPEC rescue nil)].compact.any?{|v| v === spec}
    end
    def open(*args, &b)
      return args[0].open(*args[1..-1], &b) if args[0].respond_to?(:open)
      case args[0].to_str
      when (Serial::SPEC rescue nil)
        return ((@serial_ports ||= {})[$1] ||= Serial::new($1, $2 ? $2.to_i : 115200))
      when '-'
        if (/^[wa]/ === args[1]) \
            || (args[1].kind_of?(Integer) && ((File::Constants::WRONLY & args[1]) > 0)) then
          return STDOUT
        else
          return STDIN
        end
      end rescue nil
      super
    end
    def inflate(src, type = :gz)
      case type
      when :gz
        require 'zlib'
        Zlib::GzipReader.send(*(src.kind_of?(IO) ? [:new, src] : [:open, src]))
      when :Z
        res = IO::popen("uncompress -c #{src.kind_of?(IO) ? '-' : src}", 'r+')
        res.print(src.read) if src.kind_of?(IO)
        res.close_write
        res
      else
        raise "Unknown compression type: #{type} of #{src}"
      end
    end
    def get_txt(fname_or_uri)
      is_uri = fname_or_uri.kind_of?(URI)
      open(fname_or_uri){|src|
        compressed = proc{
          case src.content_type
          when /gzip/; next :gz
          end if is_uri
          case fname_or_uri.to_s
          when /\.gz$/; next :gz
          when /\.Z$/; next :Z
          end
          nil
        }.call

        case src
        when File
          next src.path
        when Tempfile
          # Preserve tempfile after leaving open-uri block
          src.define_singleton_method(:close!){close(false)}
          next src # Kernel.open(obj) redirects to obj.open if obj responds to :open
        end unless compressed

        Tempfile::open(File::basename($0, '.*')){|dst|
          dst.binmode
          dst.write((compressed ? inflate(is_file ? src.path : src, compressed) : src).read)
          dst.rewind
          dst.path
        }
      }
    end
  end
  module CRC24Q
    POLY = 0x1864CFB
    TABLE = 0x100.times.collect{|i|
      res = i << 16
      8.times{
        res <<= 1
        res ^= POLY if (res & 0x1000000) > 0
      }
      res
    }
    def CRC24Q.checksum(bytes)
      bytes.inject(0){|crc, byte|
        ((crc << 8) & 0xFFFF00) ^ TABLE[byte ^ ((crc >> 16) & 0xFF)]
      }
    end
  end
  module BitOp
    MASK = (1..8).collect{|i| (1 << i) - 1}.reverse
    def BitOp.extract(src_bytes, bits_list, offset = 0)
      res = []
      bits_list.inject(offset.divmod(8) + [offset]){|(qM, rM, skip), bits|
        qL, rL = (skip += bits).divmod(8)
        v = src_bytes[qM] & MASK[rM]
        res << if rL > 0 then
          src_bytes[(qM+1)..qL].inject(v){|v2, b| (v2 << 8) | b} >> (8 - rL)
        else
          src_bytes[(qM+1)..(qL-1)].inject(v){|v2, b| (v2 << 8) | b}
        end
        [qL, rL, skip]
      }
      res
    end
  end
end
end
