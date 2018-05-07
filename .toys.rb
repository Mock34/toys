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

name "install" do
  desc "Build and install the current gems"
  use :exec
  execute do
    set Context::EXIT_ON_NONZERO_STATUS, true
    ::Dir.chdir(::File.dirname(tool.definition_path)) do
      version = capture("./toys-dev system version").strip
      ::Dir.chdir("toys-core") do
        cli = new_cli.add_config_path(".toys.rb")
        run("build", cli: cli)
        sh "gem install pkg/toys-core-#{version}.gem"
      end
      ::Dir.chdir("toys") do
        cli = new_cli.add_config_path(".toys.rb")
        run("build", cli: cli)
        sh "gem install pkg/toys-#{version}.gem"
      end
    end
  end
end

name "ci" do
  desc "CI target that runs tests and rubocop for both gems"
  use :exec
  execute do
    set Context::EXIT_ON_NONZERO_STATUS, true
    ::Dir.chdir(::File.dirname(tool.definition_path)) do
      ::Dir.chdir("toys-core") do
        cli = new_cli.add_config_path(".toys.rb")
        run("test", cli: cli)
        run("rubocop", cli: cli)
      end
      ::Dir.chdir("toys") do
        cli = new_cli.add_config_path(".toys.rb")
        run("test", cli: cli)
        run("rubocop", cli: cli)
      end
    end
  end
end

name "yardoc" do
  desc "Generates yardoc for both gems"
  use :exec
  execute do
    set Context::EXIT_ON_NONZERO_STATUS, true
    ::Dir.chdir(::File.dirname(tool.definition_path)) do
      ::Dir.chdir("toys-core") do
        exec "yardoc"
      end
      ::Dir.chdir("toys") do
        exec "yardoc"
      end
    end
  end
end

name "clean" do
  desc "Cleans both gems"
  use :exec
  execute do
    set Context::EXIT_ON_NONZERO_STATUS, true
    ::Dir.chdir(::File.dirname(tool.definition_path)) do
      ::Dir.chdir("toys-core") do
        cli = new_cli.add_config_path(".toys.rb")
        run("clean", cli: cli)
      end
      ::Dir.chdir("toys") do
        cli = new_cli.add_config_path(".toys.rb")
        run("clean", cli: cli)
      end
    end
  end
end

name "release" do
  desc "Releases both gems"
  use :exec
  execute do
    set Context::EXIT_ON_NONZERO_STATUS, true
    ::Dir.chdir(::File.dirname(tool.definition_path)) do
      ::Dir.chdir("toys-core") do
        cli = new_cli.add_config_path(".toys.rb")
        run("release", cli: cli)
      end
      ::Dir.chdir("toys") do
        cli = new_cli.add_config_path(".toys.rb")
        run("release", cli: cli)
      end
    end
  end
end
