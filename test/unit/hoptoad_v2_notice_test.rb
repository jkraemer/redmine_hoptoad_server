require File.expand_path('../../test_helper', __FILE__)

class HoptoadV2NoticeTest < ActiveSupport::TestCase

  test 'should parse redmine params' do
    assert params = @notice.redmine_params
    assert_equal('Exception', params['tracker'], params.inspect)
    assert_equal('staging', params['environment'])
    assert_equal(5, params['priority'])
    assert_equal('etel10000', params['project'])
    assert_equal('kTxxxxxxxxxhxxxxxxxl', params['api_key'])
    assert_equal('/serviceportal', params['repository_root'])
  end

  test 'should parse server environment' do
    assert env = @notice['server_environment']
    assert_equal('/Users/jk/code/webit/etel/serviceportal', env['project-root'])
    assert_equal('production', env['environment-name'])
    assert_equal('blender.local', env['hostname'])
  end

  test 'should parse error' do
    assert error = @notice['error']
    assert_equal('RuntimeError', error['class'])
    assert_equal('RuntimeError: pretty print me!', error['message'])
    assert backtrace = error['backtrace']
    assert backtrace.any?
    assert l = backtrace.first
    assert_equal('6', l['number'])
    assert_equal('[PROJECT_ROOT]/app/views/layouts/serviceportal.html.erb', l['file'])
    assert_equal('_run_erb_app47views47layouts47serviceportal46html46erb', l['method'])
    l = backtrace.last
    assert_equal('3', l['number'])
    assert_equal('', l['method'])
    assert_equal('script/server', l['file'])
  end

  test 'should parse request' do
    assert req = @notice['request']
    assert_equal('https://cul8er.local:3001/', req['url'])
    assert_equal('meta', req['component'])
    assert_equal('index', req['action'])
    assert params = req['params']
    assert_equal('index', params['action'])
    assert_equal('meta', params['controller'])
    assert cgi = req['cgi-data']
    assert_equal('', cgi['rack.session'])
    assert_equal('text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8', cgi['HTTP_ACCEPT'])
  end

  def setup
    @notice = HoptoadV2Notice.new v2_notice_xml
  end

end
