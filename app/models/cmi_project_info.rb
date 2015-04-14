class CmiProjectInfo < ActiveRecord::Base
  unloadable

  belongs_to :project

  validates_presence_of :project

  validates_format_of :actual_start_date, :with => /^\d{4}-\d{2}-\d{2}$/, :message => :not_a_date, :allow_nil => true
  validates_format_of :scheduled_start_date, :with => /^\d{4}-\d{2}-\d{2}$/, :message => :not_a_date, :allow_nil => false
  validates_format_of :scheduled_finish_date, :with => /^\d{4}-\d{2}-\d{2}$/, :message => :not_a_date, :allow_nil => false

  validates_numericality_of :scheduled_qa_meetings, :only_integer => true
  validates_numericality_of :total_income
  validates_numericality_of :guarantee, :only_integer => true
  validates_inclusion_of :guarantee, :in => (0..24), :message => :not_in_range

  def scheduled_role_effort(role)
    effort = project.last_base_line.cmi_checkpoint_efforts.detect{ |effort| effort.role == role }
    effort.nil? ? 0.0 : effort.scheduled_effort
  end

  def scheduled_role_effort_id(role)
    effort = project.last_base_line.cmi_checkpoint_efforts.detect{ |effort| effort.role == role }
    effort.nil? ? nil : effort.id
  end

  def total_income
    factura_tracker_id = Setting.plugin_redmine_cmi['bill_tracker']
    cantidad_facturada_id = Setting.plugin_redmine_cmi['bill_amount_custom_field']

    amount = 0.0
    
    if factura_tracker_id.present? && cantidad_facturada_id.present?
      facturas = Issue.find_all_by_project_id_and_tracker_id(project.id, factura_tracker_id)
      amount = CustomValue.sum(:value, 
                               :conditions => {:custom_field_id => cantidad_facturada_id, 
                                               :customized_id => facturas.collect{|f| f.id}
                                              }
                              )
    end

    amount.to_f
  end

end
