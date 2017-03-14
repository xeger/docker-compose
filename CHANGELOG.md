1.1
---

#### New features

Add `scale` command to Session methods.


1.0
---

No significant changes; the 1.0 increment is to indicate that Docker::Compose now has test coverage, and that we intend to maintain a stable API until 2.0.

0.6
---

#### Interface-breaking changes

  - Replaced `docker:compose:server` Rake task with more general `docker:compose:host`
    - Replaced `server_env` option with `host_env`
    - Replaced `extra_server_env` option with `extra_host_env`
  - Stopped mapping values in `extra_host_env`; they are now exported verbatim

#### New features

Produce `docker:compose:env` output that is compatible with user's login shell.

0.5
---

Initial public release of prototype. Features work well, but there is no test
coverage.
