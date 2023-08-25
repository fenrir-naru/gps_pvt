#!/usr/bin/ruby

require 'json'
require 'zlib'

upl = JSON::parse(
    Zlib::GzipReader::open(File::join(File::dirname(__FILE__), 'upl.json.gz')).read,
    {:symbolize_names => true})

resolve_tree = proc{|root|
  assigned_type = {}
  assigned_const = {}
  resolved = nil
  expand_ref = proc{|child_v, path, parent|
    child_k = (path ||= [])[-1]
    case child_v
    when Hash
      if child_v[:typeref] then
        if !child_v[:type] then
          if (child_v[:type] = assigned_type[child_v[:typeref].to_sym]) then
            assigned_type[child_k] = child_v[:type]
            resolved += 1
          end
        end
      elsif child_v[:type] then
        type, *other = child_v[:type]
        if type.kind_of?(String) then
          child_v[:type] = [type.to_sym] + (other.empty? ? [{}] : other)
          resolved += 1
        end
        if !assigned_type.keys.include?(child_k) then
          assigned_type[child_k] = child_v[:type]
          assigned_const[child_k.to_s] = child_v[:value] if child_v.keys.include?(:value)
        end
      end
      child_v.each{|k, v|
        expand_ref.call(v, path + [k], child_v)
      }
    when Array
      child_v.each.with_index{|v, i|
        expand_ref.call(v, path + [i], child_v)
      }
    when String
      if assigned_const[child_v] then
        parent[child_k] = assigned_const[child_v]
        resolved += 1
      end
    end
  }
  while true
    resolved_previous = resolved
    resolved = 0
    expand_ref.call(root)
    break if (resolved_previous == 0) && (resolved == 0)
  end
  
  reduce_constraint = proc{|props|
    case props
    when /^((?:(?!\.{2,})\.[^\.\s]|[^\.\s])+)\.\.(\.?)((?:(?!\.{2,})\.[^\.\s]|[^\.\s])+)$/
      a, b = $~.values_at(1, 3).collect{|v| Integer(v) rescue Float(v) rescue v}
      Range::new(a, b, $2.empty? ? false : true)
    when Array
      props.collect{|prop| reduce_constraint.call(prop)}
    when Hash
      props = Hash[*(props.collect{|k, prop|
        [k, reduce_constraint.call(prop)]
      }.flatten(1))]
      if props[:and] then
        down_to, up_to, less_than = [[], [], []]
        prop = props[:and].reject{|v|
          case v
          when Range
            down_to << v.first
            v.exclude_end? ? (up_to << v.last) : (less_then << v.last)
          when Array
            case v[0]
            when ">="; down_to << v[1]
            when "<="; up_to << v[1]
            when "<"; less_then << v[1]
            end
          end
        }
        if (first = down_to.max) && (last = [up_to, less_than].flatten.min) then
          prop << Range::new(first, last, last == less_than.min)
          if prop.size > 1 then
            props[:and] = prop
          elsif props.keys.size == 1 then
            next prop[0]
          else
            props[:and] = prop[0] # Rare case?
          end
        end
      end
      props
    else
      props
    end
  }
  find_range = proc{|type_opts, k|
    res = {:root => []} # [min, max]
    res.define_singleton_method(:belong_to){|v|
      min, max = self[:root]
      if (!min || (min <= v)) && (!max || (max >= v)) then
        self[:additional] ? :root : true
      else
        :additional
      end
    }
    iter_proc = proc{|props, cat, cnd_or|
      switch_min = proc{|min_new, more_than|
        min_new = (more_than && min_new.kind_of?(Integer)) \
            ? (min_new + 1) : min_new.ceil
        res[cat][0] = [res[cat][0], min_new].compact.send(
            cnd_or ? :min : :max)
      }
      switch_max = proc{|max_new, less_than|
        max_new = (less_than && max_new.kind_of?(Integer)) \
            ? (max_new - 1) : max_new.floor
        res[cat][1] = [res[cat][1], max_new].compact.send(
            cnd_or ? :max : :min)
      }
      case props
      when Range
        switch_min.call(props.first)
        switch_max.call(props.last, props.exclude_end?)
      when Array
        case prop[0]
        when '>=', '>'; switch_min.call(prop[1], prop[1] == '>')
        when '<=', '>'; switch_max.call(prop[1], prop[1] == '<')
        end
      when Hash
        if props[:root] then
          res[:additional] = []
          iter_proc.call(props[:root], cat, cnd_or)
          iter_proc.call(props[:additional], :additional, cnd_or)
        elsif props[k] then
          [props[k]].flatten(1).each{|prop|
            iter_proc.call(prop, cat, true)
          }
        elsif (cnd = ([:and, :or, :not] & props.keys)[0]) then
          res_bkup = res
          res2 = res = {cat => []}
          cnd_or2 = (cnd != :and)
          props[cnd].each{|prop| iter_proc.call(prop, cat, cnd_or2)}
          res = res_bkup
          res2.each{|cat2, (min, max)|
            cat = cat2
            if cnd == :not then
              switch_min.call(max, true)
              switch_max.call(min, true)
            else
              switch_min.call(min)
              switch_max.call(max)
            end
          }
        end
      else
        switch_min.call(props)
        switch_max.call(props)
      end
    }
    iter_proc.call(type_opts, :root)
    res 
  }
  find_element = proc{|type_opts, k, elm_default|
    elm_default ||= []
    res = {:root => nil}
    iter_proc = proc{|props, cat, cnd_or|
      add = proc{|item|
        res[cat] = unless res[cat] then
          item
        else
          a, b = [res[cat], item].collect{|v|
            case v
            when String
              next v.each_char.to_a
            when Range
              next Range::new("#{v.first}", "#{v.last}").to_a
            end if k == :from
            v.to_a rescue [v]
          }
          a.send(cnd_or ? :| : :&, b).sort
        end
      }
      case props
      when Hash
        if props[:root] then
          res[:additional] = nil
          iter_proc.call(props[:root], cat, cnd_or)
          iter_proc.call(props[:additional], :additional, cnd_or)
        elsif props[k] then
          [props[k]].flatten(1).each{|prop|
            iter_proc.call(prop, cat, true)
          }
        elsif (cnd = ([:and, :or, :not] & props.keys)[0]) then
          res_bkup = res
          res2 = res = {cat => nil}
          cnd_or2 = (cnd != :and)
          props[cnd].each{|prop| iter_proc.call(prop, cat, cnd_or2)}
          res = res_bkup
          res2.each{|cat2, item|
            cat = cat2
            if (cnd == :not) then
              a, b = [res[cat] || elm_default, item].collect{|v| v.to_a rescue [v]}
              res[cat] = a - b
            else
              add.call(item)
            end
          }
        end
      else
        add.call(props)
      end
    }
    iter_proc.call(type_opts, :root)
    [:root, :addtional].each{|cat|
      res[cat] ||= elm_default if res.keys.include?(cat)
    }
    tbl_root = res[:root].to_a
    unless res[:additional] then
      res.define_singleton_method(:index){|v|
        raise unless idx = tbl_root.find_index(v)
        [idx]
      }
    else
      tbl_additional = res[:additional].to_a
      res.define_singleton_method(:index){|v|
        indices = [tbl_root.find_index[v], tbl_additional.find_index(v)]
        raise if indices.any?
        indices
      }
    end
    res
  }
  
  # This proc is useless because assumed automatic tagging 
  # does not require to re-ordering based on tags 
  # derived from manual tags and class numbers
  # @see https://stackoverflow.com/a/31450137
  get_universal_class_number = proc{|type|
    next get_universal_class_number.call(type[1][:root][0][:type]) if type[0] == :CHOICE
    { # @see Table.1 unless any comment
      :BOOLEAN => 1,
      :INTEGER => 2,
      :BIT_STRING => 3,
      :OCTET_STRING => 4,
      :NULL => 5,
      :ENUMERATED => 10,
      :SEQUENCE => 16,
      :IA5String => 22, # @see Table.6
      :VisibleString => 26, # @see Table.6
      :UTCTime => 23, # @see 43.3
    }[type[0]]
  }
  
  prepare_coding = proc{|tree|
    next tree.each{|k, v| prepare_coding.call(v)} unless tree[:type]

    type = tree[:type][0]
    opts = tree[:type][1] = reduce_constraint.call(tree[:type][1])
    
    case type
    when :BOOLEAN
    when :INTEGER
      opts[:value_range] = find_range.call(opts, :value)
    when :ENUMERATED
      opts[:encoded] = {}
      [:root, :additional].each{|k|
        next unless opts[k]
        opts[:encoded][k] = opts[k].to_a.sort{|(k_a, v_a), (k_b, v_b)|
          v_a <=> v_b
        }.collect{|k, v| k}
      }
      opts[:encoded].define_singleton_method(:belong_to){|k|
        if (i = self[:root].find_index(k)) then
          next [self[:additional] ? :root : true, i]
        elsif (i = (self[:additional] || []).find_index(k)) then
          next [:additional, i]
        end
        []
      }
    when :BIT_STRING, :OCTET_STRING
      opts[:size_range] = find_range.call(opts, :size)
    when :SEQUENCE
      (opts[:root] + (opts[:extension] || [])).each.with_index{|v, i|
        v[:name] = v[:name] ? v[:name].to_sym : i
        prepare_coding.call(v)
      }
    when :SEQUENCE_OF
      opts[:size_range] = find_range.call(opts, :size)
      prepare_coding.call(opts)
    when :CHOICE
      # Skip reordering based on automatic tagging assumption
      (opts[:root] + (opts[:extension] || [])).each.with_index{|v, i|
        v[:name] = v[:name] ? v[:name].to_sym : i
        prepare_coding.call(v)
      }
    when :IA5String, :VisibleString
      opts[:size_range] = find_range.call(opts, :size)
      opts[:character_table] = find_element.call(
          opts, :from, {
            :IA5String => ("\x0".."\x7F"),
            :VisibleString => ("\x20".."\x7E"),
          }[type])
    when :UTCTime
      props = [:VisibleString, opts]
      prepare_coding.call({:type => props})
      opts.merge!(props[1])
    when :NULL
    else
      raise
    end
  }
  prepare_coding.call(root)
}
resolve_tree.call(upl)

generate_skelton = proc{|tree|
  if tree[:type] then
    type, opts = tree[:type]
    case type
    when :BOOLEAN
      true
    when :INTEGER
      opts[:value_range][:root].first rescue 0
    when :ENUMERATED
      opts[:encoded][:root][0]
    when :BIT_STRING, :OCTET_STRING
      {:BIT_STRING => [0], :OCTET_STRING => [0xFF]}[type] \
          * (opts[:size_range][:root].first rescue 0)
    when :SEQUENCE
      Hash[*((opts[:root] + (opts[:extension] || [])).collect{|v|
        next if (v[:optional] || v[:default])
        [v[:name], generate_skelton.call(v)]
      }.compact.flatten(1))]
    when :SEQUENCE_OF
      v = Marshal::dump(generate_skelton.call(opts))
      (opts[:size_range][:root].first rescue 0).times.collect{
        Marshal::load(v)
      }
    when :CHOICE
      Hash[*((opts[:root] + (opts[:extension] || [])).collect.with_index{|v, i|
        [v[:name], generate_skelton.call(v)]
      }.flatten(1))]
    when :IA5String, :VisibleString
      opts[:character_table][:root].first * (opts[:size_range][:root].first rescue 0)
    when :UTCTime
      Time::now #.utc.strftime("%y%m%d%H%MZ")
    when :NULL
      nil
    else
      raise
    end
  else
    Hash[*(tree.collect{|k, v|
      [k, generate_skelton.call(v)]
    }.flatten(1))]
  end
}

require_relative '../asn1/per'

encoder = PER::Basic_Unaligned::Encoder
encode_opentype = proc{|bits| # 10.2
  q, r = bits.length.divmod(8)
  if r != 0 then
    bits += "0" * (8 - r)
    q += 1
  end
  encoder.length_normally_small_length(q) + bits
}
encode = proc{|tree, data|
  if tree[:type] then
    type, opts = tree[:type]
    case type
    when :BOOLEAN
      data ? "1" : "0"
    when :INTEGER
      mark, (min, max) = case (cat = opts[:value_range].belong_to(data))
      when :additional # 12.1
        ["1"]
      else
        [cat == :root ? "0" : "", opts[:value_range][:root]]
      end
      bits = if min then
        if max then
          (min == max) ? "" : encoder.constrainted_whole_number2(data, min, max)
        else
          encoder.semi_constrained_whole_number(data, min)
        end
      else
        encoder.unconstrained_whole_number(data)
      end
      "#{mark}#{bits}"
    when :ENUMERATED
      cat, idx = opts[:encoded].belong_to(data)
      if cat == :additional then
        "1#{encoder.normally_small_non_negative_whole_number(idx)}"
      else
        "#{'0' if cat == :root}#{encoder.constrainted_whole_number2(idx, 0, opts[:encoded][:root].size-1)}"
      end
    when :BIT_STRING, :OCTET_STRING
      res, (lb, ub) = case (cat = opts[:size_range].belong_to(data.size))
      when :additional # 15.6, 16.3
        ['1']
      else
        [cat == :root ? '0' : '', opts[:size_range][:root]]
      end
      lb ||= 0
      bits = {:BIT_STRING => 1, :OCTET_STRING => 8}[type]
      if ub == 0 then # 15.8, 16.5
        data = []
      elsif (lb == ub) && (ub < (1 << 16)) then # 15.9-10, 16.6-7
        data += ([0] * (ub - data.size))
      else # 15.11, 16.8
        if ub && (ub < (1 << 16)) then
          res += encoder.constrainted_whole_number2(data.size, lb, ub)
        else
          res += encoder.semi_constrained_whole_number(data.size, lb)
        end
      end
      res += data.collect{|v| "%0#{bits}b"%[v]}.join
    when :SEQUENCE
      opt_def_flags, root_encoded = opts[:root].collect{|v| # 18.2
        has_elm = data.include?(v[:name])
        elm = data[v[:name]]
        if v[:default] then # 18.2
          (has_elm && (v[:default] != elm)) ? ["1", encode.call(v, elm)] : ["0", nil]
        elsif v[:optional] then
          has_elm ? ["1", encode.call(v, elm)] : ["0", nil]
        else
          raise unless has_elm
          [nil, encode.call(v, elm)]
        end
      }.transpose.each{|ary| ary.compact}
      raise if opt_def_flags.size > (1 << 16) # 18.3

      ext_bit, ext_encoded = if opts[:extension] then
        flags, args_list = opts[:extension].collect{|v|
          (elm = data[v[:name]]) ? ['1', [v, elm]] : ['0', nil]
        }.transpose
        (args_list ||= []).compact!
        unless args_list.empty? then # 18.1
          ['1', "#{ # 18.8
            encoder.length_normally_small_length(args_list.size)
          }#{
            flags.join # 18.7
          }#{
            args_list.collect{|args|
              encode_opentype(encode.call(*args)) # 18.9
            }.join
          }"]
        else
          '0'
        end
      end

      "#{ext_bit}#{opt_def_flags.join}#{root_encoded.join}#{ext_encoded}"
    when :SEQUENCE_OF
      case (cat = opts[:size_range].belong_to(data.size))
      when :additional
        "1" + encoder.semi_constrained_whole_number(
            data.size, opts[:size_range][:additional][0] || 0) # 19.4
      else
        lb, ub = opts[:size_range][:root]
        lb ||= 0
        "#{'0' if cat == :root}#{
            if (lb != ub) || (ub >= (1 << 16)) then # 19.6
          ub \
              ? encoder.constrainted_whole_number2(data.size, lb, ub) \
              : encoder.semi_constrained_whole_number(data.size, lb)
        end}"
      end + data.collect{|v|
        encode.call(opts, v)
      }.join
    when :CHOICE
      res = ""
      root_i_lt = opts[:root].size
      opts[:root].each.with_index.any?{|v, i|
        next false unless data.include?(k = v[:name])
        res += "0" if opts[:extension] # 22.5
        if root_i_lt > 1 then
          res += encoder.constrainted_whole_number2(i, 0, root_i_lt - 1) # 22.6
        end
        res += encode.call(v, data[k])
      } || (opts[:extension] || []).each.with_index.any?{|v, i|
        next false unless data.include?(k = v[:name])
        res += "1" # 22.5
        res += encoder.normally_small_non_negative_whole_number(i) # 22.8
        res += encode_opentype(encode.call(v, data[k]))
      } || raise
      res
    when :IA5String, :VisibleString
      tbl_all = opts[:character_table]
      idx_root, idx_additional = data.each_char.collect{|char|
        tbl_all.index(char)
      }.transpose
      ext_bit, (alb, aub) = case (cat_size =
          opts[:size_range].belong_to(data.size))
      when :additional
        ["1", opts[:size_range][:additional]]
      else
        [((cat_size == :root) || idx_additional) \
              ? (idx_root.all? ? "0" : "1") : "",
            opts[:size_range][:root]]
      end
      idx, tbl = if (ext_bit == "1") && idx_additional then
        [idx_additional, tbl_all[:additional]]
      else
        [idx_root, tbl_all[:root]]
      end
      b = Math::log2(tbl.to_a.size).ceil # 27.5.2
      "#{ext_bit}#{
        alb ||= 0 # 27.3
        # 27.5.6(=10.9.4.1) & 27.5.7 -> 10.9.4
        str = encoder.send(*(aub \
            ? [:length_constrained_whole_number, data.size, alb..aub] \
            : [:length_otherwise, data.size]))
        str
      }#{idx.collect{|i|
        encoder.non_negative_binary_integer2(i, b) # 27.5.4
      }.join}"
    when :UTCTime
      encode.call(
          {:type => [:VisibleString, opts]},
          data.getutc.strftime("%y%m%d%H%M%SZ"))
    when :NULL
      ''
    else
      raise
    end
  else
    tree.collect{|k, v|
      encode.call(v, data[k])
    }.join
  end
}

decoder = PER::Basic_Unaligned::Decoder
decode_opentype = proc{|str| # 10.2
  str.slice!(0, decoder.length_normally_small_length(str) * 8)
}
decode = proc{|tree, str|
  if tree[:type] then
    type, opts = tree[:type]
    case type
    when :BOOLEAN
      str.slice!(0) == "1"
    when :INTEGER
      min, max = if opts[:value_range][:additional] && (str.slice!(0) == "1") then
        opts[:value_range][:additional]
      else
        opts[:value_range][:root]
      end
      if min then
        if max then
          (min == max) ? min : decoder.constrainted_whole_number2(str, min, max)
        else
          decoder.semi_constrained_whole_number(str, min)
        end
      else
        decoder.unconstrained_whole_number(str)
      end
    when :ENUMERATED
      tbl_additional = opts[:encoded][:additional]
      if tbl_additional && (str.slice!(0) == "1") then
        tbl_additional[
            decoder.normally_small_non_negative_whole_number(str)]
      else
        tbl_root = opts[:encoded][:root]
        tbl_root[
            decoder.constrainted_whole_number2(str, 0, tbl_root.size-1)]
      end
    when :BIT_STRING, :OCTET_STRING
      lb, ub = if opts[:size_range][:additional] && (str.slice!(0) == "1") then
        [] # 15.6, 16.3
      else
        opts[:size_range][:root]
      end
      lb ||= 0
      bits = {:BIT_STRING => 1, :OCTET_STRING => 8}[type]
      len = if ub == 0 then # 15.8, 16.5
        0
      elsif (lb == ub) && (ub < (1 << 16)) then # 15.9-10, 16.6-7
        ub
      else # 15.11, 16.8
        if ub && (ub < (1 << 16)) then
          decoder.constrainted_whole_number2(str, lb, ub)
        else
          decoder.semi_constrained_whole_number(str, lb)
        end
      end
      str.slice!(0, bits * len).scan(/.{#{bits}}/).collect{|chunk| chunk.to_i(2)}
    when :SEQUENCE
      has_extension = (opts[:extension] && (str.slice!(0) == '1'))
      res = Hash[*(
        opts[:root].collect{|v| [v[:name], v[:default]] if v[:default]}.compact.flatten(1)
      )].merge(Hash[*(opts[:root].select{|v| # 18.2
        (v[:default] || v[:optional]) ? (str.slice!(0) == '1') : true
      }.collect{|v|
        [v[:name], decode.call(v, str)]
      }.flatten(1))])
      res.merge!(Hash[*(
          decoder.length_normally_small_length(str).times.collect{
            str.slice!(0) == '1'
          }.zip(opts[:extension]).collect{|has_elm, v|
            next unless has_elm
            [v[:name], decode.call(v, decode_opentype(str))]
          }.compact.flatten(1))]) if has_extension
      res
    when :SEQUENCE_OF
      (if opts[:size_range][:additional] && str.slice!(0) then
        decoder.semi_constrained_whole_number(
            str, opts[:size_range][:additional][0] || 0)
      else
        lb, ub = opts[:size_range][:root]
        lb ||= 0
        if (lb != ub) || (ub >= (1 << 16)) then # 19.6
          ub \
              ? decoder.constrainted_whole_number2(str, lb, ub) \
              : decoder.semi_constrained_whole_number(str, lb)
        else
          lb
        end
      end).times.collect{decode.call(opts, str)}
    when :CHOICE
      if opts[:extension] && (str.slice!(0) == '1') then
        i = decoder.normally_small_non_negative_whole_number(str) # 22.8
        v = opts[:extension][i]
        {v[:name] => decode.call(v, decode_opentype(str))}
      else
        root_i_lt = opts[:root].size
        i = if root_i_lt > 1 then
          decoder.constrainted_whole_number2(str, 0, root_i_lt - 1) # 22.6
        else
          0
        end
        v = opts[:root][i]
        {v[:name] => decode.call(v, str)}
      end
    when :IA5String, :VisibleString
      tbl = opts[:character_table][:additional]
      alb, aub = if (tbl || opts[:size_range][:additional]) \
          && (str.slice!(0) == '1') then
        tbl ||= opts[:character_table][:root]
        opts[:size_range][:additional]
      else
        tbl = opts[:character_table][:root]
        opts[:size_range][:root]
      end
      alb ||= 0 # 27.3
      tbl = tbl.to_a
      b = Math::log2(tbl.size).ceil # 27.5.2
      
      # 27.5.6(=10.9.4.1) & 27.5.7 -> 10.9.4
      len = decoder.send(*(aub \
          ? [:length_constrained_whole_number, str, alb..aub] \
          : [:length_otherwise, str]))
      len.times.collect{
        tbl[decoder.non_negative_binary_integer(str, b)] # 27.5.4
      }.join
    when :UTCTime
      raise unless /^(\d{10})(\d{2})?(?:Z|([\+\-]\d{4}))$/ =~ decode.call(
          {:type => [:VisibleString, opts]},
          str)
      args = 5.times.collect{|i| $1[i * 2, 2].to_i}
      args[0] += 2000
      args << $2.to_i if $2
      res = Time::gm(*args)
      res += ($3[0, 3].to_i * 60 + $3[3, 2].to_i) if $3
      res
      # data.getutc.strftime("%y%m%d%H%M%SZ")
    when :NULL
    else
      raise
    end
  else
    Hash[*(tree.collect{|k, v|
      [k, decode.call(v, str)]
    }.flatten(1))]
  end
}

=begin
UPL: User Plane Location
ULP: UserPlane Location Protocol
=end

module GPS_PVT
end

GPS_PVT::UPL = Module::new{
define_method(:generate_skelton){|k_cmd|
  res = generate_skelton.call(upl[:ULP][:"ULP-PDU"])
  res[:message].reject!{|k, v|
    "ms#{k_cmd}".to_sym != k
  }
  res[:version][:maj] = 1
  res
}
define_method(:encode){|cmd|
  if (pos_payload = (cmd[:message][:msSUPLPOS][:posPayLoad] rescue nil)) \
      && pos_payload[:rrlpPayload].kind_of?(Hash) then
    pos_payload[:rrlpPayload] = encode.call(
        upl[:"RRLP-Messages"][:PDU], pos_payload[:rrlpPayload]).scan(/.{1,8}/).tap{|buf|
      buf[-1] += "0" * (8 - buf[-1].length)
    }.collect{|str| str.to_i(2)} # covert to OctetString
  end
  buf = encode.call(upl[:ULP][:"ULP-PDU"], cmd).scan(/.{1,8}/)
  buf[-1] += "0" * (8 - buf[-1].length)
  (buf.length.divmod(1 << 8) + buf[2..-1].collect{|str| str.to_i(2)}).pack("C*")
} 
define_method(:decode){|str|
  res = decode.call(upl[:ULP][:"ULP-PDU"], str.unpack("C*").collect{|v| "%08b" % [v]}.join)
  if (rrlp = (res[:message][:msSUPLPOS][:posPayLoad][:rrlpPayload] rescue nil)) then
    rrlp.define_singleton_method(:decode){
      decode.call(upl[:"RRLP-Messages"][:PDU], self.collect{|v| "%08b" % [v]}.join)
    }
  end
  res
}
module_function(:generate_skelton, :encode, :decode)
}
