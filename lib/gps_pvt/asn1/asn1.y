class ASN1::Parser

  start ModuleDefinitionList

rule

  ModuleDefinitionList :
      ModuleDefinition
      | ModuleDefinitionList ModuleDefinition {result.merge!(val[1])}
  
  # 11.4
  valuereference : identifier

  # 11.5
  modulereference : typereference

  # 12. Module definition
  ModuleDefinition : 
      ModuleIdentifier
      DEFINITIONS
      TagDefault
      ExtensionDefault
      ASSIGN
      BEGIN
      ModuleBody
      END
      {
        result = {val[0] => val[6]}
      }

  ModuleIdentifier : modulereference DefinitiveIdentifier

  DefinitiveIdentifier : LBRACE DefinitiveObjIdComponentList RBRACE |

  DefinitiveObjIdComponentList :
      DefinitiveObjIdComponent
      | DefinitiveObjIdComponent DefinitiveObjIdComponentList

  DefinitiveObjIdComponent :
      NameForm
      | DefinitiveNumberForm
      | DefinitiveNameAndNumberForm

  DefinitiveNumberForm : number
  
  TagDefault :
      EXPLICIT TAGS {raise} # not supported
      | IMPLICIT TAGS {raise} # not supported
      | AUTOMATIC TAGS
      | {raise} # not supported
  
  ExtensionDefault :
      EXTENSIBILITY IMPLIED
      |
  
  ModuleBody :
      Exports Imports AssignmentList {result = val[2]}
      |
  
  Exports :
      EXPORTS SymbolsExported SEMICOLON
      | EXPORTS ALL SEMICOLON
      |
  
  SymbolsExported :
      SymbolList
      | 
  
  Imports :
      IMPORTS SymbolsImported SEMICOLON
      | 
  
  SymbolsImported :
      SymbolsFromModuleList
      | 
  
  SymbolsFromModuleList :
      SymbolsFromModule
      | SymbolsFromModuleList SymbolsFromModule
  
  SymbolsFromModule : SymbolList FROM GlobalModuleReference
  
  GlobalModuleReference : modulereference AssignedIdentifier
  
  AssignedIdentifier :
      ObjectIdentifierValue
      | DefinedValue
      |
  
  SymbolList :
      Symbol
      | SymbolList COMMA Symbol
  
  Symbol :
      Reference
      | ParameterizedReference
  
  Reference :
      typereference
      | valuereference
      | objectclassreference
      | objectreference
      | objectsetreference

  AssignmentList :
      Assignment
      | AssignmentList Assignment {result = result.merge(val[1])}
   
  Assignment :
      TypeAssignment
      | ValueAssignment
      #| XMLValueAssignment
      /*| ValueSetTypeAssignment
      | ObjectClassAssignment
      | ObjectAssignment
      | ObjectSetAssignment
      | ParameterizedAssignment*/

  # 13. Referencing type and value definitions
  DefinedType :
      /*ExternalTypeReference
      |*/ Typereference
      | ParameterizedType
      | ParameterizedValueSetType
  /*
  DefinedValue :
      ExternalValueReference
      | Valuereference
      | ParameterizedValue
  */
  DefinedValue : {raise}

  # 15. Assigning types and values
  TypeAssignment : typereference ASSIGN Type { # 15.1
    result = {val[0] => val[2]}
  }
  
  ValueAssignment : valuereference Type ASSIGN Value { # 15.2
    result = {val[0] => val[1].merge({:value => val[3]})}
  }
  
  ValueSetTypeAssignment : typereference Type ASSIGN ValueSet # 15.6
  
  ValueSet : LBRACE ElementSetSpecs RBRACE # 15.7

  # 16. Definition of types and values
  Type : # 16.1
      BuiltinType {
        result = {:type => val[0]} if val[0].kind_of?(Symbol) 
      }
      | ReferencedType {result = {:typeref => val[0]}}
      | ConstrainedType
  
  BuiltinType : # 16.2
      BitStringType
      | BooleanType
      | CharacterStringType
      | ChoiceType
      #| EmbeddedPDVType
      | EnumeratedType
      #| ExternalType
      | InstanceOfType
      | IntegerType
      | NullType
      | ObjectClassFieldType
      | ObjectIdentifierType
      | OctetStringType
      | RealType
      #| RelativeOIDType
      | SequenceType
      | SequenceOfType
      #| SetType
      #| SetOfType
      | TaggedType
      | UTCTime # 43. Universal time

  ReferencedType : # 16.3
      DefinedType
      | UsefulType
      #| SelectionType
      | TypeFromObject
      | ValueSetFromObjects
      
  NamedType : identifier Type {result = {:name => val[0]}.merge(val[1])} # 16.5

  Value : # 16.7
      BuiltinValue
      #| ReferencedValue
      | ObjectClassFieldValue

  BuiltinValue : # 16.9
      BitStringValue
      | BooleanValue
      | CharacterStringValue
      | ChoiceValue
      #| EmbeddedPDVValue
      | EnumeratedValue
      #| ExternalValue
      #| InstanceOfValue
      | IntegerValue
      | NullValue
      | ObjectIdentifierValue
      | OctetStringValue
      | RealValue
      #| RelativeOIDValue
      | SequenceValue
      | SequenceOfValue
      #| SetValue
      #| SetOfValue
      #| TaggedValue

  #ReferencedValue : DefinedValue | ValueFromObject # 16.11
  #ReferencedValue : identifier
  
  # 17. Notation for the boolean type
  BooleanType : BOOLEAN
  BooleanValue : TRUE | FALSE
  
  # 18. Notation for the integer type
  IntegerType :
      INTEGER {result = {:type => val[0]}}
      | INTEGER LBRACE NamedNumberList RBRACE {result = {:type => [val[0], {:list => val[2]}]}}
  NamedNumberList :
      NamedNumber {result = val[0]}
      | NamedNumberList COMMA NamedNumber {result.merge!(val[2])}
  NamedNumber :
      identifier LCBRACE SignedNumber RCBRACE {result = {val[0] => val[2]}}
      | identifier LCBRACE DefinedValue RCBRACE
  SignedNumber :
      number
      | MINUS number {result = -val[1]}
      
  IntegerValue :
      SignedNumber
      | identifier

  # 19. Notation for the enumerated type
  EnumeratedType :
      ENUMERATED LBRACE Enumerations RBRACE {
        array = (val[2][0][0].clone rescue [])
        val[2][0][1].each{|k, i| array.insert(i, k)} rescue nil
        root_sorted = array.clone
        additional_keys = []
        val[2][1][0].each{|k|
          additional_keys << (array[array.find_index(nil) || array.size] = k)
        } rescue nil
        val[2][1][1].each{|k, i|
          raise if array[i]
          additional_keys << (array[i] = k)
        } rescue nil
        result = {:type => [val[0], {
          :root => Hash[*(root_sorted.collect.with_index{|k, i|
            k ? [k, i] : nil
          }.compact.flatten(1))]
        }]}
        result[:type][1][:additional] = Hash[*(additional_keys.collect{|k|
          [k, array.find_index(k)]
        }.flatten(1))] if val[2][1]
      }
  /*
  Enumerations :
      RootEnumeration
      | RootEnumeration COMMA ELLIPSIS ExceptionSpec
      | RootEnumeration COMMA ELLIPSIS ExceptionSpec COMMA AdditionalEnumeration
  RootEnumeration : Enumeration
  AdditionalEnumeration : Enumeration
  */
  Enumerations : # work around version
      Enumeration {result = [val[0]]}
      | Enumeration COMMA ELLIPSIS ExceptionSpec
          {result = [val[0], []]}
      | Enumeration COMMA ELLIPSIS ExceptionSpec
          COMMA Enumeration
          {result = [val[0], val[5]]}
  Enumeration :
      EnumerationItem {
        result = [[], {}]
        val[0].kind_of?(Symbol) ? (result[0] << val[0]) : result[1].merge!(val[0])
      }
      | Enumeration COMMA EnumerationItem {
        val[2].kind_of?(Symbol) ? (result[0] << val[2]) : result[1].merge!(val[2])
      }
  EnumerationItem :
      identifier
      | NamedNumber
  
  EnumeratedValue : identifier
  
  # 20. Notation for the real type
  RealType : REAL
  
  RealValue :
      NumericRealValue
      | SpecialRealValue
  NumericRealValue :
      realnumber 
      | MINUS realnumber
      | SequenceValue
  SpecialRealValue : PLUS_INFINITY | MINUS_INFINITY
  
  # 21. Notation for the bitstring
  BitStringType :
      BIT STRING {result = {:type => :BIT_STRING}}
      | BIT STRING LBRACE NamedBitList RBRACE {result = {:type => [:BIT_STRING, {:list => val[3]}]}}
  NamedBitList :
      NamedBit {result = val[0]}
      | NamedBitList COMMA NamedBit {result.merge!(val[2])}
  NamedBit :
      identifier LCBRACE number RCBRACE {result = {val[0] => val[2]}}
      | identifier LCBRACE DefinedValue RCBRACE {result = {val[0] => val[2]}}
  
  BitStringValue :
      bstring
      | hstring
      | LBRACE IdentifierList RBRACE
      | LBRACE RBRACE
      | CONTAINING Value
  IdentifierList :
      identifier
      | IdentifierList COMMA identifier
  
  # 22. Notation for the octetstring type
  OctetStringType : OCTET STRING {result = {:type => :OCTET_STRING}}
  OctetStringValue :
      bstring
      | hstring
      | CONTAINING Value
  
  # 23. Notation for the null type
  NullType : NULL
  NullValue : NULL
  
  # 24. Notation for sequence types
  SequenceType :
      /*SEQUENCE LBRACE RBRACE
      | SEQUENCE LBRACE ExtensionAndException OptionalExtensionMarker RBRACE
      |*/ SEQUENCE LBRACE ComponentTypeLists RBRACE {result = {:type => [val[0], val[2]]}}
  /*
  ExtensionAndException :
      ELLIPSIS
      | ELLIPSIS ExceptionSpec
  OptionalExtensionMarker :
      COMMA ELLIPSIS
      |
  ComponentTypeLists :
      RootComponentTypeList
      | RootComponentTypeList
        COMMA ExtensionAndException ExtensionAdditions OptionalExtensionMarker
      | RootComponentTypeList
        COMMA ExtensionAndException ExtensionAdditions ExtensionEndMarker
        COMMA RootComponentTypeList
      | ExtensionAndException ExtensionAdditions ExtensionEndMarker
        COMMA RootComponentTypeList
      | ExtensionAndException ExtensionAdditions OptionalExtensionMarker
  RootComponentTypeList : ComponentTypeList
  ExtensionEndMarker : COMMA ELLIPSIS
  */
  ComponentTypeLists : # work around version
      /* empty */ {result = {:root => []}}
      | ComponentTypeList {result = {:root => val[0]}}
      | ComponentTypeList COMMA ELLIPSIS ExceptionSpec ExtensionAdditions
          {result = {:root => val[0], :extension => val[4]}}
      | ComponentTypeList COMMA ELLIPSIS ExceptionSpec ExtensionAdditions
          COMMA ELLIPSIS
          {result = {:root => val[0], :extension => val[4]}}
      | ComponentTypeList COMMA ELLIPSIS ExceptionSpec ExtensionAdditions
          COMMA ELLIPSIS COMMA ComponentTypeList
          {result = {:root => val[0] + val[8], :extension => val[4]}}
      | ELLIPSIS ExceptionSpec
          {result = {:root => [], :extension => []}}
      | ELLIPSIS ExceptionSpec COMMA ELLIPSIS
          {result = {:root => [], :extension => []}}
      | ELLIPSIS ExceptionSpec ExtensionAdditions
          {result = {:root => [], :extension => val[2]}}
      | ELLIPSIS ExceptionSpec ExtensionAdditions COMMA ELLIPSIS
          {result = {:root => [], :extension => val[2]}}
      | ELLIPSIS ExceptionSpec ExtensionAdditions COMMA ELLIPSIS
          COMMA ComponentTypeList
          {result = {:root => val[6], :extension => val[2]}}
  ExtensionAdditions :
      COMMA ExtensionAdditionList {result = val[1]}
      | {result = []}
  ExtensionAdditionList :
      ExtensionAddition {result = [val[0]]}
      | ExtensionAdditionList COMMA ExtensionAddition {result << val[2]}
  ExtensionAddition :
      ComponentType
      | ExtensionAdditionGroup
  ExtensionAdditionGroup :
      LVBRACKET VersionNumber ComponentTypeList RVBRACKET {raise} # Not supported
  VersionNumber :
      | number COLON
  ComponentTypeList :
      ComponentType {result = [val[0]]}
      | ComponentTypeList COMMA ComponentType {result << val[2]}
  ComponentType :
      NamedType
      | NamedType OPTIONAL {result = val[0].merge({:optional => true})}
      | NamedType DEFAULT Value {result = val[0].merge({:default => val[2]})}
      | COMPONENTS OF Type
  
  SequenceValue :
      LBRACE ComponentValueList RBRACE
      | LBRACE RBRACE
  ComponentValueList :
      NamedValue
      | ComponentValueList COMMA NamedValue

  # 25 Notation for sequence-of types
  SequenceOfType :
      SEQUENCE OF SequenceOfType_t {
        result = {:type => ["#{val[0]}_#{val[1]}".to_sym, val[2]]}
      }
  SequenceOfType_t : Type | NamedType
  
  SequenceOfValue :
      LBRACE ValueList RBRACE 
      | LBRACE NamedValueList RBRACE
      | LBRACE RBRACE
  ValueList :
      Value 
      | ValueList COMMA Value
  NamedValueList :
      NamedValue
      | NamedValueList COMMA NamedValue

  # 28. Notation for choice types
  ChoiceType : CHOICE LBRACE AlternativeTypeLists RBRACE {
    result = {:type => [val[0], val[2]]}
  }
  /*
  AlternativeTypeLists :
      RootAlternativeTypeList
      | RootAlternativeTypeList
        COMMA ExtensionAndException ExtensionAdditionAlternatives OptionalExtensionMarker
  RootAlternativeTypeList : AlternativeTypeList
  */
  AlternativeTypeLists : # work around version
      AlternativeTypeList {result = {:root => val[0]}}
      | AlternativeTypeList COMMA ELLIPSIS ExceptionSpec ExtensionAdditionAlternatives
          {result = {:root => val[0], :extension => val[4]}}
      | AlternativeTypeList COMMA ELLIPSIS ExceptionSpec ExtensionAdditionAlternatives
          COMMA ELLIPSIS
          {result = {:root => val[0], :extension => val[4]}}
  ExtensionAdditionAlternatives :
      COMMA ExtensionAdditionAlternativesList {result = val[1]}
      | {result = []}
  ExtensionAdditionAlternativesList :
      ExtensionAdditionAlternative {result = [val[0]]}
      | ExtensionAdditionAlternativesList COMMA ExtensionAdditionAlternative {result << val[2]}
  ExtensionAdditionAlternative :
      ExtensionAdditionAlternativesGroup
      | NamedType
  ExtensionAdditionAlternativesGroup :
      LVBRACKET VersionNumber AlternativeTypeList RVBRACKET {raise} # Not supported
  AlternativeTypeList :
      NamedType {result = [val[0]]}
      | AlternativeTypeList COMMA NamedType {result << val[2]}
  
  ChoiceValue : identifier COLON Value
  
  # 30. Notation for tagged types
  TaggedType :
      Tag Type
      | Tag IMPLICIT Type
      | Tag EXPLICIT Type
  Tag : LBRACKET Class ClassNumber RBRACKET
  ClassNumber :
      number
      | DefinedValue
  Class :
      UNIVERSAL
      | APPLICATION
      | PRIVATE
      |
  
  #TaggedValue : Value
  
  # 31. Notation for the object identifier type
  ObjectIdentifierType : OBJECT IDENTIFIER
  
  ObjectIdentifierValue :
      LBRACE ObjIdComponentsList RBRACE
      | LBRACKET DefinedValue ObjIdComponentsList RBRACKET
  ObjIdComponentsList :
      ObjIdComponents
      | ObjIdComponents ObjIdComponentsList
  ObjIdComponents :
      NameForm
      | NumberForm
      | NameAndNumberForm
      | DefinedValue
  NameForm : identifier
  NumberForm :
      number
      | DefinedValue
  NameAndNumberForm : identifier LCBRACE NumberForm RCBRACE
  
  # 36. Notation for character string types
  CharacterStringType :
      RestrictedCharacterStringType
      | UnrestrictedCharacterStringType
  CharacterStringValue :
      RestrictedCharacterStringValue
      | UnrestrictedCharacterStringValue
  
  # 37. Definition of restricted character string types
  RestrictedCharacterStringType :
      /*BMPString
      | GeneralString
      | GraphicString
      |*/ IA5String
      /*| ISO646String
      | NumericString
      | PrintableString
      | TeletexString
      | T61String
      | UniversalString
      | UTF8String
      | VideotexString*/
      | VisibleString
      
  RestrictedCharacterStringValue :
      cstring
      | CharacterStringList
      | Quadruple
      | Tuple
  CharacterStringList : LBRACE CharSyms RBRACE
  CharSyms :
      CharsDefn
      | CharSyms COMMA CharsDefn
  CharsDefn :
      cstring
      | Quadruple
      | Tuple
      | DefinedValue
  Quadruple : LBRACE Group COMMA Plane COMMA Row COMMA Cell RBRACE
  Group : number
  Plane : number
  Row : number
  Cell : number
  Tuple : LBRACE TableColumn COMMA TableRow RBRACE
  TableColumn : number
  TableRow : number
  
  # 40. Definition of unrestricted character string types
  UnrestrictedCharacterStringType : CHARACTER STRING
  
  UnrestrictedCharacterStringValue : SequenceValue
  
  # 41. Notation for types defined in clauses 42 to 44
  UsefulType : typereference

  # 45. Constrained types
  ConstrainedType :
      Type Constraint {
        type_name, type_opt = val[0][:type]
        type_opt = constraint_hash(type_opt ? [:and, type_opt, val[1]] : val[1])
        result = {:type => [type_name, type_opt]}
      }
      | TypeWithConstraint
  TypeWithConstraint :
      TypeWithConstraint_p TypeWithConstraint_c OF TypeWithConstraint_t {
        raise if val[0] == :SET # not supported
        result = {:type => ["#{val[0]}_OF".to_sym, val[3].merge(constraint_hash(val[1]))]}
      }
  TypeWithConstraint_p : SET | SEQUENCE
  TypeWithConstraint_c : Constraint | SizeConstraint
  TypeWithConstraint_t : Type | NamedType
  Constraint : LCBRACE ConstraintSpec ExceptionSpec RCBRACE {
    result = val[1]
  }
  ConstraintSpec :
      SubtypeConstraint
      #| GeneralConstraint
  SubtypeConstraint : ElementSetSpecs
  
  # 46. Element set specification
  ElementSetSpecs :
      RootElementSetSpec
      | RootElementSetSpec COMMA ELLIPSIS {
        result = [:extensible, val[0]]
      }
      | RootElementSetSpec COMMA ELLIPSIS COMMA AdditionalElementSetSpec {
        result = [:extensible, val[0], val[4]]
      }
  RootElementSetSpec : ElementSetSpec
  AdditionalElementSetSpec : ElementSetSpec {
    raise if val[0].flatten.include?(:extensible)
  }
  ElementSetSpec :
      Unions
      #| ALL Exclusions
      | ALL EXCEPT Elements {
        raise if val[2].flatten.include?(:extensible)
        result = case val[2][0]
          when :and; [:not, val[2]]
          when :not; (val[2][1].kind_of?(Array)) ? val[2][1] : [:or, val[2][1]]
          when :or; [:not, (val[2].size == 2) ? val[2][1] : val[2]]
        end
      }
  Unions :
      Intersections
      #| UElems UnionMark Intersections
      | Unions UnionMark Intersections {
        elms = ((val[0][0] == :or) ? val[0][1..-1] : [val[0]]) \
            + ((val[2][0] == :or) ? val[2][1..-1] : [val[2]])
        elm_hash = {}
        elms.reject!{|elm|
          elm_hash.merge!(elm){|k, v, v_|
            [v].flatten(1) + [v_].flatten(1)
          } if (elm.kind_of?(Hash) && (elm.keys.size == 1))
        }
        result = [:or] + elms + elm_hash.collect{|k, v| {k => v}}
      }
  #UElems : Unions
  Intersections :
      IntersectionElements
      #| IElems IntersectionMark IntersectionElements
      | Intersections IntersectionMark IntersectionElements {
        result = [:and] + ((val[0][0] == :and) ? val[0][1..-1] : [val[0]]) \
            + ((val[2][0] == :and) ? val[2][1..-1] : [val[2]])
      }
  #IElems : Intersections
  IntersectionElements :
      Elements
      #| Elems Exclusions
      | Elements EXCEPT Elements {
        raise if val[2].flatten.include?(:extensible)
        val[2] = case val[2][0]
          when :and; [:not, val[2]]
          when :not; (val[2][1].kind_of?(Array)) ? val[2][1] : [:or, val[2][1]]
          when :or; [:not, (val[2].size == 2) ? val[2][1] : val[2]]
        end
        result = [:and] + ((val[0][0] == :and) ? val[0][1..-1] : [val[0]]) \
            + ((val[2][0] == :and) ? val[2][1..-1] : [val[2]])
      }
  #Elems : Elements
  #Exclusions : EXCEPT Elements
  UnionMark : VBAR | UNION
  IntersectionMark : HAT | INTERSECTION
  Elements : # always return Array[op, arg[0], ...]
      SubtypeElements {result = [:or, val[0]]}
      #| ObjectSetElements
      | LCBRACE ElementSetSpec RCBRACE {result = val[1]}

  # 47. Subtype elements
  SubtypeElements :
      SingleValue               # 47.2
      #| ContainedSubtype       # 47.3
      | ValueRange              # 47.4
      | PermittedAlphabet       # 47.5
      | SizeConstraint          # 47.6
      #| TypeConstraint         # 47.7
      #| InnerTypeConstraints   # 47.8
      #| PatternConstraint      # 47.9

  SingleValue : Value {result = {:value => val[0]}}
  
  #ContainedSubtype : Includes Type
  #Includes : INCLUDES |
  
  ValueRange : LowerEndpoint RANGE_SEP UpperEndpoint {
    range = val.values_at(0, 2).collect{|item|
      item.empty? ? nil : item
    }.compact
    range = {:and => range} if range.size > 1
    ((range = (val[2][0] == :<=) \
        ? (val[0][1]..val[2][1]) \
        : (val[0][1]...val[2][1])) rescue nil) if val[0][0] == :>=
    result = {:value => range}
  }
  LowerEndpoint :
      LowerEndValue {result = (val[0] == :MIN) ? [] : [:>=, val[0]]}
      | LowerEndValue LT {result = (val[0] == :MIN) ? [] : [:>, val[0]]}
  UpperEndpoint :
      UpperEndValue {result = (val[0] == :MAX) ? [] : [:<=, val[0]]}
      | LT UpperEndValue {result = (val[0] == :MAX) ? [] : [:<, val[0]]}
  LowerEndValue : Value | MIN
  UpperEndValue : Value | MAX
  
  SizeConstraint :
      SIZE Constraint {
        iter_proc = proc{|tree|
          case tree
          when Hash
            raise unless (tree.keys - [:value]).empty?
            next {:size => tree[:value]}
          when Array
            tree[1..-1] = tree[1..-1].collect{|v| iter_proc.call(v)}
          end
          tree
        }
        result = iter_proc.call(val[1])
      }
  
  #TypeConstraint : Type
  
  PermittedAlphabet :
      FROM Constraint {
        iter_proc = proc{|tree|
          case tree
          when Hash
            raise unless (tree.keys - [:value]).empty?
            next {:from => tree[:value]}
          when Array
            tree[1..-1] = tree[1..-1].collect{|v| iter_proc.call(v)}
          end
          tree
        }
        result = iter_proc.call(val[1])
      }
  
  # 49. The exception identifier
  ExceptionSpec :
      EXCMARK ExceptionIdentification {raise} # Not implemented
      |
  ExceptionIdentification :
      SignedNumber
      | DefinedValue
      | Type COLON Value
end

---- header

require 'strscan'

---- inner

  RESERVED_WORDS = proc{
    keys =(<<-__TEXT__).gsub(/\s+/, ' ').gsub(/^\s+|\s+$/, '').split(' ')
      ABSENT ABSTRACT-SYNTAX ALL APPLICATION AUTOMATIC BEGIN BIT BMPString BOOLEAN BY
      CHARACTER CHOICE CLASS COMPONENT COMPONENTS CONSTRAINED CONTAINING DEFAULT DEFINITIONS EMBEDDED
      ENCODED END ENUMERATED EXCEPT EXPLICIT EXPORTS EXTENSIBILITY EXTERNAL FALSE FROM
      GeneralizedTime GeneralString GraphicString IA5String IDENTIFIER IMPLICIT IMPLIED IMPORTS INCLUDES INSTANCE
      INTEGER INTERSECTION ISO646String MAX MIN MINUS-INFINITY NULL NumericString OBJECT ObjectDescriptor
      OCTET OF OPTIONAL PATTERN PDV PLUS-INFINITY PRESENT PrintableString PRIVATE REAL
      RELATIVE-OID SEQUENCE SET SIZE STRING SYNTAX T61String TAGS TeletexString TRUE
      TYPE-IDENTIFIER UNION UNIQUE UNIVERSAL UniversalString UTCTime UTF8String VideotexString VisibleString WITH
__TEXT__
    Hash[*(keys.collect{|k|
      [k, k.gsub(/\-/, '_').to_sym]
    }.flatten(1))].merge({
      '[['  => :LVBRACKET,
      ']]'  => :RVBRACKET,
      '['   => :LBRACKET,
      ']'   => :RBRACKET,
      '{'   => :LBRACE,
      '}'   => :RBRACE,
      '('   => :LCBRACE,
      ')'   => :RCBRACE,
      ','   => :COMMA,
      ';'   => :SEMICOLON,
      '::=' => :ASSIGN,
      ':'   => :COLON,
      '-'   => :MINUS,
      '...' => :ELLIPSIS,
      '..'  => :RANGE_SEP,
      '|'   => :VBAR,
      '^'   => :HAT,
      '<'   => :LT,
      '!'   => :EXCMARK,
    })
  }.call

  REGEXP_PATTERN = /(?:
    (\s+|--[^\n]*|\/\*[^\*]*\*\/)
    | (#{RESERVED_WORDS.collect{|k, sym|
        Regexp::escape(k) + (k =~ /^[\w\-]+$/ ? '\b' : '')
      }.join('|')})
    | ([A-Z][-\w]+)
    | ([a-z][-\w]+)
    | (\d+)
    | \"((?:\"\"|[^\"])*)\"
  )/mxo

  def next_token
    return @stack.shift unless @stack.empty?

    while (token = @scanner.scan(REGEXP_PATTERN))
      if @scanner[1]
        next  # comment or whitespace
      elsif @scanner[2]
        return [RESERVED_WORDS[token]] * 2
      elsif @scanner[3]
        return [:typereference, token.to_sym]
      elsif @scanner[4]
        return [:identifier, token.to_sym]
      elsif @scanner[5]
        return [:number, token.to_i]
      elsif @scanner[6]
        return [:cstring, @scanner[6]]
      end

      raise #'Internal error'
    end

    return nil if @scanner.eos?

    raise "Parse error before #{@scanner.string.slice(@scanner.pos, 40)}"
  end
  
  attr_accessor :yydebug
  attr_reader :error, :backtrace

  def parse(str)
    @scanner = StringScanner::new(str)
    @stack = []
    @lastpos = 0
    @pos = 0
    
    tree = nil
    begin
      tree = do_parse
    rescue Racc::ParseError => e # ASN1Error
      @error = e.to_s
      @backtrace = e.backtrace
      return nil
    end

    return tree
  end
  
  def constraint_hash(array)
    array[1..-1] = array[1..-1].collect{|elm|
      elm.kind_of?(Array) ? constraint_hash(elm) : elm
    }
    case array[0]
    when :and
      elm_hash = {}
      array[1..-1] = array[1..-1].reject{|elm|
        if (elm.keys & [:and, :not, :or]).empty? then
          elm_hash.merge!(elm){|k, v, v_|
            {:and => (v[:and] rescue [v].flatten(1)) \
                + (v_[:and] rescue [v_].flatten(1))}
          }
        end
      } + [elm_hash]
      (array.size == 2) ? array[1] : {:and => array[1..-1]}
    when :not
      if array[1].size == 1 then
        k, v = array[1].to_a[0]
        return {k => (v[:not] rescue false) ? v[:not] : {:not => v}} \
            unless [:and, :or].include?(k)
      end
      {:not => array[1]}
    when :or
      (array.size == 2) ? array[1] : {:or => array[1..-1]}
    when :extensible
      if array[2] then # root and extensible
        keys = array[1].keys | array[2].keys
        if keys.size == 1 then
          k = keys[0]
          return {k => {:root => array[1][k], :additional => array[2][k]}} \
              unless [:and, :not, :or].include?(k)
        end
        {:root => array[1], :additional => array[2]}
      else # root only
        if array[1].size == 1 then
          k, v = array[1].to_a[0]
          return {k => (v[:root] rescue false) ? v : {:root => v}} \
              unless [:and, :not, :or].include?(k)
        end
        {:root => array[1]}
      end
    else
      raise
    end
  end

---- footer

if $0 == __FILE__ then
  require 'json'
  parser = ASN1::Parser::new
  #parser.yydebug = true
  tree = parser.parse(ARGV[0] ? open(ARGV.shift).read : $stdin)
  print JSON::pretty_generate(tree)
end
