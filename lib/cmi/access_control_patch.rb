require 'dispatcher' unless Rails::VERSION::MAJOR >= 3

module CMI
  module AccessControlPatch
    def self.included(base) # :nodoc:
      base.extend(ClassMethods)

      # Same as typing in the class
      base.class_eval do
      	class << self
        	alias_method_chain :read_action?, :cmi
    	end
      end
      base.send(:include, InstanceMethods)
    end

    module ClassMethods
    	# Add cmi read actions for show metrics when project are closed
    	def read_action_with_cmi?(action)
			cmi_read_actions = ["metrics/show", "metrics/yearly"]
	        if !action.is_a?(Symbol) and cmi_read_actions.include?("#{action[:controller]}/#{action[:action]}")
	          return true
	        end

	        read_action_without_cmi?(action)
    	end 
    end

    module InstanceMethods
	    
    end
  end
end

if Rails::VERSION::MAJOR >= 3
  ActionDispatch::Callbacks.to_prepare do
    # use require_dependency if you plan to utilize development mode
    require_dependency 'redmine/access_control'
    Redmine::AccessControl.send(:include, CMI::AccessControlPatch)
  end
else
  Dispatcher.to_prepare do
    require_dependency 'redmine/access_control'
    Redmine::AccessControl.send(:include, CMI::AccessControlPatch)
  end
end