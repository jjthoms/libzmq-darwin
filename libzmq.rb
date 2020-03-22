#!/usr/bin/env ruby

#
# A script to download and build libzmq for iOS, including arm64
# Adapted from https://github.com/drewcrawford/libzmq-ios/blob/master/libzmq.sh
#

require 'fileutils'

# ZeroMQ release version
PKG_VER="4.1.7"

# Minimum platform versions
IOS_VERSION_MIN         = "12.0"
MACOS_VERSION_MIN       = "10.14"
#TVOS_VERSION_MIN        = "11.0"


LIBNAME="libzmq.a"
ROOTDIR=File.absolute_path(File.dirname(__FILE__))
LIBSODIUM_DIST=File.join(ROOTDIR, "../libsodium-darwin/dist")

VALID_ARHS_PER_PLATFORM = {
  "iOS"     => ["arm64", "x86_64"],
  "macOS"   => ["x86_64"],
#  "tvOS"    => ["arm64", "x86_64"],
}

DEVELOPER               = `xcode-select -print-path`.chomp
LIPO                    = `xcrun -sdk iphoneos -find lipo`.chomp

# Script's directory
SCRIPTDIR               = File.absolute_path(File.dirname(__FILE__))

# root directory
LIBDIR                  = File.join(SCRIPTDIR, "build/zeromq")

# Destination directory for build and install
BUILDDIR="#{SCRIPTDIR}/build"
DISTDIR="#{SCRIPTDIR}/dist"
DISTLIBDIR="#{SCRIPTDIR}/lib"

def find_sdks
  sdks=`xcodebuild -showsdks`.chomp
  sdk_versions = {}
  for line in sdks.lines do
    if line =~ /-sdk iphoneos(\S+)/
      sdk_versions["iOS"]     = $1
    elsif line =~ /-sdk macosx(\S+)/
      sdk_versions["macOS"]   = $1
#    elsif line =~ /-sdk appletvos(\S+)/
#      sdk_versions["tvOS"]    = $1
    end
  end
  return sdk_versions
end

sdk_versions            = find_sdks()
IOS_SDK_VERSION         = sdk_versions["iOS"]
MACOS_SDK_VERSION       = sdk_versions["macOS"]
#TVOS_SDK_VERSION        = sdk_versions["tvOS"]

puts "iOS     SDK version = #{IOS_SDK_VERSION}"
puts "macOS   SDK version = #{MACOS_SDK_VERSION}"
#puts "tvOS    SDK version = #{TVOS_SDK_VERSION}"

# Cleanup
if File.directory? BUILDDIR
    FileUtils.rm_rf BUILDDIR
end
if File.directory? DISTDIR
    FileUtils.rm_rf DISTDIR
end
FileUtils.mkdir_p BUILDDIR
FileUtils.mkdir_p DISTDIR

# Download and extract the latest stable release indicated by PKG_VER variable
def download_and_extract_libzeromq()
  puts "Downloading latest stable release of 'zeromq'"
  pkg_name      = "zeromq-#{PKG_VER}"
  pkg           = "#{pkg_name}.tar.gz"
  url           = "https://github.com/zeromq/zeromq4-1/releases/download/v#{PKG_VER}/#{pkg}"
  exit 1 unless system("cd #{BUILDDIR} && curl -O -L #{url}")
  exit 1 unless system("cd #{BUILDDIR} && tar xzf #{pkg}")
  FileUtils.mv "#{BUILDDIR}/#{pkg_name}", "build/zeromq"
  FileUtils.rm "#{BUILDDIR}/#{pkg}"
end

# Download and extract ZeroMQ
download_and_extract_libzeromq()

PLATFORMS = sdk_versions.keys
libs_per_platform = {}

# Compile zeromq for each Apple device platform
for platform in PLATFORMS
  # Compile zeromq for each valid Apple device architecture
  archs = VALID_ARHS_PER_PLATFORM[platform]
  for arch in archs
    build_type = "#{platform}-#{arch}"

    puts "Building #{build_type}..."
    build_arch_dir=File.absolute_path("#{BUILDDIR}/#{platform}-#{arch}")
    FileUtils.mkdir_p(build_arch_dir)

    LIBSODIUM_INC = "#{LIBSODIUM_DIST}/#{platform.downcase}/include"
    LIBSODIUM_LIB = "#{LIBSODIUM_DIST}/#{platform.downcase}/lib"

    other_cppflags = "-Os -I#{LIBSODIUM_INC} -fembed-bitcode"
    OTHER_CXXFLAGS = "-Os"
    other_ldflags = "-L#{LIBSODIUM_LIB} -lsodium"
    sodium_cflags = "-arch #{arch} #{other_cppflags}"
    sodium_libs = "-arch ${arch} -L#{LIBSODIUM_LIB}"

    case build_type
    when "iOS-arm64"
      # iOS 64-bit ARM (iPhone 5s and later)
      platform_name   = "iPhoneOS"
      host            = "arm-apple-darwin"
      base_dir        = "#{DEVELOPER}/Platforms/#{platform_name}.platform/Developer"
      ENV["BASEDIR"]  = base_dir
      isdk_root       = "#{base_dir}/SDKs/#{platform_name}#{IOS_SDK_VERSION}.sdk"
      ENV["ISDKROOT"] = isdk_root
      ENV["CXXFLAGS"] = OTHER_CXXFLAGS
      ENV["CPPFLAGS"]   = "-arch #{arch} -isysroot #{isdk_root}  -mios-version-min=#{IOS_VERSION_MIN} #{other_cppflags}"
      ENV["LDFLAGS"]  = "-mthumb -arch #{arch} -isysroot #{isdk_root} #{other_ldflags}"
      ENV["sodium_CFLAGS"] = sodium_cflags
      ENV["sodium_LIBS"] = sodium_libs
    when "tvOS-arm64"
      # tvOS 64-bit ARM (Apple TV 4)
      platform_name   = "AppleTVOS"
      host            = "arm-apple-darwin"
      base_dir        = "#{DEVELOPER}/Platforms/#{platform_name}.platform/Developer"
      ENV["BASEDIR"]  = base_dir
      isdk_root       = "#{base_dir}/SDKs/#{platform_name}#{TVOS_SDK_VERSION}.sdk"
      ENV["ISDKROOT"] = isdk_root
      ENV["CXXFLAGS"] = OTHER_CXXFLAGS
      ENV["CPPFLAGS"]   = "-arch #{arch} -isysroot #{isdk_root} -mtvos-version-min=#{TVOS_VERSION_MIN} #{other_cppflags}"
      ENV["LDFLAGS"]  = "-mthumb -arch #{arch} -isysroot #{isdk_root} #{other_ldflags}"
      ENV["sodium_CFLAGS"] = sodium_cflags
      ENV["sodium_LIBS"] = sodium_libs
    when "iOS-x86_64"
      # iOS 64-bit simulator (iOS 7+)
      platform_name   = "iPhoneSimulator"
      host            = "#{arch}-apple-darwin"
      base_dir        = "#{DEVELOPER}/Platforms/#{platform_name}.platform/Developer"
      ENV["BASEDIR"]  = base_dir
      isdk_root       = "#{base_dir}/SDKs/#{platform_name}#{IOS_SDK_VERSION}.sdk"
      ENV["ISDKROOT"] = isdk_root
      ENV["CXXFLAGS"] = OTHER_CXXFLAGS
      ENV["CPPFLAGS"]   = "-arch #{arch} -isysroot #{isdk_root} -mios-version-min=#{IOS_VERSION_MIN} #{other_cppflags}"
      ENV["LDFLAGS"]  = "-arch #{arch} #{other_ldflags}"
      ENV["sodium_CFLAGS"] = sodium_cflags
      ENV["sodium_LIBS"] = sodium_libs
    when "macOS-x86_64"
      # macOS 64-bit
      platform_name   = "MacOSX"
      host            = "#{arch}-apple-darwin"
      base_dir        = "#{DEVELOPER}/Platforms/#{platform_name}.platform/Developer"
      ENV["BASEDIR"]  = base_dir
      isdk_root       = "#{base_dir}/SDKs/#{platform_name}#{MACOS_SDK_VERSION}.sdk"
      ENV["ISDKROOT"] = isdk_root
      ENV["CXXFLAGS"] = OTHER_CXXFLAGS
      ENV["CPPFLAGS"]   = "-arch #{arch} -isysroot #{isdk_root} -mmacosx-version-min=#{MACOS_VERSION_MIN} #{other_cppflags}"
      ENV["LDFLAGS"]  = "-arch #{arch} #{other_ldflags}"
      ENV["sodium_CFLAGS"] = sodium_cflags
      ENV["sodium_LIBS"] = sodium_libs
    when "tvOS-x86_64"
      # tvOS 64-bit simulator
      platform_name   = "AppleTVSimulator"
      host            = "#{arch}-apple-darwin"
      base_dir        = "#{DEVELOPER}/Platforms/#{platform_name}.platform/Developer"
      ENV["BASEDIR"]  = base_dir
      isdk_root       = "#{base_dir}/SDKs/#{platform_name}#{TVOS_SDK_VERSION}.sdk"
      ENV["ISDKROOT"] = isdk_root
      ENV["CXXFLAGS"] = OTHER_CXXFLAGS
      ENV["CPPFLAGS"]   = "-arch #{arch} -isysroot #{isdk_root} -mtvos-version-min=#{TVOS_VERSION_MIN} #{other_cppflags}"
      ENV["LDFLAGS"]  = "-arch #{arch} #{other_ldflags}"
      ENV["sodium_CFLAGS"] = sodium_cflags
      ENV["sodium_LIBS"] = sodium_libs
    else
      warn "Unsupported platform/architecture #{build_type}"
      exit 1
    end

    # Modify path to include Xcode toolchain path
    ENV["PATH"] = "#{DEVELOPER}/Toolchains/XcodeDefault.xctoolchain/usr/bin:" +
      "#{DEVELOPER}/Toolchains/XcodeDefault.xctoolchain/usr/sbin:#{ENV["PATH"]}"

    puts "Configuring for #{build_type}..."
    FileUtils.cd(LIBDIR)
    configure_cmd = [
      "./configure",
      "--prefix=#{build_arch_dir}",
      "--disable-shared",
      "--enable-static",
      "--host=#{host}",
      "--with-libsodium=yes"
    ]
    exit 1 unless system(configure_cmd.join(" "))

    puts "Building for #{build_type}..."
    exit 1 unless system("make clean")
    exit 1 unless system("make -j V=0")
    exit 1 unless system("make install")

    # Add to the architecture-dependent library list for the current platform
    libs = libs_per_platform[platform]
    if libs == nil
      libs_per_platform[platform] = libs = []
    end
    libs.push "#{build_arch_dir}/lib/#{LIBNAME}"
  end
end

# Build a single universal (fat) library file for each platform
# And copy headers
for platform in PLATFORMS
  dist_platform_folder = "#{DISTDIR}/#{platform.downcase}"
  dist_platform_lib    = "#{dist_platform_folder}/lib"
  FileUtils.mkdir_p dist_platform_lib

  # Find libraries for platform
  libs                 = libs_per_platform[platform]

  # Make sure library list is not empty
  if libs == nil || libs.length == 0
    warn "Nothing to do for #{LIBNAME}"
    next
  end

  # Build universal library file (aka fat binary)
  lipo_cmd = "#{LIPO} -create #{libs.join(" ")} -output #{dist_platform_lib}/#{LIBNAME}"
  puts "Combining #{libs.length} libraries into #{LIBNAME} for #{platform}..."
  exit 1 unless system(lipo_cmd)

  # Copy headers for architecture
  for arch in VALID_ARHS_PER_PLATFORM["#{platform}"]
      include_dir = "#{BUILDDIR}/#{platform}-#{arch}/include"
      if File.directory? include_dir
        FileUtils.cp_r(include_dir, dist_platform_folder)
      end
  end

end

# Cleanup
FileUtils.rm_rf BUILDDIR
