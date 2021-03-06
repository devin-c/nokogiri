gem 'rake-compiler'
require 'rake/extensioncompiler'
HOST = Rake::ExtensionCompiler.mingw_host

require 'mini_portile'
dependencies = YAML.load_file("dependencies.yml")
$recipes = {}
%w[zlib libiconv libxml2 libxslt].each do |lib|
  $recipes[lib] = MiniPortile.new lib, dependencies[lib]
end
$recipes.each { |_, recipe| recipe.host = HOST }

file "lib/nokogiri/nokogiri.rb" do
  File.open("lib/nokogiri/nokogiri.rb", 'wb') do |f|
    f.write %Q{require "nokogiri/\#{RUBY_VERSION.sub(/\\.\\d+$/, '')}/nokogiri"\n}
  end
end

namespace :cross do
  task :zlib do
    recipe = $recipes["zlib"]
    recipe.files = ["http://zlib.net/#{recipe.name}-#{recipe.version}.tar.gz"]
    class << recipe
      def configure
        Dir.chdir work_path do
          mk = File.read 'win32/Makefile.gcc'
          File.open 'win32/Makefile.gcc', 'wb' do |f|
            f.puts "BINARY_PATH = #{CROSS_DIR}/bin"
            f.puts "LIBRARY_PATH = #{CROSS_DIR}/lib"
            f.puts "INCLUDE_PATH = #{CROSS_DIR}/include"
            f.puts mk.sub(/^PREFIX\s*=\s*$/, "PREFIX = #{HOST}-")
          end
        end
      end

      def configured?
        Dir.chdir work_path do
          !! (File.read('win32/Makefile.gcc') =~ /^BINARY_PATH/)
        end
      end

      def compile
        execute "compile", "make -f win32/Makefile.gcc"
      end

      def install
        execute "install", "make -f win32/Makefile.gcc install"
      end
    end

    checkpoint = "#{CROSS_DIR}/#{recipe.name}-#{recipe.version}-#{recipe.host}.installed"
    unless File.exist?(checkpoint)
      recipe.cook
      touch checkpoint
    end
    recipe.activate
  end

  task :libiconv do
    recipe = $recipes["libiconv"]
    recipe.files = ["http://ftp.gnu.org/pub/gnu/libiconv/#{recipe.name}-#{recipe.version}.tar.gz"]
    recipe.configure_options = [
      "--host=#{HOST}",
      "--enable-static",
      "--disable-shared",
      "CPPFLAGS='-Wall'",
      "CFLAGS='-O2 -g'",
      "CXXFLAGS='-O2 -g'"
    ]

    checkpoint = "#{CROSS_DIR}/#{recipe.name}-#{recipe.version}-#{recipe.host}.installed"
    unless File.exist?(checkpoint)
      recipe.cook
      touch checkpoint
    end
    recipe.activate
  end

  task :libxml2 => ["cross:zlib", "cross:libiconv"] do
    recipe = $recipes["libxml2"]
    recipe.files = ["ftp://ftp.xmlsoft.org/libxml2/#{recipe.name}-#{recipe.version}.tar.gz"]
    recipe.configure_options = [
      "--host=#{HOST}",
      "--enable-static",
      "--disable-shared",
      "--with-zlib=#{CROSS_DIR}",
      "--with-iconv=#{$recipes["libiconv"].path}",
      "--without-python",
      "--without-readline",
      "CFLAGS='-DIN_LIBXML'"
    ]

    checkpoint = "#{CROSS_DIR}/#{recipe.name}-#{recipe.version}-#{recipe.host}.installed"
    unless File.exist?(checkpoint)
      recipe.cook
      touch checkpoint
    end
    recipe.activate
  end

  task :libxslt => ['cross:libxml2'] do
    recipe = $recipes["libxslt"]
    recipe.files = ["ftp://ftp.xmlsoft.org/libxml2/#{recipe.name}-#{recipe.version}.tar.gz"]
    recipe.configure_options = [
      "--host=#{HOST}",
      "--enable-static",
      "--disable-shared",
      "--with-libxml-prefix=#{$recipes["libxml2"].path}",
      "--without-python",
      "--without-crypto",
      "CFLAGS='-DIN_LIBXML'"
    ]

    checkpoint = "#{CROSS_DIR}/#{recipe.name}-#{recipe.version}-#{recipe.host}.installed"
    unless File.exist?(checkpoint)
      recipe.cook
      touch checkpoint
    end
    recipe.activate
  end

  task :file_list do
    add_file_to_gem "lib/nokogiri/nokogiri.rb"
  end

end

require 'rake/clean'
CLOBBER.include("#{CROSS_DIR}/*.installed", "#{CROSS_DIR}/#{HOST}", "tmp/#{HOST}")

task :cross2 => ["cross:libxslt", "lib/nokogiri/nokogiri.rb", "cross", "cross:file_list"]
