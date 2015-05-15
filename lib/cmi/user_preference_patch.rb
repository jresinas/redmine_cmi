require_dependency 'user_preference'
require 'dispatcher' unless Rails::VERSION::MAJOR >= 3

# Patches Redmine's TimeEntry dinamically. Adds callbacks to save the role and
# cost added by the plugin.
module CMI
  module UserPreferencePatch
    def self.included(base) # :nodoc:
      base.extend(ClassMethods)
      base.send(:include, InstanceMethods)

      base.class_eval do
        unloadable # Send unloadable so it will be reloaded in development
      end
    end

    module ClassMethods
    end

    module InstanceMethods
      def metric_enabled(name)
        name = name.to_sym
        (self[name].present? and self[name] == "1") or (!self[name].present? and Setting.plugin_redmine_cmi[name].present?)
      end
    end
  end
end

if Rails::VERSION::MAJOR >= 3
  ActionDispatch::Callbacks.to_prepare do
    # use require_dependency if you plan to utilize development mode
    UserPreference.send(:include, CMI::UserPreferencePatch)
  end
else
  Dispatcher.to_prepare do
    UserPreference.send(:include, CMI::UserPreferencePatch)
  end
end
