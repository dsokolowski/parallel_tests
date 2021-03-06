require 'parallel'
require 'parallel_tests/grouper'
require 'parallel_tests/railtie'

class ParallelTests
  VERSION = File.read( File.join(File.dirname(__FILE__),'..','VERSION') ).strip

  # parallel:spec[2,controller] <-> parallel:spec[controller]
  def self.parse_rake_args(args)
    num_processes = Parallel.processor_count
    options = ""
    if args[:count].to_s =~ /^\d*$/ # number or empty
      num_processes = args[:count] unless args[:count].to_s.empty?
      prefix = args[:path_prefix]
      options = args[:options] if args[:options]
    else # something stringy
      prefix = args[:count]
    end
    [num_processes.to_i, prefix.to_s, options]
  end

  # finds all tests and partitions them into groups
  def self.tests_in_groups(root, num_groups, options={})
    if options[:no_sort] == true
      Grouper.in_groups(find_tests(root), num_groups)
    else
      Grouper.in_even_groups_by_size(tests_with_runtime(root,options), num_groups)
    end
  end

  def self.run_tests(test_files, process_number, options)    
    require_list = test_files.map{|f| "\"#{f}\"" }.join(' ')
    cmd = "ruby -Itest #{options[:test_options]} -e 'ARGV.each{|f| load f unless f.to_s.match(/^-/) }' #{require_list} #{options[:test_args]}"
    execute_command(cmd, process_number, options)
  end

  def self.execute_command(cmd, process_number, options)
    cmd = "TEST_ENV_NUMBER=#{test_env_number(process_number)} ; export TEST_ENV_NUMBER; #{cmd}"
    f = open("|#{cmd}", 'r')
    output = fetch_output(f, options)
    f.close
    {:stdout => output, :exit_status => $?.exitstatus}
  end

  def self.find_results(test_output)
    test_output.split("\n").map {|line|
      line = line.gsub(/\.|F|\*/,'')
      next unless line_is_result?(line)
      line
    }.compact
  end

  def self.test_env_number(process_number)
    process_number == 0 ? '' : process_number + 1
  end

  protected

  # read output of the process and print in in chucks
  def self.fetch_output(process, options)
    all = ''
    buffer = ''
    timeout = options[:chunk_timeout] || 0.2
    flushed = Time.now.to_f

    while char = process.getc
      char = (char.is_a?(Fixnum) ? char.chr : char) # 1.8 <-> 1.9
      all << char

      # print in chunks so large blocks stay together
      now = Time.now.to_f
      buffer << char
      if flushed + timeout < now
        print buffer
        STDOUT.flush
        buffer = ''
        flushed = now
      end
    end

    # print the remainder
    print buffer
    STDOUT.flush

    all
  end

  # copied from http://github.com/carlhuda/bundler Bundler::SharedHelpers#find_gemfile
  def self.bundler_enabled?
    return true if Object.const_defined?(:Bundler) 

    previous = nil
    current = File.expand_path(Dir.pwd)

    until !File.directory?(current) || current == previous
      filename = File.join(current, "Gemfile")
      return true if File.exists?(filename)
      current, previous = File.expand_path("..", current), current
    end

    false
  end

  def self.line_is_result?(line)
    line =~ /\d+ failure/
  end

  def self.test_suffix
    "_test.rb"
  end

  def self.tests_with_runtime(root,options={})
    tests = find_tests(root)
    root_path = ( options[:root_path] || "#{root}/../" )
    lines = File.read("#{root_path}/tmp/parallel_profile.log").split("\n") rescue []

    # use recorded test runtime if we got enough data
    if lines.size * 1.5 > tests.size
      puts "Using recorded test runtime"
      times = Hash.new(1)
      lines.each do |line|
        test, time = line.split(":")
        key = [options[:root_path],test].compact.join('/')
        times[key] = time.to_f
      end
      tests.sort.map{|test| [test, times[test]] }
    else # use file sizes
      tests.sort.map{|test| [test, File.stat(test).size] }
    end
  end
  
  def self.tests_with_excluded(path)    
    result = path.match(/!\((.*)\)/)
    if result
      excluded_files = path.gsub(result[0],result[1])
      files = path.gsub("#{result[0]}/","*/").gsub(result[0],"")    
      return [].tap do |result|
        result[0] = Dir[files+"**/*#{self.test_suffix}"]
        result[1] = Dir[excluded_files+"**/*#{self.test_suffix}"]
      end
    else
      return [].tap do |result|
        result[0] = Dir["#{path}**/**/*#{self.test_suffix}"]        
        result[1] = []
      end
    end
  end
    
  def self.find_tests(root)
    if root.is_a?(Array)
      root
    else      
      tests,excluded_tests = tests_with_excluded(root)
      return tests - excluded_tests
    end
  end
end
