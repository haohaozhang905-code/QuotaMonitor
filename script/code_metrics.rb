#!/usr/bin/env ruby

root = File.expand_path("..", __dir__)
source_files = Dir[File.join(root, "Sources/QuotaMonitor/**/*.swift")].sort
test_files = Dir[File.join(root, "Tests/QuotaMonitorTests/**/*.swift")].sort

def count_lines(paths)
  paths.sum { |path| File.readlines(path).length }
end

def normalize(line)
  line.strip.gsub(/\s+/, " ")
end

def repeated_windows(paths, root)
  windows = Hash.new { |hash, key| hash[key] = [] }
  paths.each do |path|
    lines = File.readlines(path).map { |line| normalize(line) }
    next if lines.length < 8

    (0..lines.length - 8).each do |index|
      window = lines[index, 8]
      next if window.count { |line| !line.empty? && !line.start_with?("//") } < 7

      windows[window.join("\n")] << [path.delete_prefix("#{root}/"), index + 1]
    end
  end

  windows.select { |_snippet, locations| locations.map(&:first).uniq.length > 1 }
    .sort_by { |_snippet, locations| [-locations.map(&:first).uniq.length, -locations.length] }
end

production_repeated = repeated_windows(source_files, root)
test_repeated = repeated_windows(test_files, root)

puts "Production Swift LOC: #{count_lines(source_files)}"
puts "Test Swift LOC: #{count_lines(test_files)}"
puts "Repeated 8-line windows in production: #{production_repeated.length}"
puts "Repeated 8-line windows in tests: #{test_repeated.length}"
puts "Top repeated blocks (overlapping windows may represent one larger block):"
production_repeated.first(20).each_with_index do |(snippet, locations), index|
  files = locations.map(&:first).uniq
  puts "\n#{index + 1}. #{files.length} files: #{locations.map { |file, line| "#{file}:#{line}" }.join(', ')}"
  puts snippet.lines.first(8).map { |line| "   #{line}" }
end
