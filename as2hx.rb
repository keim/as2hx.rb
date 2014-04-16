require 'fileutils'

def as3_to_haxe(as3code, vectorToArray=true)
  preimport = '';

  # remove head indent
  as3code.gsub!(/^\t+/){|m| m.gsub("\t", '    ')}
  as3code.gsub!(/^    /, '')
  # package
  as3code.gsub!(/package\s+([\w.]*)\s*\{/, 'package \1;')
  packageName = $1
  as3code.sub!(/^(.+)\}\s*/m, '\1')

  # types
  as3code.gsub!(/(:|as|is)(\s*)void/,        '\1\2Void')
  as3code.gsub!(/(:|as|is)(\s*)int/,         '\1\2Int')
  as3code.gsub!(/(:|as|is)(\s*)uint/,        '\1\2UInt')
  as3code.gsub!(/(:|as|is)(\s*)Number/,      '\1\2Float')
  as3code.gsub!(/(:|as|is)(\s*)Boolean/,     '\1\2Bool')
  as3code.gsub!(/(:|as|is)(\s*)(\*|Object)/, '\1\2Dynamic')
  as3code.gsub!(/('|"|<\s*)int(\s*>|'|")/,    '\1Int\2')
  as3code.gsub!(/('|"|<\s*)uint(\s*>|'|")/,   '\1UInt\2')
  as3code.gsub!(/('|"|<\s*)Number(\s*>|'|")/, '\1Float\2')
  as3code.gsub!(/('|"|<\s*)Boolean(\s*>|'|")/,'\1Bool\2')
  as3code.gsub!(/int\s*\((.+?)\)/,    'cast(\1, Int)')
  as3code.gsub!(/uint\s*\((.+?)\)/,   'cast(\1, UInt)')
  as3code.gsub!(/Number\s*\((.+?)\)/, 'cast(\1, Float)')
  as3code.gsub!(/Boolean\s*\((.+?)\)/,'cast(\1, Bool)')
  as3code.gsub!(/([\w$]+)\s+as\s+([\w$]+)/, 'cast(\1, \2)')
  as3code.gsub!(/([\w$]+)\s+is\s+([\w$]+)/, 'Std.is(\1, \2)')

  as3code.gsub!(/(\s+)isNaN(\s*\()/, '\1Math.isNaN\2')

  # vector
  if vectorToArray
    as3code.gsub!(/Vector\s*\.\s*<\s*([\w$]+)\s*>/, 'Array<\1>')
  else
    preimport += "import flash.Vector;\n" if as3code =~ /Vector\s*\.\s*</
    as3code.gsub!(/new\sVector\s*\.\s*<\s*[\w$]+\s*>\s*\((.*?)\)/, 'new Vector(\1)')
    as3code.gsub!(/Vector\s*\.\s*<\s*([\w$]+)\s*>/, 'Vector<\1>')
  end
  # array
  as3code.gsub!(/Array\((.*?)\)/, 'Array<Dynamic>(\1)')

  # namespace, scopes, getter/setter
  hasInternal = false
  getsetHash = {}
  vinitHash = {}
  #       1   2                 3           4          56             7    8               9          10                       11           12        13            14
  rex = /^(\s*(\/\*.*?\*\/)?\s*)(static\s*)?([\w$]+)\s+((var|const)\s+(.+?)(\s*:\s*[\w$]+?)(\s*=.+?;)?(\s*\/\/.*)?$|function\s*(get|set)?\s+(.+?)\s*\((.*?)\)\s*:\s*([\w$]+))/
  as3code.gsub!(rex) do |matched|
    # variables
    headSpace = $1
    isStatic = !$3.nil?
    accessType = $4
    var_or_const = $6
    var_or_const_name = $7
    variableType = $8
    variableInit = $9
    variableComm = $10
    # function
    get_or_set = $11
    func_name = $12
    func_param = $13
    func_return = $14
    # internal flags
    isConst = (var_or_const === 'const')
    staticStr = (isStatic || isConst) ? 'static ' : ''
    hasInternal ||= (accessType === 'internal')

    # static
    ret = headSpace + staticStr
    # definition
    if !var_or_const.nil?
      # scope & remove namespace
      ret += (accessType =~ /^(internal|protected|private)$/) ? 'private ' : 'public '
      # var_or_const
      if isConst
        ret += "inline var #{var_or_const_name}#{variableType}#{variableInit}#{variableComm}"
      else
        ret += "var #{var_or_const_name}#{variableType};"
        ret += variableComm if !variableComm.nil?
        vinitHash[var_or_const_name.to_sym] = variableInit
      end
    else
      # function
      func_name_sym = func_name.to_sym
      if !get_or_set.nil?
        get_or_set_s = get_or_set.to_s
        if getsetHash[func_name_sym].nil?
          getsetHash[func_name_sym] = {:get=>'null', :set=>'null'}
          returnType = func_return
          if get_or_set === 'set'
            returnType = func_param.to_s.match(/:\s*([\w$]+)/)[1]
          end
          # scope & remove namespace
          ret += (accessType =~ /internal|protected|private/) ? 'private ' : 'public '
          # getter or setter
          ret += "var #{func_name}(%get_or_set%) : #{returnType};\n#{headSpace}#{staticStr}"
        end
        # change scope
        accessType = 'private'
        # memory function name
        func_name = '__' + get_or_set_s + func_name.capitalize
        getsetHash[func_name_sym][get_or_set_s.to_sym] = func_name
      end
      # scope & remove namespace
      ret += (accessType =~ /internal|protected|private/) ? 'private ' : 'public '
      ret += "function #{func_name}(#{func_param}) : #{func_return}"
    end

    ret
  end
  preimport += "@:allow(#{packageName});\n" if hasInternal

  # rewrite getter and setter
  getsetHash.each do |func_name, get_or_set|
    func_name_s = func_name.to_s
    as3code.sub!("#{func_name_s}(%get_or_set%)") do |matched|
      func_name_s + '(' + get_or_set[:get] + ', ' + get_or_set[:set] + ')'
    end
  end

  # remove namespace
  as3code.gsub!(/use\s+namespace/, "//use namespace")
  as3code.gsub!(/([\w$]+)::/, "")

  # loop
  #   for (i=s; i<e; i++)
  as3code.gsub!(/(.*?)(for\s*\(\s*(.*?);\s*(.*?);\s*(.*?)\))/) do |matched|
    indent = $1
    all_form = $2
    start_form = $3
    end_form = $4
    iter_form = $5
    iter_form =~ /^([\w$]+)?\s*\+\+\s*([\w$]+)?/
    iter = $1 || $2
    start_form =~ /^#{iter}\s*=\s*(.+)\s*$/
    start_cond = $1
    end_form =~ /^#{iter}\s*<\s*(.+)\s*$/
    end_cond = $1
    ret = "#{indent}//#{all_form}\n"
    if !(iter.nil? || end_cond.nil? || start_cond.nil?)
      ret + "#{indent}for (#{iter} in #{start_cond}...#{end_cond})"
    else
      ret + "#{indent}#{start_form};\n#{indent}while (#{end_form}) %loop#{indent}<<#{iter_form}>>%"
    end
  end
  #   for (s;e;i) -> s; while(e){i}
  pos = 0
  while !(pos = as3code.index(/%loop(.*?)<<(.*?)>>%/, pos)).nil? do
    indent = $1
    iter_form = $2
    end_pos = pos
    nest = 0
    while !(end_pos = as3code.index(/[{}]/,end_pos)).nil? do
      end_pos
    end
  end

  #   for (i in a) -> for (i in Reflect.fields(a))
  as3code.gsub!(/(for\s*\(.*?\s+)in(\s+)(.*?)\s*\)/, '\1in\2Reflect.field(\3)')
  #   for each (i in a) -> for (i in a)
  as3code.gsub!(/for\s+each/, 'for')

  # class name
  convertTo = 'class \1'
  convertTo = preimport + "\n" + convertTo if preimport != ''
  as3code.sub!(/public\s+class\s*([\w$]+)/, convertTo)
  
  # constructor and initializer
  as3code.sub!(/([^\r\n]*?)(public\s+)?function\s+#{$1}(.*?\{.*?(super\s*\(.*?\).*?)?[\r\n]+)/m) do |matched|
    indent = $1 + '    '
    ret = "#{$1}function new#{$3}"
    if vinitHash.size > 0 
      ret += indent + "// [auto inserted] initialize variables\n"
      vinitHash.each do |key, value|
        ret += indent + key.to_s + value + "\n"
      end 
      ret += indent + "// [auto inserted] \n\n"
    end
  end
end




FileUtils.rm_r('./converted')
Dir.mkdir('./converted')
Dir.glob('./original/**/*.as') do |src|
  p src
  dst = src.sub(/\/original\//, '/converted/').sub!(/\.as$/, '.hx')
  as3code = File.open(src, "r") do |file| file.read end
  haxecode = as3_to_haxe(as3code)
  dstdir = dst.match(/^(.+)\/.*/)[1]
  FileUtils.mkdir_p(dstdir) if !File.exist?(dstdir)
  File.open(dst, "w") do |file| 
    file.write haxecode
  end
end
