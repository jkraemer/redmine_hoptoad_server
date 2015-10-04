module RedmineHoptoadServer
  module Patches
    module IssuePatch
      def self.apply
        Issue.class_eval do
          attr_accessor :skip_notification
          prepend InstanceMethods
        end
      end

      module InstanceMethods
        def skip_notification?
          @skip_notification == true
        end

        def send_notification
          super unless skip_notification?
        end
      end
    end
  end
end

