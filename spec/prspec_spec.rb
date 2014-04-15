require_relative '..\lib\prspec.rb'
require 'rspec'
require 'parallel'
require 'timeout'

RSpec.configure do |config|
  config.around(:each) do |example|
    Timeout::timeout(30) {
      example.run
    }
  end

  config.before(:suite) do
    $p = PRSpec.new(['--test-mode']) # test mode
  end

  config.after(:each) do

  end

  config.after(:suite) do
    `taskkill /F /FI "WindowTitle eq  Administrator:  prspec-test*" /T`
    `taskkill /F /FI "WindowTitle eq  prspec-test*" /T`

    path = "*.{out,err}"
    delete_files = Dir.glob(path)
    delete_files.each do |file|
      File.unlink file
    end
  end
end

describe 'PRSpec Tests' do
  it 'Get help message' do
    expected = 'Usage: prspec [options]
    -p, --path PATH                  Relative path from the base directory to search for spec files
    -e, --exclude REGEX              Regex string used to exclude files
    -d, --dir DIRECTORY              The base directory to run from
    -n, --num-threads THREADS        The number of threads to use
    -t, --tag TAG                    A rspec tag value to filter by
    -r, --rspec-args "RSPEC_ARGS"    Additional arguments to be passed to rspec (must be surrounded with double quotes)
        --test-mode                  Do everything except actually starting the test threads
    -q, --quiet                      Quiet mode. Do not display parallel thread output
    -h, --help                       Display a help message
        --ignore-pending             Ignore all pending tests
'
    path = File.join('.', 'lib','prspec.rb')
    actual = `ruby -r "#{path}" -e "PRSpec.new(['-h'])"`
    expect(actual).to end_with(expected), "Help message did not end with expected string... expected: '#{expected}'; recieved: '#{actual}'"    
  end

  it 'Verify invalid parameter results in program exit and help message displayed' do
    expected = 'Usage: prspec [options]
    -p, --path PATH                  Relative path from the base directory to search for spec files
    -e, --exclude REGEX              Regex string used to exclude files
    -d, --dir DIRECTORY              The base directory to run from
    -n, --num-threads THREADS        The number of threads to use
    -t, --tag TAG                    A rspec tag value to filter by
    -r, --rspec-args "RSPEC_ARGS"    Additional arguments to be passed to rspec (must be surrounded with double quotes)
        --test-mode                  Do everything except actually starting the test threads
    -q, --quiet                      Quiet mode. Do not display parallel thread output
    -h, --help                       Display a help message
        --ignore-pending             Ignore all pending tests
'
    path = File.join('.', 'lib','prspec.rb')
    actual = `ruby -r "#{path}" -e "PRSpec.new(['-z','foo'])"`
    expect(actual).to end_with(expected), "Help message did not end with expected string... expected: '#{expected}'; recieved: '#{actual}'"    
  end

  it 'Verify default number of available Processes' do
    expected = Parallel.processor_count
    actual = $p.get_number_of_threads
    expect(actual).to eq(expected), "Expected the default number of threads, #{actual}, to match the number of processors available on the machine: #{expected}"
  end

  it 'Verify number of running threads when tests running' do
    p = PRSpec.new(['-p','test/inside_check.rb','-q']) # this will run test/sample.rb
    actual = ''
    p.processes.each do |proc|
      actual << proc.output
    end
    expect(actual).not_to eq(''), "Expected that a test would run and have some output, but did not"
    expect(actual).to include("1 example, 0 failures"), "Expected that the test found a running process and passed, but did not: #{actual}"
  end

  it 'Verify process completes when subprocess is spawned and detached' do
    p = PRSpec.new(['-p','test/sub_process.rb','-q']) # this will run test/sub_process.rb
    sleep(15) # allow time for the tests to complete
    expect(p.running?).to eq(false), "Expected to pass if process detaches correctly, but did not"
    lines = `wmic process get commandline`
    count = 0
    lines.split("\n").each do |line|
      if (line.include?("prspec-test"))
        count += 1
      end
    end
    sub_process_found = (count >= 1)
    expect(sub_process_found).to eq(true), "Expected that the subprocess is still running, but was not.  Found #{count}"
  end

  it 'Verify begin_run handles nil input' do
    expect { $p.begin_run(nil, {:test_mode => true}) }.to raise_error("Invalid input passed to method: 'processes' must be a valid Array of PRSpecThread objects")
  end

  it 'Verify begin_run handles wrong datatype input' do
    expect { $p.begin_run(['foo'], {:test_mode=>true}) }.to raise_error
    expect { $p.begin_run([PRSpecThread.new(nil,nil,nil,nil)], 'foo') }.to raise_error
  end

  it 'Verify handling of -p with filename specified' do
    expect { PRSpec.new(['-p','prspec.rb','-d','./lib']) }.to raise_error, "Expected to be able to specify a filename containing no tests in the path and for the program to halt, but did not"
    p = PRSpec.new(['-p','test/sample.rb', '--test-mode'])
    expect(p.tests.length).to eq(2), "Expected to be able to specify a filename in the path and still find tests, but did not"
  end

  it 'Verify handling of -p using default filename search pattern' do
    p = PRSpec.new(['-p','test', '--test-mode'])
    expect(p.tests.length).to eq(6), "Expected searches restricted to filenames ending with _spec.rb only, but was not"
  end

  it 'Verify handling of bad spacing in spec files' do
    p = PRSpec.new(['-p','test/error_sample.rb','--test-mode'])
    expect(p.tests.length).to eq(8), "Expected bad spacing to be handled correctly, but was not.  Found: #{p.tests.length}"
  end

  it 'Verify creation of Processes' do
    expected = $p.get_number_of_threads
    actual = $p.processes.length
    expect(actual).to eq(expected), "Expected the number of Processes created, #{actual}, to equal the number of processors available on the machine: #{expected}"
    $p.processes.each do |proc| 
      expect(proc.nil?).to be(false), "Expected that each process was created successfully, but at least one was nil"
      expect(proc.is_a?(PRSpecThread)).to be(true), "Expected that each process was of type PRSpecThread, but at least one was: #{proc.class.to_s}"
      expect(proc.tests.length).to be > 0, "Expected that each process has at least one test, but at least one only had: #{proc.tests.length}"
    end
  end

  it 'Verify is_windows?' do
    expected = (RUBY_PLATFORM.match(/mingw/i)) ? true : false
    actual = PRSpec.is_windows?
    expect(actual).to eq(expected), "Expected platform detection to return #{expected.to_s}, but returned #{actual.to_s}"
  end

  it 'Verify -r arguments get passed to rspec calls' do
    p = PRSpec.new(['-p','test', '-r', '"--format documentation --out tagged.out"']) # expect to run only 1 test
    expect(File.exists?('tagged.out')).to eq(true), "Expected that the rspec --out argument would create a file of name 'tagged.out', but did not"
    File.delete('tagged.out')
  end

  it 'Verify -t filters by expected tags' do
    p = PRSpec.new(['-p','test', '-t', 'tagged', '-q']) # expect to run only 1 test
    actual = ''
    p.processes.each do |proc|
      actual << proc.output
    end
    expect(actual).not_to eq(''), "Expected that a test would run and have some output, but did not"
    expect(actual).to include("Run options: include {:full_description=>/Sample\\ 5\\ \\-\\ Expect\\ pass/}"), "Expected that the tagged test would be run, but it wasn't: #{actual}"
    expect(actual).not_to include("Run options: include {:full_description=>/Sample\\ 3\\ \\-\\ Expect\\ pass/}"), "Expected that the un-tagged tests would not be run, but they were: #{actual}"
  end

  it 'Verify handling of --ignore-pending' do
    p = PRSpec.new(['-p','test', '--test-mode', '--ignore-pending'])
    expect(p.tests.length).to eq(5), "Expected only non-pending tests to be returned, but was not: #{p.tests.length} found"
  end

  it 'Verify descriptions containing double and single quotes are run successfully' do
    p = PRSpec.new(['-p','test', '-q']) # expect to run all
    actual = ''
    p.processes.each do |proc|
      actual << proc.output
    end
    expect(actual).not_to eq(''), "Expected that a test would run and have some output, but did not"
    expect(actual).to include("Run options: include {:full_description=>/Sample\\ 5\\ \\-\\ Expect\\ pass/}"), "Expected that a normal test would be run, but it wasn't: #{actual}"
    expect(actual).to include("Description\\ containing\\ \"doublequotes\""), "Expected that a test with doublequotes in the description would be run, but it wasn't: #{actual}"
    expect(actual).to include("Description\\ containing\\ 'singlequotes'"), "Expected that a test with singlequotes in the description would be run, but it wasn't: #{actual}"
  end
end