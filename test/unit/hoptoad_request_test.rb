require File.expand_path('../../test_helper', __FILE__)

class HoptoadRequestTest < ActiveSupport::TestCase
  fixtures :projects, :users, :trackers, :projects_trackers, :enumerations, :issue_statuses

  test 'should have environment' do
    assert_equal 'staging', @request.environment
  end

  test 'should have error class' do
    assert_equal 'RuntimeError', @request.error_class
  end

  test 'should have error_message' do
    assert msg = @request.error_message
    assert_match(/pretty print/, msg)
  end

  test 'should have back trace' do
    assert backtrace = @request.backtrace
    assert backtrace.size > 0
  end

  test 'should have filtered back trace' do
    @request.project_trace_filters = [
      'GEM_ROOT'
    ]
    assert backtrace = @request.backtrace
    assert f_backtrace = @request.filtered_backtrace
    assert f_backtrace.size > 0
    assert f_backtrace.size < backtrace.size
  end

  test 'should compute subject' do
    assert s = @request.subject
    assert_match(/staging/, s)
    assert_match(/RuntimeError/, s)
    assert_match(/ in /, s)
  end

  test 'should compute description' do
    assert d = @request.description
    assert_match(/Redmine Notifier reported/, d)
    assert_match(/source:\//, d)
  end

  test 'should compute journal text for textile' do
    with_settings text_formatting: 'textile' do
      assert t = @request.journal_text
      assert_match(/^h4\./, t)
    end
  end

  test 'should compute journal text for markdown' do
    with_settings text_formatting: 'markdown' do
      assert t = @request.journal_text
      assert_match(/^####/, t)
    end
  end

  def setup
    @notice = HoptoadV2Notice.new v2_notice_xml
    @request = RedmineHoptoadServer::Request.new @notice
  end

end

