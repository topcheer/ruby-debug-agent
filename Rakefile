require 'bundler/gem_tasks'

# In CI (trusted publishing), skip git checks and git push from rake release.
# The gem push is done via RUBYGEMS_API_KEY env var set by rubygems/release-gem.
if ENV['RUBYGEMS_API_KEY']
  Rake::Task['release:guard_clean'].clear_actions
  Rake::Task['release:source_control_push'].clear_actions

  task 'release:guard_clean' do
    puts 'Skipping guard_clean in CI'
  end

  task 'release:source_control_push' do
    puts 'Skipping source_control_push in CI'
  end
end
