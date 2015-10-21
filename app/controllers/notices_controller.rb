
class NoticesController < ActionController::Base

  before_filter :parse_request, :check_enabled, :find_or_create_custom_fields

  def create_v2
    @req = RedmineHoptoadServer::Request.new @notice, @redmine_params
    create_or_update_issue
  end

  def create
    @req = RedmineHoptoadServer::OldStyleRequest.new @notice, @redmine_params
    create_or_update_issue
  end

  private

  # TODO wrap in db transaction?
  def create_or_update_issue
    # retrieve redmine objects referenced in redmine_params

    # project
    unless project = Project.find_by_identifier(@redmine_params["project"])
      msg = "could not log error, project #{@redmine_params["project"]} not found."
      Rails.logger.error msg
      render :text => msg, :status => 404 and return
    end

    # tracker
    unless tracker = project.trackers.find_by_name(@redmine_params["tracker"])
      msg = "could not log error, tracker #{@redmine_params["tracker"]} not found."
      Rails.logger.error msg
      render :text => msg, :status => 404 and return
    end

    req = RedmineHoptoadServer::Request.new @notice, @redmine_params
    req.project_trace_filters = @project.custom_value_for(@trace_filter_field).value.split(/[,\s\n\r]+/) rescue []

    repo_root = req.repo_root || (project.custom_value_for(@repository_root_field).value.gsub(/\/$/,'') rescue nil)

    subject = req.subject
    author  = req.author

    # create the issue or update an existing one
    issue = Issue.find_by_subject_and_project_id_and_tracker_id_and_author_id(subject, project.id, tracker.id, author.id)
    if issue.nil?
      # new issue
      issue = Issue.new(
        project_id: project.id,
        tracker_id: tracker.id,
        author: author,
        assigned_to: req.assignee,
        category: req.category,
        priority_id: req.priority,
        subject: subject,
        description: req.description(repo_root)
      )

      ensure_project_has_fields(project)
      ensure_tracker_has_fields(tracker)

      # set custom field error class
      issue.custom_values.build(custom_field: @error_class_field,
                                value: req.error_class)
      unless req.environment.blank?
        issue.custom_values.build(custom_field: @environment_field,
                                  value: req.environment)
      end
      issue.skip_notification = true
      issue.save!
    end

    # increment occurences custom field
    if value = issue.custom_value_for(@occurences_field)
      value.update_attribute :value, (value.value.to_i + 1).to_s
    else
      issue.custom_values.create!(:value => 1, :custom_field => @occurences_field)
    end

    # create the journal entry, update issue attributes
    retried_once = false # we retry once in case of a StaleObjectError
    begin
      issue = Issue.find issue.id # otherwise the save below resets the custom value from above. Also should reduce the chance to run into the staleobject problem.
      # create journal
      issue.init_journal author, req.journal_text

      # reopen issue if needed
      if issue.status.blank? or issue.status.is_closed?
        issue.status = IssueStatus.find(:first, :conditions => {:is_default => true}, :order => 'position ASC')
      end

      issue.save!
    rescue ActiveRecord::StaleObjectError
      if retried_once
        Rails.logger.error "airbrake server: failed to update issue #{issue.id} for the second time, giving up."
      else
        retried_once = true
        retry
      end
    end
    render :status => 200, :text => "Received bug report.\n<error-id>#{issue.id}</error-id>\n<id>#{issue.id}</id>" # newer Airbrake expects just <id>...
  end

  # before_filter, checks api key
  def check_enabled
    unless @api_key.present? and @api_key == Setting.mail_handler_api_key
      render :text => 'Access denied. Redmine API is disabled or key is invalid.', :status => 403
      false
    end
  end

  # before_filter, parses the request
  def parse_request
    if logger.debug?
      logger.debug { "hoptoad error notification:\n#{request.raw_post}" }
    end
    User.current = nil
    case params[:action]
    when 'create_v2'
      if defined?(Nokogiri)
        @notice = HoptoadV2Notice.new request.raw_post
        @redmine_params = @notice.redmine_params
      else
        # falling back to using the request body as parsed by rails.
        # this leads to sub-optimal results for request and session info.
        @notice = params[:notice]
        @notice['error']['backtrace'] = @notice['error']['backtrace']['line']
        @redmine_params = YAML.load(@notice['api_key'], :safe => true)
      end
    when 'create'
      @notice = YAML.load(request.raw_post, :safe => true)['notice']
      @redmine_params = YAML.load(@notice['api_key'], :safe => true)
    else
      raise 'unknown action'
    end
    @redmine_params = @redmine_params.inject({}) do |parameters, (k, v)|
      parameters[k.to_s.gsub(/^:/, "")] = v
      parameters
    end

    @api_key = @redmine_params["api_key"]
    true
  end

  def custom_field_for(name)
    if Rails::VERSION::MAJOR == 3
      IssueCustomField.find_or_initialize_by_name name
    else
      IssueCustomField.find_or_initialize_by name: name
    end
  end

  def project_custom_field_for(name)
    if Rails::VERSION::MAJOR == 3
      ProjectCustomField.find_or_initialize_by_name name
    else
      ProjectCustomField.find_or_initialize_by name: name
    end
  end

  # make sure the custom fields exist, and load them for further usage
  def find_or_create_custom_fields
    @error_class_field = custom_field_for 'Error class'
    if @error_class_field.new_record?
      @error_class_field.attributes = {:field_format => 'string', :searchable => true, :is_filter => true}
      @error_class_field.save(:validate => false)
    end

    @occurences_field = custom_field_for '# Occurences'
    if @occurences_field.new_record?
      @occurences_field.attributes = {:field_format => 'int', :default_value => '0', :is_filter => true}
      @occurences_field.save(:validate => false)
    end

    @environment_field = custom_field_for 'Environment'
    if @environment_field.new_record?
      @environment_field.attributes = {:field_format => 'string', :searchable => true, :is_filter => true}
      @environment_field.save(:validate => false)
    end

    @trace_filter_field = project_custom_field_for 'Backtrace filter'
    if @trace_filter_field.new_record?
      @trace_filter_field.attributes = {:field_format => 'text'}
      @trace_filter_field.save(:validate => false)
    end

    @repository_root_field = project_custom_field_for 'Repository root'
    if @repository_root_field.new_record?
      @repository_root_field.attributes = {:field_format => 'string'}
      @repository_root_field.save(:validate => false)
    end
  end

  # make sure that custom fields are associated to this project and tracker
  def ensure_tracker_has_fields(tracker)
    tracker.custom_fields << @error_class_field unless tracker.custom_fields.include?(@error_class_field)
    tracker.custom_fields << @occurences_field unless tracker.custom_fields.include?(@occurences_field)
    tracker.custom_fields << @environment_field unless tracker.custom_fields.include?(@environment_field)
  end

  # make sure that custom fields are associated to this project and tracker
  def ensure_project_has_fields(project)
    project.issue_custom_fields << @error_class_field unless project.issue_custom_fields.include?(@error_class_field)
    project.issue_custom_fields << @occurences_field unless project.issue_custom_fields.include?(@occurences_field)
    project.issue_custom_fields << @environment_field unless project.issue_custom_fields.include?(@environment_field)
  end

end
