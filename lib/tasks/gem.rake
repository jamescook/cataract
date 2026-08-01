# frozen_string_literal: true

# Gem release tasks
namespace :gem do
  desc 'Prepare gem for release (compile, test, lint)'
  task prep: %i[compile test lint] do
    puts "\n#{'=' * 80}"
    puts '✓ Gem preparation complete!'
    puts '  - Code compiled successfully'
    puts '  - All tests passed'
    puts '  - Linting passed'
    puts '=' * 80
    puts "\nReady for release! Next steps:"
    puts '  1. Update version in lib/cataract/version.rb'
    puts '  2. Update CHANGELOG.md'
    puts '  3. Commit changes: git commit -am "Release vX.Y.Z"'
    puts '  4. Run: rake release (creates tag, builds gem, pushes to rubygems)'
    puts '=' * 80
  end

  desc 'Build and test gem locally (sanity check before release)'
  task build_test: :build do
    require_relative '../cataract/version'
    version = Cataract::VERSION
    gem_file = "pkg/cataract-#{version}.gem"

    puts "\nTesting gem installation locally..."
    sh "gem install #{gem_file} --local"

    puts "\nRunning smoke test..."
    ruby_code = <<~RUBY
      require 'cataract'
      sheet = Cataract::Stylesheet.parse('body { color: red; }')
      raise 'Smoke test failed!' unless sheet.rules_count == 1
      puts '✓ Smoke test passed'
    RUBY
    sh "ruby -e \"#{ruby_code}\""

    puts "\n✓ Local gem test successful: #{gem_file}"
    puts "\nTo release, run: rake release"
  end

  desc 'Verify the gem installs and runs with --disable-native-extension'
  task :verify_pure_only do
    require 'tmpdir'
    require 'bundler'

    # The suite already runs everything under CATARACT_PURE=1, but that leaves
    # the compiled extension on disk. This installs the built gem with no
    # extension at all - the only way to catch a stub Makefile that stops
    # satisfying RubyGems, or a file the pure backend needs dropping out of
    # spec.files.
    Dir.mktmpdir do |dir|
      gem_file = File.join(dir, 'cataract-pure-only.gem')
      gem_home = File.join(dir, 'gems')
      env = { 'GEM_HOME' => gem_home, 'GEM_PATH' => gem_home }
      scratch = File.realpath(dir)

      check = <<~RUBY
        require 'cataract'

        # Confirm this is the gem just built, not one already on the system.
        spec = Gem.loaded_specs['cataract']
        unless spec && File.realpath(spec.full_gem_path).start_with?('#{scratch}')
          raise "cataract loaded from \#{spec&.full_gem_path.inspect}, not the scratch install"
        end

        # The build recorded the decision rather than it being inferred.
        if Cataract::BuildConfig::NATIVE_EXTENSION
          raise 'BuildConfig::NATIVE_EXTENSION is true; expected the install to have recorded false'
        end

        # The compiled objects are genuinely absent, not merely unused: a stale
        # extension on the load path would satisfy every other assertion here.
        %w[cataract/native_extension cataract/cataract_color].each do |ext|
          begin
            require ext
          rescue LoadError
            next
          end
          raise "\#{ext} loaded; expected no compiled extension to be available"
        end

        unless Cataract::IMPLEMENTATION == :ruby
          raise "Expected the pure backend, got \#{Cataract::IMPLEMENTATION.inspect}"
        end

        unless defined?(Cataract::Backends::Native).nil?
          raise 'Cataract::Backends::Native is defined; the native backend should never have loaded'
        end

        sheet = Cataract::Stylesheet.parse(File.read('sample.css'))
        raise "Expected 3 rules, got \#{sheet.rules_count}" unless sheet.rules_count == 3

        css = sheet.to_s
        raise "Declaration lost: \#{css.inspect}" unless css.include?('color: red')
        raise "Media query lost: \#{css.inspect}" unless css.include?('@media print')

        puts '✓ No compiled extension is loadable'
        puts "✓ Loaded the \#{Cataract::IMPLEMENTATION} backend and parsed \#{sheet.rules_count} rules"
      RUBY

      File.write(File.join(dir, 'sample.css'), "body { color: red; }\n@media print { .a, .b { margin: 0; } }\n")

      # Every subprocess runs outside Bundler. Under `bundle exec` its RUBYOPT
      # reaches `gem install`, which then counts bundled gems as satisfying
      # cataract's dependencies and installs none of them into the scratch
      # home. The check runs without Bundler, cannot activate the gem for want
      # of those dependencies, and RubyGems reports that as a bare
      # "cannot load such file -- cataract".
      Bundler.with_unbundled_env do
        sh 'gem', 'build', 'cataract.gemspec', '-o', gem_file
        sh env, 'gem', 'install', gem_file, '--no-document', '--', '--disable-native-extension'

        compiled = Dir.glob(File.join(gem_home, '**', '*.{so,bundle}'))
        raise "Expected no compiled artifacts, found: #{compiled.join(', ')}" unless compiled.empty?

        puts "\n✓ Nothing was compiled"

        # Runs outside this checkout with CATARACT_PURE unset, so the installed
        # gem has to reach the pure backend on its own rather than be told to.
        # verbose(false) stops rake echoing the whole check script back.
        Dir.chdir(dir) do
          verbose(false) { sh env.merge('CATARACT_PURE' => nil), RbConfig.ruby, '-e', check }
        end
      end
    end

    puts "\n✓ Pure-only install verified"
  end

  desc 'Bump version (usage: rake gem:bump[major|minor|patch])'
  task :bump, [:type] do |_t, args|
    type = args[:type] || 'patch'
    unless %w[major minor patch].include?(type)
      abort "Invalid version bump type: #{type}. Use: major, minor, or patch"
    end

    version_file = 'lib/cataract/version.rb'
    content = File.read(version_file)

    # Extract current version
    current_version = content[/VERSION = ['"](.+?)['"]/, 1]
    major, minor, patch = current_version.split('.').map(&:to_i)

    # Bump version
    case type
    when 'major'
      major += 1
      minor = 0
      patch = 0
    when 'minor'
      minor += 1
      patch = 0
    when 'patch'
      patch += 1
    end

    new_version = "#{major}.#{minor}.#{patch}"

    # Update file
    new_content = content.gsub(/VERSION = ['"]#{Regexp.escape(current_version)}['"]/, "VERSION = '#{new_version}'")
    File.write(version_file, new_content)

    puts "Version bumped: #{current_version} → #{new_version}"
    puts "\nNext steps:"
    puts "  1. Review changes: git diff #{version_file}"
    puts '  2. Update CHANGELOG.md'
    puts "  3. Commit: git commit -am 'Bump version to #{new_version}'"
  end

  desc 'Prepare release commit (prep, bump version, commit)'
  task :release_commit, [:type] => :prep do |_t, args|
    type = args[:type] || 'patch'

    # Check for uncommitted changes (ignore untracked files)
    modified_files = `git status --porcelain`.lines.reject { |line| line.start_with?('??') }
    unless modified_files.empty?
      abort 'ERROR: Working directory has uncommitted changes. Commit or stash them first.'
    end

    # Check we're on main branch
    current_branch = `git rev-parse --abbrev-ref HEAD`.strip
    unless current_branch == 'main'
      puts "WARNING: You're on branch '#{current_branch}', not 'main'"
      print 'Continue anyway? (y/N): '
      response = $stdin.gets.chomp
      abort 'Aborted.' unless response.downcase == 'y'
    end

    # Bump version
    Rake::Task['gem:bump'].invoke(type)

    # Reload version
    load 'lib/cataract/version.rb'
    new_version = Cataract::VERSION

    # Auto-generate CHANGELOG with git-cliff
    puts "\n#{'=' * 80}"
    puts 'Generating CHANGELOG.md with git-cliff...'
    puts '=' * 80

    if system('which git-cliff > /dev/null 2>&1')
      sh "git-cliff --tag v#{new_version} --output CHANGELOG.md"
      puts '✓ CHANGELOG.md generated'

      # Show the changelog for review
      puts "\nGenerated CHANGELOG (preview):"
      puts '-' * 80
      system('head -n 50 CHANGELOG.md')
      puts '-' * 80

      print "\nAccept this CHANGELOG? (Y/n): "
      response = $stdin.gets.chomp
      abort 'Aborted. Edit CHANGELOG.md manually if needed.' if response.downcase == 'n'
    else
      puts 'WARNING: git-cliff not found. Please update CHANGELOG.md manually.'
      puts 'Install: cargo install git-cliff'
      puts "\nPress Enter when ready to commit..."
      $stdin.gets

      # Check if CHANGELOG was actually updated
      changelog_diff = `git diff CHANGELOG.md`
      if changelog_diff.strip.empty?
        puts 'WARNING: CHANGELOG.md was not modified'
        print 'Continue anyway? (y/N): '
        response = $stdin.gets.chomp
        abort 'Aborted. Please update CHANGELOG.md first.' unless response.downcase == 'y'
      end
    end

    # Commit changes with Release Bot as author
    commit_message = "Release v#{new_version}"
    git_email = `git config user.email`.strip
    sh 'git add lib/cataract/version.rb CHANGELOG.md'
    sh "git commit --author 'Release Bot <#{git_email}>' -m '#{commit_message}'"

    puts "\n#{'=' * 80}"
    puts "✓ Release commit created: #{commit_message}"
    puts '=' * 80
    puts "\nNext steps:"
    puts '  1. Review commit: git show'
    puts '  2. Push to GitHub: git push'
    puts '  3. Create release: rake release (builds gem, creates tag, pushes to rubygems)'
    puts '=' * 80
  end
end
