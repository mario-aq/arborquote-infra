require 'simplecov'
require 'simplecov-console'

SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new([
  SimpleCov::Formatter::HTMLFormatter,
  SimpleCov::Formatter::Console
])

SimpleCov.start do
  add_filter '/spec/'
  add_filter '/vendor/'
  
  add_group 'Handlers', 'lambda/**/handler.rb'
  add_group 'Shared', 'lambda/shared'
  
  minimum_coverage 60
end

require 'json'
require 'rspec'

# Add lambda directory to load path
$LOAD_PATH.unshift File.expand_path('../', __dir__)

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!
  config.warnings = false
  
  if config.files_to_run.one?
    config.default_formatter = 'doc'
  end

  config.order = :random
  Kernel.srand config.seed
end

# Mock AWS environment variables for tests
ENV['QUOTES_TABLE_NAME'] = 'test-quotes-table'
ENV['USERS_TABLE_NAME'] = 'test-users-table'
ENV['STAGE'] = 'test'
ENV['AWS_REGION'] = 'us-east-1'

