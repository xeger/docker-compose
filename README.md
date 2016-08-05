[![Build Status](https://travis-ci.org/xeger/docker-compose.svg)](https://travis-ci.org/xeger/docker-compose) [![Coverage Status](https://coveralls.io/repos/github/xeger/docker-compose/badge.svg?branch=coveralls)](https://coveralls.io/github/xeger/docker-compose?branch=coveralls) [![Docs](https://img.shields.io/badge/docs-rubydoc-blue.svg)](http://www.rubydoc.info/gems/docker-compose)

# Docker::Compose

This is a Ruby OOP wrapper for the [docker-compose](https://github.com/docker/compose)
container orchestration tool from Docker Inc.

In addition to wrapping the CLI, this gem provides an environment-variable mapping
feature that allows you to export environment variables into your _host_ that point
to network services exposed by containers. This allows you to run an application on
your host for quicker and easier development, but run all of its dependencies --
database, cache, adjacent services -- in containers. The dependencies can even run
on another machine, e.g. a cloud instance or a container cluster, provided your
development machine has TCP connectivity to every port exposed by a container.  

Throughout this documentation we will refer to this gem as `Docker::Compose`
as opposed to the `docker-compose` tool that this gem wraps.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'docker-compose'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install docker-compose

## Usage

### Invoking from Ruby code

```ruby
require 'docker/compose'

# Create a new session in Dir.pwd using the file "docker-compose.yml".
# For fine-grained control over options, see Docker::Compose::Session#new
compose = Docker::Compose.new

compose.version

compose.up(detached:true)

exited = compose.ps.where { |c| !c.up? }
puts "We have some exited containers: " + exited.join(', ')

sum = compose.ps.inject(0) { |a,c| a + c.size }
puts format("Composition is using %.1f MiB disk space", sum/1024.0**2)
```

### Invoking from Rake

Open your Rakefile and add the Docker::Compose tasks.

```ruby
require 'docker/compose/rake_tasks'

Docker::Compose::RakeTasks.new do |tasks|
    # customize by calling setter methods of tasks;
    # see the class documentation for details
end

```

Notice that `rake -T` now has a few additional tasks for invoking gem
functionality. You can `docker:compose:env` to print shell exports for
host-to-container environment mapping, or you can `docker:compose:host[foo]`.

### Hosting a Command

To run a process on your host and allow it to talk to containers, use
the `docker:compose:host` task. For example, I could enter a shell
with `rake docker:compose:host[bash]`.

Before "hosting" your command, the Rake task exports some environment
variables that your command can use to discover services running in
containers. Your Rakefile specifies which variables your app needs
(the `host_env` option) and which container information each variable should
map to.

By hosting commands, you benefit from easier debugging and code editing of
the app you're working on, but still get to rely on containers to provide
the companion services your app requires to run.

### Mapping container IPs and ports

As a trivial example, let's say that your `docker-compose.yml` contains one
service, the database that your app needs in order to run.

```yaml
db:
  image: mysql:latest
  environment:
    MYSQL_DATABASE: myapp_development
    MYSQL_ROOT_PASSWORD: opensesame
  ports:
    - "3306"

```

Your app needs two inputs, `DATABASE_HOST` and `DATABASE_PORT`. You can specify
this with the host_env option of the Rake task:

```ruby
Docker::Compose::RakeTasks.new do |tasks|
    tasks.host_env = {
        'DATABASE_HOST' => 'db:[3306]',
        'DATABASE_PORT' => '[db]:3306',
    }
end
```

Now, I can run my services, ask Docker::Compose to map the environment values
to the actual IP and port that `db` has been published to, and run my app:

```bash
# First, bring up the containers we will be interested in
user@machine$ docker-compose up -d

# The rake task prints bash code resembling the following:
#   export DATABASE_HOST='127.0.0.1'
#   export DATABASE_PORT='34387'
# We eval it, which makes the variables available to our shell and to all
# subprocesses.
user@machine$ eval "$(bundle exec rake docker:compose:env)"

user@machine$ bundle exec rackup
```

The `host_env` option also handles substitution of URLs, and arrays of values
(which are serialized back to the environment as JSON)
For example:

```ruby
tasks.host_env = {
  'DATABASE_URL' => 'mysql://db:3306/myapp_development',
  'MIXED_FRUIT' => ['db:[3306]', '[db]:3306']
}
```

This would result in the following exports:

```bash
export DATABASE_URL='mysql://127.0.0.1:34387/myapp_development'
export MIXED_FRUIT='["127.0.0.1", "34387"]'
```

To learn more about mapping, read the class documentation for
`Docker::Compose::Mapper`.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/xeger/docker-compose. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
