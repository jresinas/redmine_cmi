class HistoryUserProfile < ActiveRecord::Base
  validates :created_on, :allow_nil => false, #:presence => true, 
              :format => {:with => /^\d{4}-\d{2}-\d{2}/, :message => :not_a_date }
  validates :finished_on, :allow_nil => true, 
              :format => {:with => /^\d{4}-\d{2}-\d{2}/, :message => :not_a_date }
  validate :avoid_overlapping
  validate :finished_on_after_created_on

  belongs_to :user

  before_validation :set_created_on, :if => Proc.new {|hup| hup.created_on.nil? }
  after_save :update_time_entries
  after_save :update_profile_custom_field
  after_destroy :update_time_entries
  after_destroy :update_profile_custom_field

  def avoid_overlapping
    end_date = self.finished_on.present? ? self.finished_on : DateTime.now
    errors.add(:base, l(:"activerecord.errors.messages.overlap")) if HistoryUserProfile.find(:first, :conditions => ["id != ? AND user_id = ? AND created_on <= ? AND (finished_on IS NULL OR finished_on >= ?)", self[:id] || 0, self[:user_id], end_date, self[:created_on]]) != nil
  end

  def finished_on_after_created_on
    end_date = self.finished_on.present? ? self.finished_on : DateTime.now
    errors.add(:base, l(:"activerecord.errors.messages.finish_before_create")) if self.created_on.present? and self.created_on > end_date
  end

  def set_created_on
    if self.finished_on.nil?
      end_date = Date.today
    else
      end_date = self.finished_on.to_date
    end

    hup = HistoryUserProfile.find(:first, :conditions => ["user_id = ? AND finished_on < ?", self.user_id, end_date], :order => 'finished_on DESC')

    if hup.present?
      self.created_on = hup[:finished_on] + 1.day
    end
  end

  def update_time_entries
    if !self.id_changed? and self.created_on_changed?
      start_date = [self.created_on_was, self.created_on].min
    else
      start_date = self.created_on
    end

    if self.finished_on.nil? or (self.finished_on_changed? and self.finished_on_was.nil?)
      end_date = Date.today
    elsif !self.id_changed? and self.finished_on_changed?
      end_date = [self.finished_on_was, self.finished_on].max
    else
      end_date = self.finished_on
    end

    time_entries = TimeEntry.find(:all, :conditions => ["user_id = ? AND spent_on >= ? AND spent_on <= ?", self.user_id, start_date.to_date, end_date.to_date])

  	time_entries.each do |te|
  		te.save
  	end
  end

  def update_profile_custom_field
    if self.finished_on.nil? or (self.finished_on_changed? and self.finished_on_was.nil?)
      current = HistoryUserProfile.find(:first, :conditions => ["user_id = ? AND finished_on IS NULL", self.user_id], :order => 'created_on DESC', :select => 'profile')
      
      if current.present?
        User.find(self.user_id).role=(current.profile)
      else
        User.find(self.user_id).role=(" ")
      end
    end
  end
end
