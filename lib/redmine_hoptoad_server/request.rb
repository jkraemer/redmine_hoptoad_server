require 'pp'

module RedmineHoptoadServer
  class Request

    TRACE_FILTERS = [
      /^On\sline\s#\d+\sof/,
      /^\d+:/
    ]

    attr_reader :notice, :environment, :repo_root, :priority, :author
    attr_accessor :project_trace_filters

    def initialize(notice, redmine_params = notice.redmine_params)
      @project_trace_filters = []
      @notice = notice
      @redmine_params = redmine_params


      @repo_root   = redmine_params["repository_root"]
      @environment = redmine_params['environment']
      @assigned_to = redmine_params['assigned_to']

      @priority    = redmine_params['priority']
      if @priority.blank?
        @priority = IssuePriority.default.id
      end

      @author = User.find_by_login(redmine_params["author"]) || User.anonymous
    end


    def error_class
      notice['error']['class'].to_s
    end

    def error_message
      notice['error']['message']
    end

    def backtrace
      @backtrace ||= notice['error']['backtrace'] rescue []
    end

    def filtered_backtrace
      @filtered_backtrace ||= filter_backtrace backtrace
    end

    def error_line
      filtered_backtrace.first
    end

    # build subject by removing method name and '[RAILS_ROOT]', make sure it
    # does not exceed 255 chars
    #
    # TODO take end of path not beginning?
    def subject
      subject = environment.present? ? "[#{environment}] " : ""
      subject << error_class
      if l = error_line
        subject << " in #{cleanup_path(l['file'])[0,(250-subject.length)]}:#{l['number']}"
      end
      subject
    end

    # build description including a link to source repository
    def description(repo_root = nil)
      "Redmine Notifier reported an Error".tap do |description|
        if l = error_line
          description << " related to source:#{repo_root}/#{cleanup_path l['file']}#L#{l['number']}"
        end
      end
    end

    def journal_text
      JournalText.format(
        error_message,
        filtered_backtrace,
        notice,
        backtrace
      )
    end

    def category
      IssueCategory.find_by_name(@redmine_params["category"]) unless @redmine_params["category"].blank?
    end

    def assignee
      if @assigned_to.present?
        User.find_by_login(@assigned_to) || Group.find_by_lastname(@assigned_to)
      end
    end

    private

    def cleanup_path(path)
      path.gsub(/\[(PROJECT|RAILS)_ROOT\]\//,'')
    end

    def filter_backtrace(backtrace)
      trace_filters = TRACE_FILTERS + @project_trace_filters
      backtrace.reject do |line|
        file = line['file'] rescue nil
        if file
          # detect.present?
          trace_filters.map do |filter|
            file.scan(filter)
          end.flatten.compact.uniq.any?
        else
          Rails.logger.error "invalid backtrace element #{line.inspect}"
          true
        end
      end
    end
  end


  class OldStyleRequest < Request
    def initialize(*args)
      super
      @notice = v2_notice_hash @notice
    end

    private

    # transforms the old-style notice structure into the hoptoad v2 data format
    def v2_notice_hash(notice)
      {
        'error' => {
          'class' => notice['error_class'],
          'message' => notice['error_message'],
          'backtrace' => parse_backtrace(notice['back'].blank? ? notice['backtrace'] : notice['back'])
        },
        'environment' => (notice['server_environment'].blank? ? notice['environment'] : notice['server_environment']),
        'session' => notice['session'],
        'request' => notice['request']
      }
    end

    def parse_backtrace(lines)
      lines.map do |line|
        if line =~ /(.+):(\d+)(:in `(.+)')?/
          { 'number' => $2.to_i, 'method' => $4, 'file' => $1 }
        else
          logger.error "could not parse backtrace line:\n#{line}"
          nil
        end
      end.compact
    end


  end
end
