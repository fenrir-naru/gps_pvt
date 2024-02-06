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
