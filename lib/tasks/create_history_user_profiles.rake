desc 'Create initial history user profiles'

task :create_history_user_profiles, [:init_date] => :environment do |t, args|
	User.all.each do |user|
		if user.role.present?
			last_hup = user.history_user_profiles.sort_by{|hup| hup.finished_on.to_s}.last
			if last_hup.nil? or (last_hup.present? and last_hup.finished_on.present? and last_hup.finished_on < args[:init_date].to_date)
				HistoryUserProfile.create(user_id: user.id, profile: user.role, created_on: args[:init_date].to_date, finished_on: nil)
			end
		end
	end
end