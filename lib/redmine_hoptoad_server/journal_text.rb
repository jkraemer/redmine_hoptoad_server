module RedmineHoptoadServer
  module JournalText

    def self.format(*args)
      case Setting.text_formatting
      when 'textile'
        Textile.new *args
      when 'markdown'
        Markdown.new *args
      else
        fail 'unknown text formatting'+Setting.text_formatting
      end.text
    end

    class Formatter
      def initialize(error_message, filtered_backtrace, notice, backtrace)
        @error_message = error_message
        @filtered_backtrace = filtered_backtrace
        @notice = notice
        @backtrace = backtrace
      end

      def format_hash(hash)
        PP.pp hash, ""
      end

      def format_backtrace(lines)
        lines.map{ |line| "#{line['file']}:#{line['number']}#{":in #{line['method']}" if line['method']}" }.join("\n")
      end
    end

    class Textile < Formatter
      def text
        "h4. Error message\n\n<pre>#{@error_message}</pre>".tap do |text|
          text << "\n\nh4. Filtered backtrace\n\n<pre>#{format_backtrace(@filtered_backtrace)}</pre>" unless @filtered_backtrace.blank?
          text << "\n\nh4. Request\n\n<pre>#{format_hash @notice['request']}</pre>" unless @notice['request'].blank?
          text << "\n\nh4. Session\n\n<pre>#{format_hash @notice['session']}</pre>" unless @notice['session'].blank?
          unless (env = (@notice['server_environment'] || @notice['environment'])).blank?
            text << "\n\nh4. Environment\n\n<pre>#{format_hash env}</pre>"
          end
          text << "\n\nh4. Full backtrace\n\n<pre>#{format_backtrace @backtrace}</pre>" unless @backtrace.blank?
        end
      end
    end

    class Markdown < Formatter
      # TODO indent pre blocks instead
      def text
        "#### Error message\n\n#{indent @error_message}\n".tap do |text|
          text << "\n\n#### Filtered backtrace\n\n#{indent format_backtrace @filtered_backtrace }\n" unless @filtered_backtrace.blank?
          text << "\n\n#### Request\n\n#{indent format_hash @notice['request']}\n" unless @notice['request'].blank?
          text << "\n\n#### Session\n\n#{indent format_hash @notice['session']}\n" unless @notice['session'].blank?
          unless (env = (@notice['server_environment'] || @notice['environment'])).blank?
            text << "\n\n#### Environment\n\n#{indent format_hash env}\n"
          end
          text << "\n\n#### Full backtrace\n\n#{indent format_backtrace @backtrace}\n" unless @backtrace.blank?
        end
      end

      private

      def indent(string)
        string.lines.map{|s|s.prepend "    "}.join
      end
    end

  end
end
