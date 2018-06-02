# cyclone

A simple example on the use of
[`distributed-process`](https://github.com/haskell-distributed/distributed-process)
to model a network of nodes that continuously send random numbers (in the
interval `(0, 1]`) to each other.

## Installation

This project can be built using
[`stack`](https://docs.haskellstack.org/en/stable/README/):

```sh
stack build
```

After building it, `cyclone` can be run either using `stack exec`:

```sh
stack exec cyclone -- --help
```

Or installed locally:

```sh
stack install && cyclone --help
```

## Usage

`cyclone` can be started either as a master or a slave. 

To start cyclone as a slave use the `slave` command:

```sh
cyclone slave -p 3949
```

If the `slave` command is not present, `cyclone` will be started as a master,
querying the local network for available slaves, and starting the
number-sending processes on those slaves.

The master process require slave nodes to be running when the master is
invoked. 

Pass the `--help` flag to `cyclone` to see all the available options.

For convenience, we also provide a helper tool called `cyclone-spawn` (which
can be built and executed as described above), which allows to run a series of
commands that are specified in a configuration file (see
[`.cyclone-spawn.config`](.cyclone-spawn.config)). By means of this
configuration file, several nodes can be started:

```sh
stack exec cyclone -- slave -p 9091
stack exec cyclone -- slave -p 9092
stack exec cyclone -- slave -p 9093
stack exec cyclone -- slave -p 9094
```

And also, in Unix platforms, the `timeout` command provides a convenient way of
simulating node failures:

```sh
stack exec cyclone -- slave -p 9091
timeout 4 stack exec cyclone -- slave -p 9095
timeout 7 stack exec cyclone -- slave -p 9096

```

## Manual testing

To test the program, you could use a command like the following:

```sh
stack exec cyclone-spawn & \
(sleep 1; stack exec cyclone -- --send-for 3 --wait-for 1 --with-seed 8475)
```

Or with a custom configuration file:
```sh
stack exec cyclone-spawn  -- .cyclone-spawn-failures.config & \
 (sleep 1; stack exec cyclone -- --send-for 13 --wait-for 1 --with-seed 8475)
```
