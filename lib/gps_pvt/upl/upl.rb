#!/usr/bin/ruby

require 'json'
require 'zlib'
require_relative '../asn1/asn1'

ASN1 = GPS_PVT::ASN1

upl = ASN1::resolve_tree(JSON::parse(
    Zlib::GzipReader::open(File::join(File::dirname(__FILE__), 'upl.json.gz')).read,
    {:symbolize_names => true}))

# RRLP payload conversion
ASN1::dig(upl, :ULP, :"ULP-PDU", :message, :msSUPLPOS, :posPayLoad, :rrlpPayload)[:type][1].merge!({
  :hook_encode => proc{|data|
    next data unless data.kind_of?(Hash)
    ASN1::encode_per(upl[:"RRLP-Messages"][:PDU], data).scan(/.{1,8}/).tap{|buf|
      buf[-1] += "0" * (8 - buf[-1].length)
    }.collect{|str| str.to_i(2)}
  },
  :hook_decode => proc{|data|
    data.define_singleton_method(:decode){
      ASN1::decode_per(upl[:"RRLP-Messages"][:PDU], self.collect{|v| "%08b" % [v]}.join)
    }
    data
  },
})

ASN1::dig(upl, :"MAP-LCS-DataTypes", :"Ext-GeographicalInformation")[:type][1].merge!({
  :hook_decode => proc{
    gen_ut = proc{|c, x| proc{|k| ((x + 1) ** k - 1) * c} }
    tbl_task = {
      :lat => [3, proc{|v| Rational((v & 0x7FFFFF) * 90, 1 << 23).to_f * (((v >> 23) == 1) ? -1 : 1)}],
      :lng => [3, proc{|v| Rational((v >= (1 << 23) ? v - (1 << 24) : v) * 180, 1 << 23).to_f}],
      :ucode => 1,
      :usmaj => [1, gen_ut.call(10, 0.1)],
      :usmin => [1, gen_ut.call(10, 0.1)],
      :omaj => 1,
      :cnf => 1,
      :alt => [2, proc{|v| (v & 0x7FFF) * (((v >> 15) == 1) ? -1 : 1)}],
      :ualt => [1, gen_ut.call(45, 0.025)],
      :irad => [2, proc{|v| v * 5}],
      :urad => [1, gen_ut.call(10, 0.1)],
      :oang => [1, proc{|v| v * 2}],
      :iang => [1, proc{|v| (v + 1) * 2}],
    }
    tbl_item = { # 7.2 Table 2a in 3GPP TS 23.032
      # (a) 7.3.2 Ellipsoid point with uncertainty Circle
      1 => [8, :lat, :lng, :ucode],
      # (b) 7.3.3 Ellipsoid point with uncertainty Ellipse
      3 => [11, :lat, :lng, :usmaj, :usmin, :omaj, :cnf],
      # (c) 7.3.6 Ellipsoid point with altitude and uncertainty Ellipsoid
      9 => [14, :lat, :lng, :alt, :usmaj, :usmin, :omaj, :ualt, :cnf],
      # (d) 7.3.7 Ellipsoid Arc 
      10 => [13, :lat, :lng, :irad, :urad, :oang, :iang, :cnf],
      # (e) 7.3.1 Ellipsoid Point
      0 => [7, :lat, :lng],
    }
    proc{|data|
      data.define_singleton_method(:decode){
        len, *items = tbl_item[self[0] >> 4]
        next nil unless self.length == len
        offset = 1
        Hash[*(items.collect{|k|
          len2, task = tbl_task[k]
          v = self.slice(offset, len2).inject(0){|res, v2| (res << 8) + v2}
          v = task.call(v) if task
          offset += len2
          [k, v]
        }.flatten(1))]
      }
      data
    }
  }.call,
})

# LPP payload conversion
ASN1::dig(upl, :ULP, :"ULP-PDU", :message, :msSUPLPOS, :posPayLoad, :"ver2-PosPayLoad-extension", :lPPPayload)[:type][1].merge!({
  :hook_encode => proc{|data|
    next data unless data.kind_of?(Hash)
    ASN1::encode_per(upl[:"LPP-PDU-Definitions"][:"LPP-Message"], data).scan(/.{1,8}/).tap{|buf|
      buf[-1] += "0" * (8 - buf[-1].length)
    }.collect{|str| str.to_i(2)}.scan(/.{1,60000}/)
  },
  :hook_decode => proc{|data|
    data.define_singleton_method(:decode){
      ASN1::decode_per(upl[:"LPP-PDU-Definitions"][:"LPP-Message"], self.flatten.collect{|v| "%08b" % [v]}.join)
    }
    data
  },
})

# BCD String
[:msisdn, :mdn, :imsi, :"ver2-imei"].each{|k|
  elm = ASN1::dig(upl, :ULP, :"ULP-PDU", :sessionID, :setSessionID, :setId, k)
  next unless elm
  elm[:type][1].merge!({
    :hook_encode => proc{|data|
      next data unless data.kind_of?(String)
      (("0" * (16 - data.size)) + data).scan(/\d{2}/).collect{|v| v.to_i(16)}
    },
    :hook_decode => proc{|data|
      data.collect{|v| "%02X"%[v]}.join
    },
  })
}

=begin
UPL: User Plane Location
ULP: UserPlane Location Protocol
=end

GPS_PVT::UPL = Module::new{
define_method(:generate_skeleton){|k_cmd, *args|
  opts = args[0] || {}
  ver = case [2, 0xFF, 0xFF].zip([opts[:version]].flatten || []) \
      .inject(0){|sum, (v1, v2)| (sum * 0x100) + (v2 || v1)}
    when 0x020006..0x02FFFF; [2, 0, 6]
    #when 0x020000..0x02FFFF; [2, 0, 0]
    else; raise
  end
  res = ASN1::generate_skeleton(upl[:ULP][:"ULP-PDU"])
  [:maj, :min, :servind].zip(ver).each{|k, v|
    res[:version][k] = v
  }
  res[:message].reject!{|k, v|
    "ms#{k_cmd}".to_sym != k
  }
  res.define_singleton_method(:all_keys){
    (iter = proc{|hash|
      hash.collect{|k, v|
        v.kind_of?(Hash) ? {k => iter.call(v)} : k
      }
    }).call(self)
  }
  res
}
define_method(:encode){|cmd|
  buf = ASN1::encode_per(upl[:ULP][:"ULP-PDU"], cmd).scan(/.{1,8}/)
  buf[-1] += "0" * (8 - buf[-1].length)
  (buf.length.divmod(1 << 8) + buf[2..-1].collect{|str| str.to_i(2)}).pack("C*")
} 
define_method(:decode){|str|
  ASN1::decode_per(upl[:ULP][:"ULP-PDU"], str.unpack("C*").collect{|v| "%08b" % [v]}.join)
}
module_function(:generate_skeleton, :encode, :decode)
}
