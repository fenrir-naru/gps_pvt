module GPS_PVT
end

resolve_tree = proc{|root|
  assigned_type = {}
  assigned_const = {}
  resolved = nil
  expand_ref = proc{|child_v, path, parent|
    child_k = (path ||= [])[-1]
    case child_v
    when Hash
      keys = child_v.keys
      if child_v[:typeref] then
        keys -= [:typeref, :type]
        if child_v[:typeref].kind_of?(Array) then # imported type
          src_k = child_v[:typeref].collect!{|v| v.to_sym}
          dst_k = [path[0], child_k]
          if !assigned_type[dst_k] && assigned_type[src_k] then 
            assigned_type[dst_k] = assigned_type[src_k]
            assigned_const[dst_k] = assigned_const[src_k] if assigned_const[src_k]
            resolved += 1
          end
        elsif !child_v[:type] then
          child_v[:typeref] = child_v[:typeref].to_sym
          if (child_v[:type] = assigned_type[[path[0], child_v[:typeref]]]) then
            assigned_type[[path[0], child_k]] = child_v[:type]
            resolved += 1
          end
        end
      elsif child_v[:type] then
        type, *other = child_v[:type]
        if type.kind_of?(String) then
          child_v[:type] = [type.to_sym] + (other.empty? ? [{}] : other)
          resolved += 1
          if child_k.kind_of?(Symbol) then
            assigned_type[[path[0], child_k]] = child_v[:type]
            if child_v.keys.include?(:value) then
              assigned_const[[path[0], child_k]] = child_v[:value]
            else
              child_v[:type][1][:typename] = child_k
            end
          end
        end
      end
      keys.each{|k|
        expand_ref.call(child_v[k], path + [k], child_v)
      }
    when Array
      child_v.each.with_index{|v, i|
        expand_ref.call(v, path + [i], child_v)
      }
    when String
      if [:value, :size].any?{|k| path.include?(k)}
        src_k = [path[0], child_v.to_sym]
        if assigned_const[src_k] then
          parent[child_k] = assigned_const[src_k]
          resolved += 1
        end
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
    when Array
      props.collect!{|prop| reduce_constraint.call(prop)}
    when Hash
      props.keys.each{|k|
        props[k] = reduce_constraint.call(props[k])
      }
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
    type_opts[k] = reduce_constraint.call(type_opts[k]) if type_opts[k]
    res = {:root => []} # [min, max]
    res.define_singleton_method(:belong_to){|v|
      min, max = self[:root]
      if (!min || (min <= v)) && (!max || (max >= v)) then
        self[:additional] ? :root : true
      else
        self[:additional] ? :additional : raise
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
    type_opts[k] = reduce_constraint.call(type_opts[k]) if type_opts[k]
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
    next tree.each{|k, v|
      prepare_coding.call(v) unless [:typeref].include?(k) # skip alias
    } unless tree.include?(:type)
    next unless tree[:type] # skip undefined type
    next if tree[:typeref]

    type, opts = tree[:type]
    
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
        v[:type][1][:typename] ||= v[:name] if v[:name].kind_of?(Symbol) && v[:type] # for debugger
        v[:type] = [:SEQUENCE, {:root => v[:group]}] if v[:group]
        prepare_coding.call(v)
        v[:names] = v[:group].collect{|v2|
          # if name is not Symbol, it will be changed to [index_in_sequence, index_in_group]
          v2[:name] = [v[:name], v2[:name]] unless v2[:name].kind_of?(Symbol)
          v2[:name]
        } if v[:group]
      }
    when :SEQUENCE_OF
      opts[:size_range] = find_range.call(opts, :size)
      prepare_coding.call(opts)
    when :CHOICE
      # Skip reordering based on automatic tagging assumption
      opts[:extension] = opts[:extension].collect{|v|
        v[:group] || [v] # 22. Note says "Version brackets have no effect"
      }.flatten(1) if opts[:extension]
      (opts[:root] + (opts[:extension] || [])).each.with_index{|v, i|
        v[:name] = v[:name] ? v[:name].to_sym : i
        v[:type][1][:typename] ||= v[:name] if v[:name].kind_of?(Symbol) && v[:type] # for debugger
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

generate_skeleton = proc{|tree|
  if tree.include?(:type) then
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
        subset = generate_skeleton.call(v)
        v[:group] ? subset.to_a : [[v[:name], subset]]
      }.compact.flatten(2))]
    when :SEQUENCE_OF
      v = Marshal::dump(generate_skeleton.call(opts))
      (opts[:size_range][:root].first rescue 0).times.collect{
        Marshal::load(v)
      }
    when :CHOICE
      Hash[*((opts[:root] + (opts[:extension] || [])).collect{|v|
        [v[:name], generate_skeleton.call(v)]
      }.flatten(1))]
    when :IA5String, :VisibleString
      opts[:character_table][:root].first * (opts[:size_range][:root].first rescue 0)
    when :UTCTime
      Time::now #.utc.strftime("%y%m%d%H%MZ")
    when :NULL
      nil
    else
      p tree
      raise
    end
  else
    Hash[*(tree.collect{|k, v|
      [k, generate_skeleton.call(v)]
    }.flatten(1))]
  end
}

require_relative 'per'

encoder = GPS_PVT::PER::Basic_Unaligned::Encoder
encode_opentype = proc{|bits| # 10.2
  len_oct, r = bits.length.divmod(8)
  if r != 0 then
    bits += "0" * (8 - r)
    len_oct += 1
  end
  res, len_oct_remain = encoder.length_otherwise(len_oct) # 10.2.2 unconstrained length
  while len_oct_remain # fragmentation
    res += bits.slice!(0, (len_oct - len_oct_remain) * 8)
    len_oct = len_oct_remain
    len_enc, len_oct_remain = encoder.length_otherwise(len_oct) # 10.2.2 unconstrained length
    res += len_enc
  end
  res + bits
}
encode = proc{|tree, data|
  if tree.include?(:type) then
    type, opts = tree[:type]
    data = opts[:hook_encode].call(data) if opts[:hook_encode]
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
          elm = if v[:group] then
            data_in_group = data.select{|k2, v2| v[:names].include?(k2)}
            data_in_group.empty? ? nil : data_in_group
          else
            data[v[:name]]
          end
          elm ? ['1', [v, elm]] : ['0', nil]
        }.transpose
        # If any extension element is absent, '0' extension bit should be selected.
        # '1' extension bit with "000..." bit-fields is wrong.
        (args_list ||= []).compact!
        unless args_list.empty? then # 18.1
          ['1', "#{ # 18.8 -> 10.9
            encoder.with_length(flags.size, :length_normally_small_length).collect{|len_str, range|
              len_str + flags[range].join
            }.join # 18.7
          }#{
            args_list.collect{|args|
              encode_opentype.call(encode.call(*args)) # 18.9
            }.join
          }"]
        else
          '0'
        end
      end

      "#{ext_bit}#{opt_def_flags.join}#{root_encoded.join}#{ext_encoded}"
    when :SEQUENCE_OF
      ext_bit, len_enc = case (cat = opts[:size_range].belong_to(data.size))
      when :additional
        # 19.4 -> 10.9.4.2(semi_constrained_whole_number)
        ['1', :length_otherwise]
      else
        lb, ub = opts[:size_range][:root]
        lb ||= 0 # 19.2
        [
          cat == :root ? '0' : '',
          if (lb != ub) || (ub >= (1 << 16)) then
            # 19.6 -> 10.9.4.1(constrained_whole_number) or 10.9.4.2(semi_constrained_whole_number)
            ub \
                ? [:length_constrained_whole_number, lb..ub] \
                : :length_otherwise
          else
            ''
          end
        ]
      end
      ext_bit + encoder.with_length(data.size, *len_enc).collect{|len_str, range|
        len_str + data[range].collect{|v| encode.call(opts, v)}.join
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
        res += encode_opentype.call(encode.call(v, data[k]))
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
      
      alb ||= 0 # 27.3
      # 27.5.6(=10.9.4.1) & 27.5.7 -> 10.9.4
      len_enc = aub \
          ? [:length_constrained_whole_number, alb..aub] \
          : :length_otherwise
      ext_bit + encoder.with_length(idx.size, *len_enc).collect{|len_str, range|
        len_str + idx[range].collect{|i|
          encoder.non_negative_binary_integer2(i, b) # 27.5.4
        }.join
      }.join
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

decoder = GPS_PVT::PER::Basic_Unaligned::Decoder
decode_opentype = eval(<<-__SRC__)
proc{|str, &b| # 10.2
  len_oct, cnt = decoder.length_otherwise(str) # 10.2.2 unconstrained length
  if cnt then # fragmentation
    str_buf = str.slice!(0, len_oct * 8)
    loop{
      len_oct, cnt = decoder.length_otherwise(str)
      str_buf += str.slice!(0, len_oct * 8)
      break unless cnt
    }
    b.call(str_buf)
  else
    len_before = str.size
    res = b.call(str)
    str.slice!(0, [(len_oct * 8) - (len_before - str.size), 0].max) # erase padding
    res
  end
}
__SRC__
decode = proc{|tree, str|
  if tree.include?(:type) then
    type, opts = tree[:type]
    res = case type
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
      data = Hash[*(
        opts[:root].collect{|v| [v[:name], v[:default]] if v[:default]}.compact.flatten(1)
      )].merge(Hash[*(opts[:root].select{|v| # 18.2
        (v[:default] || v[:optional]) ? (str.slice!(0) == '1') : true
      }.collect{|v|
        [v[:name], decode.call(v, str)]
      }.flatten(1))])
      data.merge!(Hash[*(
          decoder.with_length(str, :length_normally_small_length).collect{|len|
            len.times.collect{str.slice!(0) == '1'}
          }.flatten(1).zip(opts[:extension]).collect{|has_elm, v|
            next unless has_elm
            decoded = decode_opentype.call(str){|str2| decode.call(v, str2)}
            v[:group] ? decoded.to_a : [[v[:name], decoded]]
          }.compact.flatten(2))]) if has_extension
      data
    when :SEQUENCE_OF
      len_dec = if opts[:size_range][:additional] && str.slice!(0) then
        # 19.4 -> 10.9.4.2(semi_constrained_whole_number)
        :length_otherwise
      else
        lb, ub = opts[:size_range][:root]
        lb ||= 0
        if (lb != ub) || (ub >= (1 << 16)) then
          # 19.6 -> 10.9.4.1(constrained_whole_number) or 10.9.4.2(semi_constrained_whole_number)
          ub \
              ? [:length_constrained_whole_number, lb..ub] \
              : :length_otherwise
        else
          lb
        end
      end
      decoder.with_length(str, *len_dec).collect{|len|
        len.times.collect{decode.call(opts, str)}
      }.flatten(1)
    when :CHOICE
      if opts[:extension] && (str.slice!(0) == '1') then
        i = decoder.normally_small_non_negative_whole_number(str) # 22.8
        v = opts[:extension][i]
        {v[:name] => decode_opentype.call(str){|str2| decode.call(v, str2)}}
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
      len_dec = aub \
          ? [:length_constrained_whole_number, alb..aub] \
          : :length_otherwise
      decoder.with_length(str, *len_dec).collect{|len|
        len.times.collect{
          tbl[decoder.non_negative_binary_integer(str, b)] # 27.5.4
        }
      }.join
    when :UTCTime
      raise unless /^(\d{10})(\d{2})?(?:Z|([\+\-]\d{4}))$/ =~ decode.call(
          {:type => [:VisibleString, opts]},
          str)
      args = 5.times.collect{|i| $1[i * 2, 2].to_i}
      args[0] += 2000
      args << $2.to_i if $2
      data = Time::gm(*args)
      data += ($3[0, 3].to_i * 60 + $3[3, 2].to_i) if $3
      data
    when :NULL
    else
      raise
    end
    res = opts[:hook_decode].call(res) if opts[:hook_decode]
    res
  else
    Hash[*(tree.collect{|k, v|
      [k, decode.call(v, str)]
    }.flatten(1))]
  end
}
debug_decode = proc{ # debugger
  decode_orig = decode
  check_str = proc{|str|
    history = str.history
    idx = history[:orig].size - str.size
    idx_previous = history[:index][-1]
    if idx > idx_previous then
      history[:index] << idx
      history[:orig].slice(idx_previous, idx - idx_previous)
    end
  }
  print_str = proc{|str_used, history, value|
    next unless str_used
    type, opts = (history[:parent][-1][:type] rescue nil)
    $stderr.puts [
        (" " * history[:parent].size) + str_used,
        "#{type}#{"(#{opts[:typename]})" if opts[:typename]}",
        case value
        when NilClass; nil
        when Array; "\"#{value.inspect}\""
        else; value.inspect
        end
        ].compact.join(',')
  }
  decode = proc{|tree, str|
    if !str.respond_to?(:history) then
      history = {
        :orig => str.dup,
        :index => [0],
        :parent => [tree],
      }
      str.define_singleton_method(:history){history}
    else
      history = str.history
      print_str.call(check_str.call(str), history)
      history[:parent] << tree
    end
    begin
      res = decode_orig.call(tree, str)
      print_str.call(check_str.call(str), history, res)
      res
    rescue
      type, opts = [tree.kind_of?(Hash) ? tree[:type] : nil, [nil, {}]].compact[0]
      $stderr.puts [
          "#{" " * (history[:parent].size - 1)}[error]",
          ("#{type}#{"(#{opts[:typename]})" if opts[:typename]}" if type)
          ].compact.join(',')
      raise
    ensure
      history[:parent].pop
    end
  }
}

dig = proc{|tree, *keys|
  if tree[:type] then
    type, opts = tree[:type]
    case type
    when :SEQUENCE, :CHOICE
      k = keys.shift
      elm = (opts[:root] + (opts[:extension] || [])).find{|v| v[:name] == k}
      keys.empty? ? elm : dig.call(elm, *keys)
    else
      raise
    end
  else
    elm = tree[keys.shift]
    keys.empty? ? elm : dig.call(elm, *keys)
  end
}

GPS_PVT::ASN1 = Module::new{
define_method(:resolve_tree, &resolve_tree)
define_method(:generate_skeleton, &generate_skeleton)
define_method(:encode_per, &encode)
define_method(:decode_per, &decode)
define_method(:dig, &dig)
define_method(:read_json){|*json_files|
  require 'json'
  resolve_tree(json_files.inject({}){|res, file|
    res.merge(JSON::parse(open(file).read, {:symbolize_names => true}))
  })
}
decode_orig = decode
define_method(:debug=){|bool|
  if bool then
    debug_decode.call
  else
    debug = decode_orig
  end
  bool
}
module_function(*instance_methods(false))
}
