# frozen_string_literal: true

# Shared consts
CHANGED_FILES = (git.added_files + git.modified_files).freeze
ADDED_FILES = git.added_files.freeze

Dir[File.join(__dir__, ".danger/*.rb")].each do |danger_rule_file|
  danger_rule = danger_rule_file.gsub(%r{(^./.danger/|.rb)}, "")
  $stdout.print "- #{danger_rule} "
  eval File.read(danger_rule_file), binding, File.expand_path(danger_rule_file) # rubocop:disable Security/Eval
  $stdout.puts "✅"
rescue Exception => e # rubocop:disable Lint/RescueException
  $stdout.puts "💥"

  fail "Danger rule :#{danger_rule} failed with exception: #{e.message}\n" \
       "Backtrace: \n#{e.backtrace.join("\n")}"
end
