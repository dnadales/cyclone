# cyclone

A simple example on the use of
[`distributed-process`](https://github.com/haskell-distributed/distributed-process)
to model a network of nodes that continuously send to each other random numbers
in the interval `(0, 1]`. The nodes send message for a given period of time (see
`--send-for`), after which a grace period (see `--wait-for`) is started in
which each node calculates the following result:

```haskell
sum $ zipWith (*) [1..] (value <$> ns)
```

where `ns` is the list of received numbers, ordered by timestamp.

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
[`test/basic.config`](test/basic.config)). By means of this
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
stack exec cyclone-spawn test/basic.config & \
(sleep 1; stack exec cyclone -- --send-for 3 --wait-for 1 --with-seed 8475)
```

See the [`test`](test/) directory for a list of nodes configurations to test
the program with.

## What works and what doesn't

`cyclone` seems to work under no-failure scenarios. However, due to the large
number of messages being sent, of test cases such as
[`test/large-no-failures.config`](`test/large-no-failures.config`), a large
grace period is needed for all the messages to arrive to all the nodes after
the sending period.

Upon a node failure, the other nodes re-send to each other the last messages
they saw from the node that failed. While this approach seems to work fine for
the [`test/single-failure.config`](`test/single-failure.config`) scenario
(given a large enough grace period), other failure scenarios produce
inconsistent results.
