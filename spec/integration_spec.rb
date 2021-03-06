require 'spec/spec_helper'

describe 'CLI' do
  before do
    `rm -rf #{folder}`
  end

  after do
    `rm -rf #{folder}`
  end

  def folder
    "/tmp/parallel_tests_tests"
  end

  def write(file, content, subfolder=nil)
    subfolder = "#{subfolder}/" if subfolder
    path = "#{folder}/spec/#{subfolder}#{file}"
    `mkdir -p #{File.dirname(path)}` unless File.exist?(File.dirname(path))
    File.open(path, 'w'){|f| f.write content }
    path
  end

  def bin_folder
    "#{File.expand_path(File.dirname(__FILE__))}/../bin"
  end

  def executable
    "#{bin_folder}/parallel_test"
  end

  def run_specs(options={})
    `cd #{folder} && #{executable} --chunk-timeout 999 -t spec -n #{options[:processes]||2} #{options[:add]} 2>&1`
  end

  it "runs tests in parallel" do
    write 'xxx_spec.rb', 'describe("it"){it("should"){puts "TEST1"}}'
    write 'xxx2_spec.rb', 'describe("it"){it("should"){puts "TEST2"}}'
    result = run_specs

    # test ran and gave their puts
    result.should include('TEST1')
    result.should include('TEST2')

    # all results present
    result.scan('1 example, 0 failure').size.should == 4 # 2 results + 2 result summary
    result.scan(/Finished in \d+\.\d+ seconds/).size.should == 2
    result.scan(/Took \d+\.\d+ seconds/).size.should == 1 # parallel summary
    $?.success?.should == true
  end

  it "fails when tests fail" do
    write 'xxx_spec.rb', 'describe("it"){it("should"){puts "TEST1"}}'
    write 'xxx2_spec.rb', 'describe("it"){it("should"){1.should == 2}}'
    result = run_specs

    result.scan('1 example, 1 failure').size.should == 2
    result.scan('1 example, 0 failure').size.should == 2
    $?.success?.should == false
  end

  it "can exec given commands with ENV['TEST_ENV_NUM']" do
    result = `#{executable} -e 'ruby -e "puts ENV[:TEST_ENV_NUMBER.to_s].inspect"' -n 4`
    result.split("\n").sort.should == %w["" "2" "3" "4"]
  end

  it "can exec given command non-parallel" do
    result = `#{executable} -e 'ruby -e "sleep(rand(10)/100.0); puts ENV[:TEST_ENV_NUMBER.to_s].inspect"' -n 4 --non-parallel`
    result.split("\n").should == %w["" "2" "3" "4"]
  end

  it "exists with success if all sub-processes returned success" do
    system("#{executable} -e 'cat /dev/null' -n 4").should == true
  end

  it "exists with failure if any sub-processes returned failure" do
    system("#{executable} -e 'test -e xxxx' -n 4").should == false
  end

  it "can run through parallel_spec / parallel_cucumber" do
    version = `#{executable} -v`
    `#{bin_folder}/parallel_spec -v`.should == version
    `#{bin_folder}/parallel_cucumber -v`.should == version
  end

  it "runs faster with more processes" do
    write 'xxx_spec.rb', 'describe("it"){it("should"){sleep 2}}'
    write 'xxx2_spec.rb', 'describe("it"){it("should"){sleep 2}}'
    write 'xxx3_spec.rb', 'describe("it"){it("should"){sleep 2}}'
    write 'xxx4_spec.rb', 'describe("it"){it("should"){sleep 2}}'
    write 'xxx5_spec.rb', 'describe("it"){it("should"){sleep 2}}'
    write 'xxx6_spec.rb', 'describe("it"){it("should"){sleep 2}}'
    t = Time.now
    run_specs :processes => 6
    expected = 10
    (Time.now - t).should <= expected
  end

  it "can can with given files" do
    write "x1_spec.rb", "puts '111'"
    write "x2_spec.rb", "puts '222'"
    write "x3_spec.rb", "puts '333'"
    result = run_specs(:add => 'spec/x1_spec.rb spec/x3_spec.rb')
    result.should include('111')
    result.should include('333')
    result.should_not include('222')
  end

  it "can run with test-options" do
    write "x1_spec.rb", ""
    write "x2_spec.rb", ""
    result = run_specs(:add => "--test-options ' --version'", :processes => 2)
    result.should =~ /\d+\.\d+\.\d+.*\d+\.\d+\.\d+/m # prints version twice
  end
  
  it "should override path_prefix by environment variable" do
    write "x1_spec.rb", "puts 111"
    write "x2_spec.rb", "puts 222", "sub1"
    result = `cd #{folder} &&  PATH_PREFIX=sub1 #{executable} -t spec  -n 1 2>&1 && echo 'i ran!'`
    result.should_not include('111')
    result.should include('222')    
  end
  
  it "should run all tests without excluded folder" do
    write "x1_spec.rb", "puts 111"
    write "x2_spec.rb", "puts 222"
    write "x3_spec.rb", "puts 333", "sub1"
    write "x4_spec.rb", "puts 444", "sub1"
    write "x5_spec.rb", "puts 555", "sub1/sub2"
    write "x6_spec.rb", "puts 666", "sub1/sub2"
    write "x7_spec.rb", "puts 777", "sub3/sub2"
    write "x8_spec.rb", "puts 888", "sub3/sub2"
    
    result = `cd #{folder} && #{executable} -t spec  -n 1 2>&1 && echo 'i ran!'`    
    result.should include('111')
    result.should include('222')
    result.should include('333')
    result.should include('444')
    result.should include('555')
    result.should include('666')
    result.should include('777')
    result.should include('888')
    
    result = `cd #{folder} &&  PATH_PREFIX="!(sub1)" #{executable} -t spec  -n 1 2>&1 && echo 'i ran!'`    
    result.should include('111')
    result.should include('222')
    result.should_not include('333')
    result.should_not include('444')
    result.should include('555')
    result.should include('666')
    result.should include('777')
    result.should include('888')
    
    result = `cd #{folder} &&  PATH_PREFIX="sub1/!(sub2)" #{executable} -t spec  -n 1 2>&1 && echo 'i ran!'`
    result.should_not include('111')
    result.should_not include('222')
    result.should include('333')
    result.should include('444')    
    result.should_not include('555')
    result.should_not include('666')
    result.should_not include('777')
    result.should_not include('888')
    
    result = `cd #{folder} &&  PATH_PREFIX="!(sub1)/sub2" #{executable} -t spec  -n 1 2>&1 && echo 'i ran!'`
    result.should_not include('111')
    result.should_not include('222')
    result.should_not include('333')
    result.should_not include('444')    
    result.should_not include('555')
    result.should_not include('666')
    result.should include('777')
    result.should include('888')
  end
  
  it "should log tests output in file using environment variable LOGGER" do
    write "x1_spec.rb", "puts 111"    
    logger_path = "/tmp/test.log"    
    result = `cd #{folder} &&  LOGGER=#{logger_path} #{executable} -t spec  -n 1 spec/x1_spec.rb  2>&1 && echo 'i ran!'`    
    file_content = File.read(logger_path)    
    file_content.should include("111")
  end
  
  it "should log tests output in file using argument -l" do
    write "x1_spec.rb", "puts 111"    
    logger_path = "/tmp/test.log"    
    result = `cd #{folder} && #{executable} -t spec  -n 1 -l #{logger_path} spec/x1_spec.rb  2>&1 && echo 'i ran!'`    
    file_content = File.read(logger_path)    
    file_content.should include("111")
  end
  
  it "should override test options using environment variable TESTOPTS" do    
    write "x1_spec.rb", ''
    result = `cd #{folder} && TESTOPTS="--DUMMY_OPTION" #{executable} -t spec -n 1 spec/x1_spec.rb  2>&1 && echo 'i ran!'`  
    result.should include("invalid option: --DUMMY_OPTION")
  end
  
  it "should override test options using environment variable TESTOPTS" do    
    write "x1_spec.rb", ''
    write "x2_spec.rb", ''
    write "x3_spec.rb", ''
    write "x4_spec.rb", ''
    result = `cd #{folder} && MULTIPLY="0.75" #{executable} -t spec -n 4 spec/x1_spec.rb spec/x2_spec.rb spec/x3_spec.rb spec/x4_spec.rb  2>&1 && echo 'i ran!'`  
    result.should include("3 processes for 4 specs")
    
    result = `cd #{folder} && MULTIPLY="0.5" #{executable} -t spec -n 4 spec/x1_spec.rb spec/x2_spec.rb spec/x3_spec.rb spec/x4_spec.rb  2>&1 && echo 'i ran!'`  
    result.should include("2 processes for 4 specs")
  end
end