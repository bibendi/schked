# Schked

Framework agnostic Rufus-scheduler wrapper to run recurring jobs.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "schked"
```

And then execute:

```sh
bundle
```

Or install it yourself as:

```sh
gem install schked
```

## Usage

### Ruby on Rails

.schked

```
--require config/environment
```

config/schedule.rb

```ruby
cron "*/5 * * * *" do
  Scheduler::CleanOrphanAttachmentsJob.perform_later
end
```

config/initializers/schked.rb

```ruby
Schked.file_paths << Rails.root.join("config", "schedule.rb")
```

engines/lib/foo/engine.rb

```ruby
module Foo
  class Engine < ::Rails::Engine
    initializer "foo" do |app|
      Schked.file_paths << root.join("config", "schedule.rb")
    end
  end
end
```

And run Schked:

```sh
bundle exec schked start
```

To show schedule:

```sh
bundle exec schked show
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/schked. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Schked project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/schked/blob/master/CODE_OF_CONDUCT.md).
