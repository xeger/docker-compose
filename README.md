# Docker::Compose

This is a Ruby OOP wrapper for the [docker-compose](https://github.com/docker/compose)
command-line tool. It also contains some features that layer nicely on top of
docker-compose to enhance your productivity.

Distinctive features of this gem:

1) Simulates environment-variable substitution in the style of docker-compose
   1.5; sequences such as ${FOO} in your YML will be replaced with the
   corresponding environment variable. (This feature will go away once 1.5
   is released.)

2) Environment-variable mapping that allows you to export environment variables
   into your _host_ that point to network services published by containers.


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

# Create a new session in Dir.pwd using the file "docker-compose.yml"
# for fine-grained control over options, see Docker::Compose::Session#new
compose = Docker::Compose.new

compose.version

compose.up(detached:true)
```

### Invoking from Rake

Open your Rakefile and add the docker-compose tasks

```ruby
require 'docker/compose/rake_tasks'

Docker::Compose::RakeTasks.new do |tasks|
    # customize by calling setter methods of tasks;
    # see the class documentation for details
end

```

Notice that `rake -T` now has a few additional tasks for invoking gem
functionality. You can `docker:compose:env` to print bash export statements
for host-to-container environment mapping; you can `docker:compose:up` or
`docker:compose:stop` to start and stop containers.

Note that the `docker-compose` command is a perfectly valid way to start
and stop containers, but the gem provides some env-substitution functionality
for your YML files that will be built into docker-compose 1.5 but is not
released yet. If your YML contains `${ENV}` references, i.e. in order to
point your containers at network services running on the host, then you must
invoke docker-compose through Rake in order to peform the substitution.

### Mapping container IPs and ports

Assuming that your app accepts its configuration in the form of environment
variables, you can use the `docker:compose:env` to export environment values
into your bash shell that point to services running inside containers. This
allows you to run the app on your host (for easier debugging and code editing)
but let it communicate with services running inside containers.

Docker::Compose uses a heuristic to figure out which IP your services
are actually reachable at; the heuristic works regardless whether you are
running "bare" docker daemon on localhost, communicating with a docker-machine
instance, or even using a cloud-hosted docker machine!

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
this in the env section of the Rake task:

```ruby
Docker::Compose::RakeTasks.new do |tasks|
    tasks.env = {
        'DATABASE_HOST' => 'db:[3306]'
        'DATABASE_PORT' => '[db]:3306'
    }
end
```

(If I had a `DATABASE_URL` input, I could provide a URL such as
`mysql://db/myapp_development`; Docker::Compose would parse the URL and replace
the hostname and port appropriately.)

Now, I can run my services, ask Docker::Compose to map the environment values
to the actual IP and port that `db` has been published to, and run my app:

```bash
user@machine$ docker-compose up -d

# This prints bash code resembling the following:
#   export DATABASE_HOST=127.0.0.1
#   export DATABASE_PORT=34387
# We eval it, which makes the variables available to our shell and to all
# subprocesses.
user@machine$ eval "$(bundle exec rake docker:compose:env)"

user@machine$ bundle exec rackup
```

To learn more about mapping, read the class documentation for
`Docker::Compose::Mapper`.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/docker-compose. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

