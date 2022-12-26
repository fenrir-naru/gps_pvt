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
  module Kernel
    open_orig = instance_method(:open)
    define_method(:open){|*args, &b|
      return open_orig.bind(self).call(*args, &b) unless Serial::SPEC =~ args[0]
      Serial::new($1, $2 ? $2.to_i : 115200)
    }
    module_function(:open)
  end
}.call if require 'rubyserial'

require 'open-uri'
require_relative 'ntrip'

class URI::Ntrip
  def read_format(options = {})
    pnt_list = self.read_source_table(options).mount_points
    case pnt_list[self.mount_point][:format]
    when /u-?b(?:lo)?x/i; :ubx
    else; nil
    end
  end
end

module GPS_PVT
module Util
  class << self
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
      (is_uri ? URI : Kernel).send(:open, fname_or_uri){|src|
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
        is_file = src.kind_of?(File) || src.kind_of?(Tempfile)

        return src.path if ((!compressed) and is_file)

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
end
end
