require 'xmlsimple'
require 'lita-keyword-arguments'

module Lita
  module Handlers
    class Rundeck < Handler

      route /rundeck info/i,
        :info, command: true, help: {
          t("help.info_key") => t("help.info_value")
      }

      route /rundeck project(?:s)?/i,
        :projects, command: true, help: {
          t("help.projects_key") => t("help.projects_value")
      }

      route /rundeck job(?:s)?/i,
        :jobs, command: true, help: {
          t("help.jobs_key") => t("help.jobs_value")
      }

      route /rundeck exec(?:utions)?(?: (\d+)?)?/i,
        :executions, command: true, help: {
          t("help.exec_key") => t("help.exec_value")
      }

      route /rundeck output (\d+)(?: (\d+)?)?/i,
        :output, command: true, help: {
          t("help.output_key") => t("help.output_value")
      }

      route /rundeck running(?: (\d+)?)?/i,
        :running, command: true, help: {
          t("help.running_key") => t("help.running_value")
      }

      route /rundeck alias(?:es)?\s*$/i,
        :aliases, command: true, help: {
          t("help.alias_key") => t("help.alias_value")
      }

      route /rundeck alias register ([a-zA-Z0-9\-+.]+)\s*/i,
        :alias_register,
        command: true,
        kwargs: {
          project: {
            short: "p"
          },
          job: {
            short: "j"
          }
        },
        help: {
          t("help.alias_register_key") => t("help.alias_register_value")
      }

      route /rundeck alias forget ([a-zA-Z0-9\-+.]+)?\s*/i,
        :alias_forget, command: true, help: {
          t("help.alias_forget_key") => t("help.alias_forget_value")
      }

      route /rundeck run(?!ning)(?: ([a-zA-Z0-9\-+.]+))?\s*/i,
        :run,
        command: true,
        kwargs: {
          project: {
            short: "p"
          },
          job: {
            short: "j"
          },
          options: {
            short: "o"
          },
          report: {
            short: "r"
          }
        },
        help: {
          t("help.run_key") => t("help.run_value")
        }

      route /rundeck options(?: ([a-zA-Z0-9\-+.]+))?\s*/i,
        :options,
        command: true,
        kwargs: {
          project: {
            short: "p"
          },
          job: {
            short: "j"
          }
        },
        help: {
          t("help.options_key") => t("help.options_value")
        }


      def self.default_config(config)
        config.url       = nil
        config.token     = nil
        config.api_debug = false
      end

      def info(response)
        text = []
        output = client.info
        return unless output

        text.push(output)
        if users
          text.push(t("info.users_allowed") +
            users.map{ |u| u.name }.join(",") )
        else
          text.push(t("info.no_users"))
        end
        response.reply text.join("\n")
      end

      def projects(response)
        text = []
        client.projects.each do |p|
          text.push("[#{p.name}] - #{p.href}")
        end
        if text.empty?
          response.reply t("projects.none")
        else
          response.reply text.join("\n")
        end
      end

      def jobs(response)
        text = []
        client.jobs.each do |j|
          line = ""
          if alias_name = aliasdb.reverse(j.project,j.name)
            line = "#{alias_name} = "
          end
          text.push(line + "[#{j.project}] - #{j.name}")
        end
        if text.empty?
          response.reply t("jobs.none")
        else
          response.reply text.join("\n")
        end
      end

      def executions(response)
        max = response.matches[0][0] if response.matches[0][0]

        text = []
        client.executions(max).each do |e|
          text.push(e.pretty_print)
        end

        if text.empty?
          response.reply t("executions.none")
        else
          response.reply text.join("\n")
        end
      end

      def running(response)
        max = response.matches[0][0] if response.matches[0][0]

        text = []
        client.running(max).each do |e|
          text.push(e.pretty_print)
        end

        if text.empty?
          response.reply t("executions.none")
        else
          response.reply text.join("\n")
        end
      end

      def run(response)
        unless user_in_group?(response.user)
          response.reply t("run.unauthorized")
          return
        end

        args = response.extensions[:kwargs]
        name = response.matches[0][0]

        project = args[:project]
        job     = args[:job]
        user    = response.user.name || response.user.id || robot.name
        options = parse_options(args[:options]) if args[:options]

        # keyword arguments win over an alias (if someone happens to give both)
        unless project && job
          project, job = aliasdb.forward(name)
        end

        unless project && job
          response.reply t("misc.job_not_found")
          return
        end

        execution = client.run(project,job,options,user)
        response.reply resolve(execution)

        if execution.status == 'running' && args[:report]
          report_back(response, execution, args[:report])
        end
      end

      def report_back(response, execution, output_limit)
        # remove the output log line limit if value is 'all' or 'full'
        output_limit = nil if /^all$|^full$/i.match(output_limit)

        # wait the average duration + 1s
        average_duration = execution.job.average_duration.to_i / 1000
        sleep average_duration + 1

        # check if complete and loop until complete with 10 second check / announce
        while true
          execution = client.execution(execution.id)
          if execution.status == 'running'
            current_duration = Time.now.to_i - execution.start_unixtime.to_i / 1000
            response.reply t(
              "run.still_running",
              id: execution.id,
              current_duration: current_duration,
              average_duration: average_duration
              )
            sleep 10
          else
            response.reply client.output(execution.id, output_limit).pretty_print_output
            return
          end
        end
      end

      def resolve(e)
        case e.status
        when "running"
          t("run.success", id: e.id, average_duration: e.job.average_duration.to_f / 1000.0)
        when "api.error.execution.conflict"
          t("run.conflict")
        when "api.error.item.unauthorized"
          t("run.token_unauthorized")
        when "api.error.job.options-invalid"
          e.message.gsub(/\n/,"")
        end
      end

      def output(response)
        id  = response.matches[0][0]
        max = response.matches[0][1] if response.matches[0][1]

        output = client.output(id, max)

        if output.error_code && output.error_code == 'api.error.item.doesnotexist'
          response.reply t("misc.execution_not_found")
        else
          response.reply output.pretty_print_output
        end
      end

      def parse_options(string)
        options = {}
        pairs = string.split(/\|/)
        pairs.each do |p|
          if p =~ /\=/
            k,v = p.split(/\=/)
            options[k] = v
          end
        end
        options
      end

      def options(response)
        args = response.extensions[:kwargs]
        name = response.matches[0][0]

        project = args[:project]
        job     = args[:job]

        # keywoard arguments win over an alias (if someone happens to give both)
        unless project && job
          project, job = aliasdb.forward(name)
        end

        unless project && job
          response.reply t("misc.job_not_found")
          return
        end

        response.reply "[#{project}] - #{job}\n" + 
          client.definition(project,job).pretty_print_options
      end

      def aliases(response)
        all = aliasdb.all
        if all.empty?
          response.reply t("alias.none")
        else
          text = [ t('alias.list') ]
          text.push(all.map{ |a| " #{a["id"]} = [#{a["project"]}] - #{a["job"]}" })
          response.reply text.join("\n")
        end
      end

      def alias_register(response)
        args    = response.extensions[:kwargs]
        name    = response.matches[0][0]
        project = args[:project]
        job     = args[:job]

        if name && project && job
          begin
            aliasdb.register(name,project,job)
            response.reply t("alias.registered")
          rescue ArgumentError
            response.reply t("alias.exists")
          end
        else
          response.reply t("alias.format")
        end
      end

      def alias_forget(response)
        name = response.matches[0][0]
        begin
          aliasdb.forget(name)
          response.reply t("alias.forgotten")
        rescue ArgumentError
          response.reply t('alias.notexists')
        end
      end

      def user_in_group?(user)
        Lita::Authorization.user_in_group?(user,:rundeck_users)
      end

      def users
        Lita::Authorization.groups_with_users[:rundeck_users]
      end

      def url
        @url ||= Lita.config.handlers.rundeck.url
      end

      def token
        @token ||= Lita.config.handlers.rundeck.token
      end

      def api_debug
        @api_debug ||= Lita.config.handlers.rundeck.api_debug
      end

      def client
        @client ||= API::Client.new(url,token,http,log,api_debug)
      end

      def aliasdb
        @aliasdb ||= Database::Alias.new(redis)
      end

      module Database
        class Alias
          attr_accessor :redis

          def initialize(redis)
            @redis = redis
          end

          def akey(id)
            "alias:#{id}"
          end

          def akeys
            redis.keys("alias:*")
          end

          def ids
            akeys.map { |e| e.split(/:/).last }
          end

          def register(id,project,job)
            if registered?(id)
              raise ArgumentError, "Alias already exists"
            else
              save(id,project,job)
            end
          end

          def forget(id)
            if registered?(id)
              delete(id)
            else
              raise ArgumentError, "Alias does not exist"
            end
          end

          def save(id,project,job)
            redis.hmset(akey(id), "project", project, "job", job)
          end

          def delete(id)
            redis.del(akey(id))
          end

          def forward(id)
            redis.hmget(akey(id), "project", "job")
          end

          def reverse(project,job)
            ids.select{ |n| p, j = forward(n); p == project && j == job }.first
          end

          def all
            list = []
            ids.each do |id|
              hash = {}
              hash["id"] = id
              hash["project"], hash["job"] = forward(id)
              list.push(hash)
            end
            list
          end

          def registered?(id)
            project, job = forward(id)
            if project && job
              true
            else
              false
            end
          end
        end
      end

      module API
        class Client
          attr_accessor :url, :token

          MAX_EXECUTIONS = 10
          MAX_OUTPUT     = 10

          def self.ensure_array(ref)
            return [ref] if ref.is_a?(Hash)
            return ref   if ref.is_a?(Array)
          end

          def initialize(url, token, http, log, debug=false)
            @url   = url
            @token = token
            @http  = http
            @log   = log
            @debug = debug
          end

          def get(path,options={})
            uri = "#{@url}#{path}"
            # Replace double slashes with a single one, excluding the // after the :
            uri.gsub!(/([^:])\/\//, '\1/')
            options[:authtoken] = @token

            request_failed = false

            http_response = @http.get(
              uri,
              options
            )

            hash = {}
            if http_response.body =~ /<.*?>/m
              # Trying to avoid nokogiri but not wanting to use ReXML directly,
              # hence the xmlsimple gem. ForceArray has usually worked well for
              # me, but this XML data seemed to cause it to be inconsistent. So
              # the ensure_array method and a little extra code has worked.
              hash = ::XmlSimple.xml_in(
                http_response.body,
                {
                  "ForceArray" => false,
                  "GroupTags"  => {
                    "options"    => "option"
                  }
                }
              )
            else
              @log.error "Request failed: API response not XML"
              request_failed = true
            end

            if @debug || request_failed
              output = options.map{ |k,v| "#{k.to_s}=#{v}" }.join("&")
              @log.debug "API request: GET #{uri}&#{output}"
              @log.debug "API response: (HTTP #{http_response.status}) #{http_response.body}"
              @log.debug "Hash: #{hash.inspect}"
            end

            hash
          end

          def info
            response = get('/api/1/system/info')
            response["success"][1]["message"] if response["success"]
          end

          def projects
            @projects ||= Project.all(self).sort_by{|p| p.name}
          end

          def jobs
            @jobs ||= Job.all(self).sort_by{|j| [j.project, j.name]}
          end

          def job(project,name)
            jobs.select{|j| j.project == project && j.name == name}.first
          end

          def definition(project,name)
            Definition.load(self,job(project,name).id)
          end

          def execution(id)
            Execution.load(self, id)
          end

          def executions(max)
            max ||= MAX_EXECUTIONS
            @executions ||= Execution.all(self,max).sort_by{|i| i.id}.reverse[0,max.to_i].reverse
          end

          def running(max)
            max ||= MAX_EXECUTIONS
            @running ||= Running.all(self,max).sort_by{|i| i.id}.reverse[0,max].reverse
          end

          def run(project,name,options,user)
            job = job(project,name)
            Job.run(self,job.id,options,user)
          end

          def output(id, max)
            max ||= MAX_OUTPUT
            Output.load(self, id, max)
          end
        end

        class Project
          attr_accessor :name, :description, :href

          def self.all(client)
            all = []
            response = client.get("/api/1/projects")
            if response["projects"]["count"].to_i > 0
              Client.ensure_array(response["projects"]["project"]).each do |p|
                all.push(Project.new(p))
              end
            end
            all
          end

          def initialize(hash)
            @name        = hash["name"]
            @description = hash["description"]
            @href        = hash["href"]
          end
        end

        class Definition
          attr_accessor :id, :name, :project, :description, :options

          def self.load(client,id)
            response = client.get("/api/1/job/#{id}")
            if response["job"]
              Definition.new(response["job"])
            end
          end

          def initialize(hash)
            @id          = hash["id"]
            @name        = hash["name"]
            @project     = hash["context"]["project"]
            @description = hash["description"]
            if option_response = hash["context"]["options"]
              @options ||= {}
              Client.ensure_array(option_response).each do |o|
                @options[o["name"]] = o
              end
            end
          end

          def pretty_print_options
            text = []
            @options.each do |name,data|
              text.push(
                "  * #{name} " +
                ( data["required"] ? "(REQUIRED) " : "" ) +
                ( data["description"] ? "- #{data["description"]}" : "" )
              )
            end
            text.join("\n")
          end
        end

        class Output
          attr_accessor :id, :entries, :completed, :exec_duration, :error_code, :error_message

          def self.load(client, id, max)
            # @todo Workaround for this: https://github.com/rundeck/rundeck/issues/1207
            max = max.to_i + 2
            response = client.get("/api/5/execution/#{id}/output?lastlines=#{max}")
            if response["output"]
              Output.new(response["output"]) 
            elsif response["error"][0]
              Output.new(
                "id" => id,
                "error_code"  => response["error"][1]["code"],
                "error_message" => response["error"][1]["message"]
              )
            end
          end

          def initialize(hash)
            @id            = hash["id"]

            if hash["completed"] == "true"
              @completed = true
            elsif hash["completed"] == "false"
              @completed = false
            end

            @exec_duration = hash["execDuration"]

            @entries       = []
            if hash["entries"] && hash["entries"]["entry"]
              @entries = hash["entries"]["entry"]
            end

            @error_code    = hash["error_code"]
            @error_message = hash["error_message"]
          end

          def pretty_print_output
            text = ["Execution #{id} output:"]
            entries.each do |entry|
              text.push("  #{entry["time"]} #{entry["content"]}")
            end

            if @completed
              text.push("Execution #{id} is complete (took #{@exec_duration.to_i  / 1000.0}s)")
            else
              text.push("Execution #{id} is not complete (running #{@exec_duration.to_i / 1000.0}s)")
            end
            text.join("\n")
          end
        end

        class Job
          attr_accessor :id, :name, :group, :project, :description,
                        :average_duration, :options

          def self.all(client)
            all = []
            client.projects.each do |p|
              response = client.get("/api/2/project/#{p.name}/jobs")
              if response["jobs"]["count"].to_i > 0
                Client.ensure_array(response["jobs"]["job"]).each do |j|
                  all.push(Job.new(j))
                end
              end
            end
            all
          end

          def self.run(client,id,options,user)
            args             = {}
            args[:asUser]    = user if user
            if options
              arg_string = []
              options.each do |k,v|
                arg_string.push("-#{k} #{v}")
              end
              args[:argString] = arg_string.join(" ")
            end

            api_response = client.get("/api/5/job/#{id}/run", args)

            if api_response["success"]
              Execution.new(api_response["executions"]["execution"])
            elsif api_response["error"][0]
              Execution.new(
                "status" => api_response["error"][1]["code"],
                "message" => api_response["error"][1]["message"]
              )
            end
          end

          def initialize(hash)
            @id               = hash["id"]
            @name             = hash["name"]
            @group            = hash["group"]
            @project          = hash["project"]
            @description      = hash["description"]
            @average_duration = hash["averageDuration"] if hash["averageDuration"]
            @options          = Client.ensure_array(hash["options"]) if hash["options"]
          end
        end

        class Execution
          attr_accessor :id, :href, :status, :message, :project, :user, :start, :start_unixtime,
                        :end, :end_unixtime, :job, :description, :argstring, :successful_nodes,
                        :failed_nodes, :aborted_by

          def self.all(client,max)
            all = []
            client.projects.each do |p|
              response = client.get("/api/5/executions",
                                    project: p.name, max: max)
              if response["executions"]["count"].to_i > 0
                list = Client.ensure_array(response["executions"]["execution"])
                list.each do |e|
                  all.push(Execution.new(e))
                end
              end
            end
            all
          end

          def self.load(client, id)
            response = client.get("/api/1/execution/#{id}")
            Execution.new(response["executions"]["execution"]) if response["executions"]["count"].to_i == 1
          end

          def initialize(hash)
            @id               = hash["id"]
            @href             = hash["href"]
            @status           = hash["status"]
            @message          = hash["message"]
            @project          = hash["project"]
            @user             = hash["user"]

            if hash["date-started"]
              @start_unixtime = hash["date-started"]["unixtime"]
              @start          = hash["date-started"]["content"]
            end

            if hash["date-ended"]
              @end_unixtime = hash["date-ended"]["unixtime"]
              @end          = hash["date-ended"]["content"]
            end

            @job              = Job.new(hash["job"]) if hash["job"]
            @description      = hash["description"]
            @argstring        = hash["argstring"]
            @aborted_by       = hash["aborted_by"]
            @successful_nodes = Client.ensure_array(hash["successful_nodes"]["node"]) if hash["successful_nodes"]
            @failed_nodes     = Client.ensure_array(hash["failed_nodes"]["node"]) if hash["failed_nodes"]
          end

          def pretty_print
            line =  "#{@id} #{@status} #{@user} [#{@job.project}] #{@job.name} "
            line += @job.options.map { |o| "#{o["name"]}:#{o["value"]}" }.join(", ") + " " if @job.options
            line += "start:#{@start}" + ( @end ? " end:#{@end}" : "" )
          end
        end

        class Running < Execution

          def self.all(client,max)
            all = []
            client.projects.each do |p|
              response = client.get("/api/5/executions/running",
                                    project: p.name, max: max)
              if response["executions"]["count"].to_i > 0
                list = Client.ensure_array(response["executions"]["execution"])
                list.each do |e|
                  all.push(Execution.new(e))
                end
              end
            end
            all
          end

        end
      end
    end

    Lita.register_handler(Rundeck)
  end
end
