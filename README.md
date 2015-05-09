# lita-rundeck

[![Build Status](https://travis-ci.org/harlanbarnes/lita-rundeck.png?branch=master)](https://travis-ci.org/harlanbarnes/lita-rundeck)
[![Coverage Status](https://coveralls.io/repos/harlanbarnes/lita-rundeck/badge.png)](https://coveralls.io/r/harlanbarnes/lita-rundeck)

**lita-rundeck** is a handler for [Lita](https://github.com/jimmycuadra/lita) that interacts with a [Rundeck](http://rundeck.org/) server.

## Installation

Add lita-rundeck to your Lita instance's Gemfile:

``` ruby
gem "lita-rundeck"
```

## Configuration

### Required Attributes

* ```url``` (String) - URL to then Rundeck server. Default: ```nil```
* ```token``` (String) - API token for access to the Rundeck server. Default: ```nil```

### Optional Attributes

* ```api_debug``` (Boolean) - When ```conf.robot.log_level``` is set to ```:debug``` enable verbose details of the API interaction. Default: ```false```

### Example

```ruby
Lita.configure do |config|
  config.handlers.rundeck.url = "https://rundeck.mycompany.org"
  config.handlers.rundeck.token = "abcdefghijzlmnopqrstuvwxyz"
  config.handlers.rundeck.api_debug = true
end
```

## Usage

### Run

Start a job execution. Optionally, have Lita return part or all of the output log to the channel when complete.

Syntax:
```
rundeck run ALIAS|--project NAME --job NAME [--options KEY=VALUE,KEY=VALUE] [--report all|NUMBER]
```

* Pass either an alias name or `--project` AND `--name` to execute the job
* Optionally, pass Job options (defined in rundeck itself) as key/value pairs delimited by a comma
* Finally, add `--report` with the string `all` to return the entirety of the log output to the channel once the job is complete. (Note Lita won't begin checking for job completion until the average duration of the job is complete.) You can also limit the output reported back to the channel. To do this, give the `--report` option an integer representing the number of lines to return from the end of the log.

Examples:

```
Lita > lita rundeck run aliasfoo
Execution 285 is running. Average job duration is 1.717 seconds.

Lita > rundeck run aliasfoo --options SECONDS=60
Execution 286 is running. Average job duration is 1.717 seconds.

Lita > rundeck run --project Litatest --job dateoutput
Execution 287 is running. Average job duration is 1.717 seconds.

Lita > rundeck run --project Litatest --job dateoutput --options SECONDS=60
Execution 288 is running. Average job duration is 1.717 seconds.

Lita > rundeck run --project Litatest --job dateoutput --options SECONDS=60,FORMAT=iso8601
Execution 289 is running. Average job duration is 1.717 seconds.

Lita > rundeck run --project Litatest --job dateoutput --options SECONDS=60,FORMAT=iso8601 --report 5
Execution 289 is running. Average job duration is 1.717 seconds.
Execution 289 output:
  18:18:27 26 Sat May 9 18:18:27 UTC 2015
  18:18:28 27 Sat May 9 18:18:28 UTC 2015
  18:18:29 28 Sat May 9 18:18:29 UTC 2015
  18:18:30 29 Sat May 9 18:18:30 UTC 2015
  18:18:31 30 Sat May 9 18:18:31 UTC 2015
Execution 289 is complete (took 30.49s)
```

* Users must be [added by a Lita admin](http://docs.lita.io/getting-started/usage/#authorization-groups) to the rundeck_users group to execute jobs
* Job names with spaces need to be quoted
* Multiple options can be submitted via comma-delimited key pairs
* Jobs identified via fully qualified project and job names (i.e. --project and --job) or via a registered alias

### Projects

List projects

```
Lita > lita rundeck projects
[Litatest] - https://rundeck.mycompany.org/api/10/project/Litatest
```

### Jobs

List jobs

```
Lita > lita rundeck jobs
[Litatest] - dateoutput
[Litatest] - refreshcache
```

### Executions

List executions (activity)

```
Lita > lita rundeck executions
295 succeeded Shell User [Litatest] dateoutput SECONDS:600 start:2014-08-16T04:36:43Z end:2014-08-16T04:46:46Z
296 succeeded Shell User [Litatest] dateoutput SECONDS:60 start:2014-08-16T05:17:07Z end:2014-08-16T05:18:09Z
```

* Fields are: id, status, submitter, project, job, options, start and end

Optionally, limit the output to a number of executions

```
Lita > lita rundeck executions 1
296 succeeded Shell User [Litatest] dateoutput SECONDS:60 start:2014-08-16T05:17:07Z end:2014-08-16T05:18:09Z
```

### Running

List currently running executions

```
Lita > lita rundeck running
297 running Shell User [Litatest] dateoutput SECONDS:60 start:2014-08-16T05:46:32Z
```

### Output

List log output for given execution (showing last 10 lines, by default):

```
Lita > lita output 5
Execution 5 output:
  23:16:30 Text of line 1
  23:16:31 Text of line 2
  23:16:32 Text of line 3
  23:16:33 Text of line 4
  23:16:34 Text of line 5
  23:16:35 Text of line 6
  23:16:36 Text of line 7
  23:16:37 Text of line 8
  23:16:38 Text of line 9
  23:16:39 Text of line 10
Execution 5 is complete (took 10.348s)
EOF
```

Optionally, take an extra integer for the number lines to return:

```
Lita > rundeck output 5 5
Execution 5 output:
  23:16:35 Text of line 6
  23:16:36 Text of line 7
  23:16:37 Text of line 8
  23:16:38 Text of line 9
  23:16:39 Text of line 10
Execution 5 is complete (took 10.348s)
```

### Options

List options for a job in detail

```
Lita > lita rundeck options aliasfoo
[Litatest] - dateoutput
  * SECONDS (REQUIRED) - Number of seconds to run
```

* Aliases or full qualified job and project names (i.e. --project and --name) can be used

### Aliases

List aliases with

```
Lita > lita rundeck aliases
Alias = [Project] - Job
 aliasfoo = [Litatest] - dateoutput
```

Register a new alias

```
Lita > rundeck alias register aliasfoo --project Litatest --job dateoutput
Alias registered
```

Forget (remove) an alias

```
Lita > lita rundeck alias forget aliasfoo
Alias removed
```

### Info

Lists the server version and users allowed to execute jobs

```
Lita > lita rundeck info
System Stats for Rundeck 2.0.4 on node rundeck.mycompany.org
Users allowed to execute jobs: Shell User
```

## License

[MIT](http://opensource.org/licenses/MIT)
