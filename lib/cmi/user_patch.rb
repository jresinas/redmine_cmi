require 'dispatcher' unless Rails::VERSION::MAJOR >= 3

# Patches Redmine's Issue dynamically.  Adds relationships
# Issue +has_one+ to Incident and ImprovementAction
module CMI
  module UserPatch
    def self.included(base) # :nodoc:
      base.extend(ClassMethods)
      base.send(:include, InstanceMethods)

      # Same as typing in the class
      base.class_eval do
        unloadable # Send unloadable so it will be reloaded in development

        has_many :history_user_profiles, :dependent => :destroy
        after_save :update_history_user_profile
      end
    end

    module ClassMethods
      def roles
        role_field = UserCustomField.find_by_name(DEFAULT_VALUES['user_role_field'])
        role_field && role_field.possible_values.unshift(" ") || []
      end
    end

    module InstanceMethods
      def update_history_user_profile
        last_profile_status = HistoryUserProfile.find_last_by_user_id self.id
        if self.role and (last_profile_status.nil? or self.role != last_profile_status.profile)
          last_profile_status.update_attribute(:finished_on, Date.today) unless last_profile_status.nil?
          HistoryUserProfile.create(:user_id => self.id, :profile => (self.custom_field_values)[0].to_s)
        end
      end
      
      def role(date = Date.today)
        hup = HistoryUserProfile.find(:first, :conditions => ["user_id = ? AND DATE(created_on) <= ? AND (finished_on IS NULL OR finished_on >= ?)", self.id, date, date], :order => "created_on DESC", :select => :profile)
        if hup.present?
          hup.profile
        else
          ""
        end
      end

      def role=(role)
        role_field = UserCustomField.find_by_name(DEFAULT_VALUES['user_role_field'], :select => :id)
        cv = CustomValue.find_or_initialize_by_customized_type_and_custom_field_id_and_customized_id(
          'Principal',
          role_field.id,
          id)
        cv.value = role
        cv.save!
      end
    end
  end
end

if Rails::VERSION::MAJOR >= 3
  ActionDispatch::Callbacks.to_prepare do
    # use require_dependency if you plan to utilize development mode
    require_dependency 'principal'
    require_dependency 'user'
    User.send(:include, CMI::UserPatch)
  end
else
  Dispatcher.to_prepare do
    require_dependency 'principal'
    require_dependency 'user'
    User.send(:include, CMI::UserPatch)
  end
end
