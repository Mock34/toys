# Copyright 2018 Daniel Azuma
#
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice,
#   this list of conditions and the following disclaimer.
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# * Neither the name of the copyright holder, nor the names of any other
#   contributors to this software, may be used to endorse or promote products
#   derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
;

module Toys
  module DSL
    ##
    # This class defines the DSL for a Toys configuration file.
    #
    # A Toys configuration defines one or more named tools. It provides syntax
    # for setting the description, defining flags and arguments, specifying
    # how to execute the tool, and requesting mixin modules and other services.
    # It also lets you define subtools, nested arbitrarily deep, using blocks.
    #
    # ## Simple example
    #
    # Create a file called `.toys.rb` in the current directory, with the
    # following contents:
    #
    #     tool "greet" do
    #       desc "Prints a simple greeting"
    #
    #       optional_arg :recipient, default: "world"
    #
    #       def run
    #         puts "Hello, #{option(:recipient)}!"
    #       end
    #     end
    #
    # Now you can execute it using:
    #
    #     toys greet
    #
    # or try:
    #
    #     toys greet rubyists
    #
    module Tool
      ## @private
      def method_added(meth)
        cur_tool = DSL::Tool.activate_tool(self)
        cur_tool.mark_runnable if cur_tool && meth == :run
      end

      ##
      # Create an acceptor that can be passed into a flag or arg. An acceptor
      # validates and/or converts a string parameter to a Ruby object. This
      # acceptor may, for the current tool, be referenced by the name you provide
      # when you create a flag or arg.
      #
      # An acceptor contains a validator, which parses and validates the string
      # syntax of an argument, and a converter, which takes the validation
      # results and returns a final value for the context data.
      #
      # The validator may be either a regular expression or a list of valid
      # inputs.
      #
      # If the validator is a regular expression, it is matched against the
      # argument string and succeeds only if the expression covers the *entire*
      # string. The elements of the MatchData (i.e. the string matched, plus any
      # captures) are then passed into the conversion function.
      #
      # If the validator is an array, the *string form* of the array elements
      # (i.e. the results of calling to_s on each element) are considered the
      # valid values for the argument. This is useful for enums, for example.
      # In this case, the input is converted to the original array element, and
      # any converter function you provide is ignored.
      #
      # If you provide no validator, then no validation takes place and all
      # argument strings are considered valid. The string itself is passed on to
      # the converter.
      #
      # The converter should be a proc that takes as its arguments the results
      # of validation. For example, if you use a regular expression validator,
      # the converter should take a series of strings arguments, the first of
      # which is the full input string, and the rest of which are captures.
      # If you provide no converter, no conversion is done and the input string
      # is considered the final value. You may also provide the converter as a
      # block.
      #
      # @param [String] name The acceptor name.
      # @param [Regexp,Array,nil] validator The validator.
      # @param [Proc,nil] converter The validator.
      #
      def acceptor(name, validator = nil, converter = nil, &block)
        cur_tool = DSL::Tool.activate_tool(self)
        return self if cur_tool.nil?
        accept =
          case validator
          when ::Regexp
            Definition::PatternAcceptor.new(name, validator, converter, &block)
          when ::Array
            Definition::EnumAcceptor.new(name, validator)
          when nil
            Definition::Acceptor.new(name, converter, &block)
          else
            raise ToolDefinitionError, "Illegal validator: #{validator.inspect}"
          end
        cur_tool.add_acceptor(accept)
        self
      end

      ##
      # Create a named mixin module.
      # This module may be included by name in this tool or any subtool.
      #
      # You should pass a block and define methods in that block.
      #
      # @param [String] name Name of the mixin
      #
      def mixin(name, &block)
        cur_tool = DSL::Tool.activate_tool(self)
        cur_tool.add_mixin(name, ::Module.new(&block)) if cur_tool
        self
      end

      ##
      # Create a named template class.
      # This template may be expanded by name in this tool or any subtool.
      #
      # You should pass a block and define the template in that block. You do
      # not need to include `Toys::Template` in the block. Otherwise, see
      # {Toys::Template} for information on defining a template. In general,
      # the block should define an initialize method, and call `to_expand` to
      # define how to expand the template.
      #
      # @param [String] name Name of the template
      #
      def template(name, &block)
        cur_tool = DSL::Tool.activate_tool(self)
        if cur_tool
          template_class = ::Class.new do
            include ::Toys::Template
          end
          template_class.class_eval(&block)
          cur_tool.add_template(name, template_class)
        end
        self
      end

      ##
      # Create a subtool. You must provide a block defining the subtool.
      #
      # If the subtool is already defined (either as a tool or a namespace), the
      # old definition is discarded and replaced with the new definition.
      #
      # @param [String] word The name of the subtool
      #
      def tool(word, &block)
        word = word.to_s
        subtool_words = @__words + [word]
        next_remaining = Loader.next_remaining_words(@__remaining_words, word)
        subtool_class = @__loader.get_tool_definition(subtool_words, @__priority).tool_class
        DSL::Tool.prepare(subtool_class, next_remaining, @__path) do
          subtool_class.class_eval(&block)
        end
        self
      end
      alias name tool

      ##
      # Create an alias in the current namespace.
      #
      # @param [String] word The name of the alias
      # @param [String] target The target of the alias
      #
      def alias_tool(word, target)
        @__loader.make_alias(@__words + [word.to_s], @__words + [target.to_s], @__priority)
        self
      end

      ##
      # Create an alias of the current tool.
      #
      # @param [String] word The name of the alias
      #
      def alias_as(word)
        if @__words.empty?
          raise ToolDefinitionError, "Cannot make an alias of the root."
        end
        @__loader.make_alias(@__words[0..-2] + [word.to_s], @__words, @__priority)
        self
      end

      ##
      # Include another config file or directory at the current location.
      #
      # @param [String] path The file or directory to include.
      #
      def load(path)
        @__loader.include_path(path, @__words, @__remaining_words, @__priority)
        self
      end

      ##
      # Expand the given template in the current location.
      #
      # The template may be specified as a class or a well-known template name.
      # You may also provide arguments to pass to the template.
      #
      # @param [Class,String,Symbol] template_class The template, either as a
      #     class or a well-known name.
      # @param [Object...] args Template arguments
      #
      def expand(template_class, *args)
        name = template_class.to_s
        if template_class.is_a?(::String)
          template_class = cur_tool.resolve_template(template_class)
        elsif template_class.is_a?(::Symbol)
          template_class = @__loader.resolve_standard_template(name)
        end
        if template_class.nil?
          raise ToolDefinitionError, "Template not found: #{name.inspect}"
        end
        template = template_class.new(*args)
        yield template if block_given?
        class_exec(template, &template_class.expander)
        self
      end

      ##
      # Set the short description for the current tool. The short description is
      # displayed with the tool in a subtool list. You may also use the
      # equivalent method `short_desc`.
      #
      # The description is a {Toys::Utils::WrappableString}, which may be word-
      # wrapped when displayed in a help screen. You may pass a
      # {Toys::Utils::WrappableString} directly to this method, or you may pass
      # any input that can be used to construct a wrappable string:
      #
      # *   If you pass a String, its whitespace will be compacted (i.e. tabs,
      #     newlines, and multiple consecutive whitespace will be turned into a
      #     single space), and it will be word-wrapped on whitespace.
      # *   If you pass an Array of Strings, each string will be considered a
      #     literal word that cannot be broken, and wrapping will be done across
      #     the strings in the array. In this case, whitespace is not compacted.
      #
      # For example, if you pass in a sentence as a simple string, it may be
      # word wrapped when displayed:
      #
      #     desc "This sentence may be wrapped."
      #
      # To specify a sentence that should never be word-wrapped, pass it as the
      # sole element of a string array:
      #
      #     desc ["This sentence will not be wrapped."]
      #
      # @param [Toys::Utils::WrappableString,String,Array<String>] str
      #
      def desc(str)
        cur_tool = DSL::Tool.activate_tool(self)
        cur_tool.desc = str if cur_tool
        self
      end
      alias short_desc desc

      ##
      # Set the long description for the current tool. The long description is
      # displayed in the usage documentation for the tool itself.
      #
      # A long description is a series of descriptions, which are generally
      # displayed in a series of lines/paragraphs. Each individual description
      # uses the form described in the {Toys::DSL::Tool#desc} documentation, and
      # may be word-wrapped when displayed. To insert a blank line, include an
      # empty string as one of the descriptions.
      #
      # Example:
      #
      #     long_desc "This is an initial paragraph that might be word wrapped.",
      #               "This next paragraph is followed by a blank line.",
      #               "",
      #               ["This line will not be wrapped."]
      #
      # @param [Toys::Utils::WrappableString,String,Array<String>...] strs
      #
      def long_desc(*strs)
        cur_tool = DSL::Tool.activate_tool(self)
        cur_tool.long_desc = strs if cur_tool
        self
      end

      ##
      # Add a flag to the current tool. Each flag must specify a key which
      # the script may use to obtain the flag value from the context.
      # You may then provide the flags themselves in OptionParser form.
      #
      # Attributes of the flag may be passed in as arguments to this method, or
      # set in a block passed to this method.
      #
      # @param [Symbol] key The key to use to retrieve the value from the
      #     execution context.
      # @param [String...] flags The flags in OptionParser format.
      # @param [Object] accept An acceptor that validates and/or converts the
      #     value. You may provide either the name of an acceptor you have
      #     defined, or one of the default acceptors provided by OptionParser.
      #     Optional. If not specified, accepts any value as a string.
      # @param [Object] default The default value. This is the value that will
      #     be set in the context if this flag is not provided on the command
      #     line. Defaults to `nil`.
      # @param [Proc,nil] handler An optional handler for setting/updating the
      #     value. If given, it should take two arguments, the new given value
      #     and the previous value, and it should return the new value that
      #     should be set. The default handler simply replaces the previous
      #     value. i.e. the default is effectively `-> (val, _prev) { val }`.
      # @param [Boolean] report_collisions Raise an exception if a flag is
      #     requested that is already in use or marked as unusable. Default is
      #     true.
      # @param [String,Array<String>,Toys::Utils::WrappableString] desc Short
      #     description for the flag. See {Toys::DSL::Tool#desc} for a
      #     description of the allowed formats. Defaults to the empty string.
      # @param [Array<String,Array<String>,Toys::Utils::WrappableString>] long_desc
      #     Long description for the flag. See {Toys::DSL::Tool#long_desc} for
      #     a description of the allowed formats. (But note that this param
      #     takes an Array of description lines, rather than a series of
      #     arguments.) Defaults to the empty array.
      # @yieldparam flag_dsl [Toys::DSL::Flag] An object that lets you
      #     configure this flag in a block.
      #
      def flag(key, *flags,
               accept: nil, default: nil, handler: nil,
               report_collisions: true,
               desc: nil, long_desc: nil,
               &block)
        cur_tool = DSL::Tool.activate_tool(self)
        return self if cur_tool.nil?
        flag_dsl = DSL::Flag.new(flags, accept, default, handler, report_collisions,
                                 desc, long_desc)
        flag_dsl.instance_exec(flag_dsl, &block) if block
        flag_dsl._add_to(cur_tool, key)
        self
      end

      ##
      # Add a required positional argument to the current tool. You must specify
      # a key which the script may use to obtain the argument value from the
      # context.
      #
      # @param [Symbol] key The key to use to retrieve the value from the
      #     execution context.
      # @param [Object] accept An acceptor that validates and/or converts the
      #     value. You may provide either the name of an acceptor you have
      #     defined, or one of the default acceptors provided by OptionParser.
      #     Optional. If not specified, accepts any value as a string.
      # @param [String] display_name A name to use for display (in help text and
      #     error reports). Defaults to the key in upper case.
      # @param [String,Array<String>,Toys::Utils::WrappableString] desc Short
      #     description for the flag. See {Toys::DSL::Tool#desc} for a
      #     description of the allowed formats. Defaults to the empty string.
      # @param [Array<String,Array<String>,Toys::Utils::WrappableString>] long_desc
      #     Long description for the flag. See {Toys::DSL::Tool#long_desc} for
      #     a description of the allowed formats. (But note that this param
      #     takes an Array of description lines, rather than a series of
      #     arguments.) Defaults to the empty array.
      # @yieldparam arg_dsl [Toys::DSL::Arg] An object that lets you configure
      #     this argument in a block.
      #
      def required_arg(key,
                       accept: nil, display_name: nil, desc: nil, long_desc: nil,
                       &block)
        cur_tool = DSL::Tool.activate_tool(self)
        return self if cur_tool.nil?
        arg_dsl = DSL::Arg.new(accept, nil, display_name, desc, long_desc)
        arg_dsl.instance_exec(arg_dsl, &block) if block
        arg_dsl._add_required_to(cur_tool, key)
        self
      end
      alias required required_arg

      ##
      # Add an optional positional argument to the current tool. You must specify
      # a key which the script may use to obtain the argument value from the
      # context. If an optional argument is not given on the command line, the
      # value is set to the given default.
      #
      # @param [Symbol] key The key to use to retrieve the value from the
      #     execution context.
      # @param [Object] default The default value. This is the value that will
      #     be set in the context if this argument is not provided on the command
      #     line. Defaults to `nil`.
      # @param [Object] accept An acceptor that validates and/or converts the
      #     value. You may provide either the name of an acceptor you have
      #     defined, or one of the default acceptors provided by OptionParser.
      #     Optional. If not specified, accepts any value as a string.
      # @param [String] display_name A name to use for display (in help text and
      #     error reports). Defaults to the key in upper case.
      # @param [String,Array<String>,Toys::Utils::WrappableString] desc Short
      #     description for the flag. See {Toys::DSL::Tool#desc} for a
      #     description of the allowed formats. Defaults to the empty string.
      # @param [Array<String,Array<String>,Toys::Utils::WrappableString>] long_desc
      #     Long description for the flag. See {Toys::DSL::Tool#long_desc} for
      #     a description of the allowed formats. (But note that this param
      #     takes an Array of description lines, rather than a series of
      #     arguments.) Defaults to the empty array.
      # @yieldparam arg_dsl [Toys::DSL::Arg] An object that lets you configure
      #     this argument in a block.
      #
      def optional_arg(key,
                       default: nil, accept: nil, display_name: nil,
                       desc: nil, long_desc: nil,
                       &block)
        cur_tool = DSL::Tool.activate_tool(self)
        return self if cur_tool.nil?
        arg_dsl = DSL::Arg.new(accept, default, display_name, desc, long_desc)
        arg_dsl.instance_exec(arg_dsl, &block) if block
        arg_dsl._add_optional_to(cur_tool, key)
        self
      end
      alias optional optional_arg

      ##
      # Specify what should be done with unmatched positional arguments. You must
      # specify a key which the script may use to obtain the remaining args from
      # the context.
      #
      # @param [Symbol] key The key to use to retrieve the value from the
      #     execution context.
      # @param [Object] default The default value. This is the value that will
      #     be set in the context if no unmatched arguments are provided on the
      #     command line. Defaults to the empty array `[]`.
      # @param [Object] accept An acceptor that validates and/or converts the
      #     value. You may provide either the name of an acceptor you have
      #     defined, or one of the default acceptors provided by OptionParser.
      #     Optional. If not specified, accepts any value as a string.
      # @param [String] display_name A name to use for display (in help text and
      #     error reports). Defaults to the key in upper case.
      # @param [String,Array<String>,Toys::Utils::WrappableString] desc Short
      #     description for the flag. See {Toys::DSL::Tool#desc} for a
      #     description of the allowed formats. Defaults to the empty string.
      # @param [Array<String,Array<String>,Toys::Utils::WrappableString>] long_desc
      #     Long description for the flag. See {Toys::DSL::Tool#long_desc} for
      #     a description of the allowed formats. (But note that this param
      #     takes an Array of description lines, rather than a series of
      #     arguments.) Defaults to the empty array.
      # @yieldparam arg_dsl [Toys::DSL::Arg] An object that lets you configure
      #     this argument in a block.
      #
      def remaining_args(key,
                         default: [], accept: nil, display_name: nil,
                         desc: nil, long_desc: nil,
                         &block)
        cur_tool = DSL::Tool.activate_tool(self)
        return self if cur_tool.nil?
        arg_dsl = DSL::Arg.new(accept, default, display_name, desc, long_desc)
        arg_dsl.instance_exec(arg_dsl, &block) if block
        arg_dsl._set_remaining_on(cur_tool, key)
        self
      end
      alias remaining remaining_args

      ##
      # Disable argument parsing for this tool. Arguments will not be parsed
      # and the options will not be populated. Instead, tools can retrieve the
      # full unparsed argument list by calling {Toys::Tool#args}.
      #
      # This directive is mutually exclusive with any of the directives that
      # declare arguments or flags.
      #
      def disable_argument_parsing
        cur_tool = DSL::Tool.activate_tool(self)
        cur_tool.disable_argument_parsing unless cur_tool.nil?
        self
      end

      ##
      # Specify how to run this tool. You may do this by providing a block to
      # this directive, or by defining the `run` method in the tool.
      #
      def run(&block)
        define_method(:run, &block)
        self
      end

      ##
      # Specify that the given module should be mixed into this tool, and its
      # methods made available when running the tool.
      #
      # You may provide either a module, the string name of a mixin that you
      # have defined in this tool or one of its ancestors, or the symbol name
      # of a well-known mixin.
      #
      # @param [Module,Symbol,String] mod Module or module name.
      #
      def include(mod)
        cur_tool = DSL::Tool.activate_tool(self)
        return if cur_tool.nil?
        name = mod.to_s
        if mod.is_a?(::String)
          mod = cur_tool.resolve_mixin(mod)
        elsif mod.is_a?(::Symbol)
          mod = @__loader.resolve_standard_mixin(name)
        end
        if mod.nil?
          raise ToolDefinitionError, "Module not found: #{name.inspect}"
        end
        super(mod)
      end

      ## @private
      def self.new_class(words, priority, loader)
        tool_class = ::Class.new(::Toys::Tool)
        tool_class.extend(DSL::Tool)
        tool_class.instance_variable_set(:@__words, words)
        tool_class.instance_variable_set(:@__priority, priority)
        tool_class.instance_variable_set(:@__loader, loader)
        tool_class.instance_variable_set(:@__remaining_words, nil)
        tool_class.instance_variable_set(:@__path, nil)
        tool_class
      end

      ## @private
      def self.activate_tool(tool_class)
        path = tool_class.instance_variable_get(:@__path)
        cur_tool =
          if tool_class.instance_variable_defined?(:@__cur_tool)
            tool_class.instance_variable_get(:@__cur_tool)
          else
            loader = tool_class.instance_variable_get(:@__loader)
            words = tool_class.instance_variable_get(:@__words)
            priority = tool_class.instance_variable_get(:@__priority)
            cur_tool = loader.activate_tool_definition(words, priority)
            if cur_tool.is_a?(Definition::Alias)
              raise ToolDefinitionError,
                    "Cannot configure #{words.join(' ').inspect} because it is an alias"
            end
            tool_class.instance_variable_set(:@__cur_tool, cur_tool)
            cur_tool
          end
        cur_tool.lock_source_path(path) if cur_tool
        cur_tool
      end

      ## @private
      def self.prepare(tool_class, remaining_words, path)
        tool_class.instance_variable_set(:@__remaining_words, remaining_words)
        tool_class.instance_variable_set(:@__path, path)
        yield
      ensure
        tool_class.instance_variable_set(:@__remaining_words, nil)
        tool_class.instance_variable_set(:@__path, nil)
      end
    end
  end
end
