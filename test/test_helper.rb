# Load the normal Rails helper
require File.expand_path File.dirname(__FILE__) + '/../../../test/test_helper'

class ActiveSupport::TestCase
  def v2_notice_xml
    IO.read File.join File.dirname(__FILE__), 'fixtures', 'v2_message.xml'
  end
end

class ActionController::TestCase

  def raw_post(action, params, body = '')
    @request.env['RAW_POST_DATA'] = body
    response = post(action, params)
    @request.env.delete('RAW_POST_DATA')
    response
  end

end
