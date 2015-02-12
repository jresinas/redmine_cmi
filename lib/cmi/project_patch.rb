require_dependency 'project'
require 'dispatcher' unless Rails::VERSION::MAJOR >= 3

module CMI
  module ProjectPatch
    def self.included(base) # :nodoc:
      base.extend(ClassMethods)
      base.send(:include, InstanceMethods)

      # Same as typing in the class
      base.class_eval do
        unloadable # Send unloadable so it will be reloaded in development

        has_one :cmi_project_info, :dependent => :destroy
        has_many :cmi_checkpoints, :dependent => :destroy
      end
    end

    module ClassMethods
      def groups
        Setting.plugin_redmine_cmi['groups'].to_s.split(/[\n\r]+/) || []
      end
    end

    module InstanceMethods
      def last_checkpoint
        cmi_checkpoints.find(:first,
                             :order => 'checkpoint_date DESC')
      end

      def effort_done_by_role(role, to_date)
        cond = [ project_condition(Setting.display_subprojects_issues?) <<
                 ' AND (role = ?)' <<
                 ' AND (spent_on <= ?)',
                 role, to_date ]
        TimeEntry.sum(:hours,
                      :include => [:project],
                      :conditions => cond)
      end

      def effort_done_by_role_yearly(role, from_date, to_date)
        cond = [ project_condition(Setting.display_subprojects_issues?) <<
                 ' AND (role = ?)' <<
                 ' AND (spent_on >= ?)' <<
                 ' AND (spent_on <= ?)',
                 role, from_date, to_date ]
        TimeEntry.sum(:hours,
                      :include => [:project],
                      :conditions => cond)
      end

      def first_checkpoint
        cmi_checkpoints.find(:first,
                             :order => 'checkpoint_date ASC')
      end

      def last_base_line(date=Date.today)
        base_line = cmi_checkpoints.find(:first,
                             :conditions => ['base_line = true AND checkpoint_date <= ?',date],
                             :order => 'checkpoint_date DESC')

        if !base_line
          base_line = first_checkpoint
        end

        base_line
      end

      def start_date
        cmi_project_info.actual_start_date.to_time
      end

      def finish_date
        cmi_checkpoints.last.scheduled_finish_date.to_time
      end
    end
  end
end
if Rails::VERSION::MAJOR >= 3
  ActionDispatch::Callbacks.to_prepare do
    # use require_dependency if you plan to utilize development mode
    Project.send(:include, CMI::ProjectPatch)
  end
else
  Dispatcher.to_prepare do
    Project.send(:include, CMI::ProjectPatch)
  end
end
