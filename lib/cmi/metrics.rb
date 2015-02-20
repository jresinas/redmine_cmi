module CMI
  class Metrics
    unloadable

    attr_reader :checkpoint, :date, :project

    def year
      checkpoint.checkpoint_date.to_date.year
    end

    def effort_done
      User.roles.inject(0.0) { |sum, role| sum + effort_done_by_role(role) }
    end

    def effort_done_by_role(role)
      project.effort_done_by_role(role, date)
    end

    def effort_scheduled
      User.roles.inject(0.0) { |sum, role| sum + effort_scheduled_by_role(role) }
    end

    def effort_scheduled_by_role(role)
      if checkpoint
        checkpoint.scheduled_role_effort(role).to_f
      elsif (info = project.try :cmi_project_info)
        info.scheduled_role_effort(role).to_f
      end
    end

    def effort_remaining
      User.roles.inject(0.0) { |sum, role| sum + effort_remaining_by_role(role) }
    end

    def effort_remaining_by_role(role)
      effort_scheduled_by_role(role) - effort_done_by_role(role)
    end

    def effort_percent_done_by_role(role)
      if effort_scheduled_by_role(role).zero?
        0.0
      else
        100.0 * effort_done_by_role(role) / effort_scheduled_by_role(role)
      end
    end

    def effort_percent_done
      if  effort_scheduled.zero?
        0.0
      else
        100.0 * effort_done / effort_scheduled
      end
    end

    def effort_original_by_role(role)
      project.last_base_line(date).scheduled_role_effort(role)
    end

    def effort_original
      User.roles.inject(0.0) { |sum, role| sum + effort_original_by_role(role) }
    end

    def effort_deviation_percent
      if effort_original.zero?
        0.0
      else
        100.0 * (effort_scheduled - effort_original) / effort_original
      end
    end

    def time_done
      if !project.cmi_project_info.actual_start_date.nil?
        (date - project.cmi_project_info.actual_start_date + 1).to_i
      else
        "--"
      end
    end

    def time_percent_done
      if  time_scheduled.zero?
        0.0
      else
        100.0 * time_done / time_scheduled
      end
    end

    def time_original
      project.cmi_project_info.scheduled_finish_date - project.cmi_project_info.scheduled_start_date
    end

    def time_deviation_percent
      if  time_original.zero?
        0.0
      else
        100.0 * (time_scheduled - time_original) / time_original
      end

    end

    def hhrr_cost_incurred
      cond = [ project.project_condition(Setting.display_subprojects_issues?) <<
               ' AND (spent_on <= ?)',
               date ]
      TimeEntry.sum(:cost,
                    :joins => :project,
                    :conditions => cond)
    end

    def hhrr_cost_scheduled
      User.roles.inject(hhrr_cost_incurred) { |sum, role|
        sum += ((effort_scheduled_by_role(role) - effort_done_by_role(role)) *
                (HistoryProfilesCost.find(:first,
                                          :conditions => ['profile = ? AND year = ?', role, date.year]).try(:value) || 0.0))
      }
    end

    def hhrr_cost_original
      User.roles.inject(0) { |sum, role|
        sum += (project.cmi_project_info.scheduled_role_effort(role) *
                (HistoryProfilesCost.find(:first,
                                          :conditions => ['profile = ? AND year = ?',
                                                          role,
                                                          project.cmi_project_info.scheduled_start_date.year]
                                          ).try(:value) || 0))
      }
    end

    def hhrr_cost_remaining
      hhrr_cost_scheduled - hhrr_cost_incurred
    end

    def hhrr_cost_percent_incurred
      if hhrr_cost_scheduled.zero?
        0.0
      else
        100.0 * hhrr_cost_incurred / hhrr_cost_scheduled
      end
    end

    def hhrr_cost_percent
      if total_cost_scheduled.zero?
        0.0
      else
        100.0 * hhrr_cost_scheduled / total_cost_scheduled
      end
    end

    def material_cost_incurred
      providers_tracker_id = Setting.plugin_redmine_cmi['providers_tracker']
      invoice_id = Setting.plugin_redmine_cmi['providers_tracker_custom_field']
      paid_date_id = Setting.plugin_redmine_cmi['providers_tracker_paid_date_custom_field']
      paid_statuses = Setting.plugin_redmine_cmi['providers_paid_statuses']
      result = 0.0

      if providers_tracker_id.present? && invoice_id.present? && paid_statuses.present? && paid_date_id.present?
        paid_statuses = paid_statuses.collect(&:to_i)   
        providers = Issue.find_all_by_project_id_and_tracker_id(project.id, providers_tracker_id)

        providers.each do |provider|
          paid_date = CustomValue.find_by_custom_field_id_and_customized_id(paid_date_id, provider.id)
          if provider.status_id.in?(paid_statuses) && (paid_date.value <= date.to_s)
            result += CustomValue.find_by_custom_field_id_and_customized_id(invoice_id, provider.id).value.to_f
          end
        end
      end

      result
    end

    def material_cost_scheduled
      providers_tracker_id = Setting.plugin_redmine_cmi['providers_tracker']
      invoice_id = Setting.plugin_redmine_cmi['providers_tracker_custom_field']
      result = 0.0
      
      if providers_tracker_id.present? && invoice_id.present?
        providers = Issue.find_all_by_project_id_and_tracker_id(project.id, providers_tracker_id)

        providers.each do |provider|
          result += CustomValue.find_by_custom_field_id_and_customized_id(invoice_id, provider.id).value.to_f
        end
      end

      result
    end

    def material_cost_remaining
      material_cost_scheduled - material_cost_incurred
    end

    def material_cost_percent_incurred
      if material_cost_scheduled.zero?
        0.0
      else
        100.0 * material_cost_incurred / material_cost_scheduled
      end
    end

    def material_cost_percent
      if total_cost_scheduled.zero?
        0.0
      else
        100.0 * material_cost_scheduled / total_cost_scheduled
      end
    end

    def material_cost_original
      material_cost_scheduled
    end

    def bpo_cost_incurred
      bpo_cost_scheduled - bpo_cost_remaining
    end

    def bpo_cost_scheduled
      bpo_tracker_id = Setting.plugin_redmine_cmi['bpo_tracker']
      coste_anyo_id = Setting.plugin_redmine_cmi['bpo_tracker_custom_field']
      cost = 0

      if bpo_tracker_id.present? && coste_anyo_id.present?
        project.issues.each do |issue|
          if issue.tracker.id == bpo_tracker_id.to_i && issue.due_date.present? && issue.start_date.present?
            year_cost = CustomValue.find(:first, :conditions => ['custom_field_id = ? AND customized_id = ?', coste_anyo_id, issue.id]).value.to_i
            cost += ((issue.due_date - issue.start_date + 1) / 365) * year_cost
           end  
        end
      end

      cost
    end

    def bpo_cost_remaining
      bpo_tracker_id = Setting.plugin_redmine_cmi['bpo_tracker']
      coste_anyo_id = Setting.plugin_redmine_cmi['bpo_tracker_custom_field']
      cost = 0

      if bpo_tracker_id.present? && coste_anyo_id.present?
        project.issues.each do |issue|
          if issue.tracker.id == bpo_tracker_id.to_i && issue.due_date.present? && issue.start_date.present? && issue.start_date <= date && issue.due_date >= date
            year_cost = CustomValue.find(:first, :conditions => ['custom_field_id = ? AND customized_id = ?', coste_anyo_id, issue.id]).value.to_i
            cost += ((issue.due_date - date + 1) / 365) * year_cost
          elsif issue.tracker.id == bpo_tracker_id.to_i && issue.due_date.present? && issue.start_date.present? && issue.start_date > date && issue.due_date >= date
            year_cost = CustomValue.find(:first, :conditions => ['custom_field_id = ? AND customized_id = ?', coste_anyo_id, issue.id]).value.to_i
            cost += ((issue.due_date - issue.start_date + 1) / 365) * year_cost
          end  
        end
      end

      cost
    end

    def bpo_cost_percent_incurred
      if bpo_cost_scheduled.zero?
        0.0
      else
        100.0 * bpo_cost_incurred / bpo_cost_scheduled
      end
    end

    def bpo_cost_percent
      if total_cost_scheduled.zero?
        0.0
      else
        100.0 * bpo_cost_scheduled / total_cost_scheduled
      end
    end

    def total_cost_incurred
      hhrr_cost_incurred + material_cost_incurred + bpo_cost_incurred
    end

    def total_cost_scheduled
      hhrr_cost_scheduled + material_cost_scheduled + bpo_cost_scheduled
    end

    def total_cost_remaining
      total_cost_scheduled - total_cost_incurred
    end

    def total_cost_percent_incurred
      if total_cost_scheduled.zero?
        0.0
      else
        100.0 * total_cost_incurred / total_cost_scheduled
      end
    end

    def total_cost_original
      hhrr_cost_original + material_cost_original + bpo_cost_scheduled
    end

    def original_margin
      project.cmi_project_info.total_income - total_cost_original
    end

    def original_margin_percent
      mc = original_margin
      ti = project.cmi_project_info.total_income
      if mc == 0
        0.0
      elsif ti!=0
        100.0 * original_margin / project.cmi_project_info.total_income
      else
        "< 0.0"
      end
    end

    def scheduled_margin
      project.cmi_project_info.total_income - total_cost_scheduled
    end

    def scheduled_margin_percent
      mc = scheduled_margin
      ti = project.cmi_project_info.total_income
      if mc == 0
        0.0
      elsif ti!=0
        100.0 * scheduled_margin / project.cmi_project_info.total_income
      else
        "< 0.0"
      end
    end

    def incurred_margin
      project.cmi_project_info.total_income - total_cost_incurred
    end

    def incurred_margin_percent
      mc = incurred_margin
      ti = project.cmi_project_info.total_income
      if mc == 0
        0.0
      elsif ti!=0
        100.0 * incurred_margin / project.cmi_project_info.total_income
      else
        "< 0.0"
      end
    end

    def risk_low
      cond = [ project.project_condition(Setting.display_subprojects_issues?) <<
               ' AND (start_date <= ?)' <<
               ' AND (tracker_id = ?)' <<
               ' AND (priority_id in (?))',
               date, Setting.plugin_redmine_cmi['risks_tracker'], Setting.plugin_redmine_cmi['priority_low'] ]
      Issue.count :joins => :project, :conditions => cond
    end

    def risk_medium
      cond = [ project.project_condition(Setting.display_subprojects_issues?) <<
               ' AND (start_date <= ?)' <<
               ' AND (tracker_id = ?)' <<
               ' AND (priority_id in (?))',
               date, Setting.plugin_redmine_cmi['risks_tracker'], Setting.plugin_redmine_cmi['priority_medium'] ]
      Issue.count :joins => :project, :conditions => cond
    end

    def risk_high
      cond = [ project.project_condition(Setting.display_subprojects_issues?) <<
               ' AND (start_date <= ?)' <<
               ' AND (tracker_id = ?)' <<
               ' AND (priority_id in (?))',
               date, Setting.plugin_redmine_cmi['risks_tracker'], Setting.plugin_redmine_cmi['priority_high'] ]
      Issue.count :joins => :project, :conditions => cond
    end

    def risk_total
      cond = [ project.project_condition(Setting.display_subprojects_issues?) <<
               ' AND (start_date <= ?)' <<
               ' AND (tracker_id = ?)',
               date, Setting.plugin_redmine_cmi['risks_tracker'] ]
      Issue.count :joins => :project, :conditions => cond
    end

    def incident_low
      cond = [ project.project_condition(Setting.display_subprojects_issues?) <<
               ' AND (start_date <= ?)' <<
               ' AND (tracker_id = ?)' <<
               ' AND (priority_id in (?))',
               date, Setting.plugin_redmine_cmi['incidents_tracker'], Setting.plugin_redmine_cmi['priority_low'] ]
      Issue.count :joins => :project, :conditions => cond
    end

    def incident_medium
      cond = [ project.project_condition(Setting.display_subprojects_issues?) <<
               ' AND (start_date <= ?)' <<
               ' AND (tracker_id = ?)' <<
               ' AND (priority_id in (?))',
               date, Setting.plugin_redmine_cmi['incidents_tracker'], Setting.plugin_redmine_cmi['priority_medium'] ]
      Issue.count :joins => :project, :conditions => cond
    end

    def incident_high
      cond = [ project.project_condition(Setting.display_subprojects_issues?) <<
               ' AND (start_date <= ?)' <<
               ' AND (tracker_id = ?)' <<
               ' AND (priority_id in (?))',
               date, Setting.plugin_redmine_cmi['incidents_tracker'], Setting.plugin_redmine_cmi['priority_high'] ]
      Issue.count :joins => :project, :conditions => cond
    end

    def incident_total
      cond = [ project.project_condition(Setting.display_subprojects_issues?) <<
               ' AND (start_date <= ?)' <<
               ' AND (tracker_id = ?)',
               date, Setting.plugin_redmine_cmi['incidents_tracker'] ]
      Issue.count :joins => :project, :conditions => cond
    end

    def changes_accepted
      cond = [ project.project_condition(Setting.display_subprojects_issues?) <<
               ' AND (start_date <= ?)' <<
               ' AND (tracker_id = ?)' <<
               ' AND (status_id in (?))',
               date, Setting.plugin_redmine_cmi['changes_tracker'], Setting.plugin_redmine_cmi['status_accepted'] ]
      Issue.count :joins => :project, :conditions => cond
    end

    def changes_rejected
      cond = [ project.project_condition(Setting.display_subprojects_issues?) <<
               ' AND (start_date <= ?)' <<
               ' AND (tracker_id = ?)' <<
               ' AND (status_id in (?))',
               date, Setting.plugin_redmine_cmi['changes_tracker'], Setting.plugin_redmine_cmi['status_rejected'] ]
      Issue.count :joins => :project, :conditions => cond
    end

    def changes_effort_incurred
      cond = [ project.project_condition(Setting.display_subprojects_issues?) <<
               ' AND (start_date <= ?)' <<
               ' AND (tracker_id = ?)',
               date, Setting.plugin_redmine_cmi['changes_tracker'] ]
      TimeEntry.sum(:hours,
                    :joins => [:project, :issue ],
                    :conditions => cond)
    end

    def changes_effort_percent
      if effort_done.zero?
        0.0
      else
        100.0 * changes_effort_incurred / effort_done
      end
    end

    def held_qa_meetings_percent
      if scheduled_qa_meetings.zero?
        0.0
      else
        100.0 * held_qa_meetings / scheduled_qa_meetings
      end
    end

    def scheduled_qa_meetings
      project.cmi_project_info.scheduled_qa_meetings
    end

    def nc_total
      cond = [ project.project_condition(Setting.display_subprojects_issues?) <<
               ' AND (start_date <= ?)' <<
               ' AND (tracker_id = ?)',
               date, Setting.plugin_redmine_cmi['qa_tracker'] ]
      Issue.count :joins => :project, :conditions => cond
    end

    def nc_pending
      cond = [ project.project_condition(Setting.display_subprojects_issues?) <<
               ' AND (start_date <= ?)' <<
               ' AND (tracker_id = ?)' <<
               ' AND (status_id in (?))',
               date, Setting.plugin_redmine_cmi['qa_tracker'], Setting.plugin_redmine_cmi['status_pending'] ]
      Issue.count :joins => :project, :conditions => cond
    end

    def nc_out_of_date
      cond = [ project.project_condition(Setting.display_subprojects_issues?) <<
               ' AND (start_date <= ?)' <<
               ' AND (tracker_id = ?)' <<
               ' AND (due_date < ?)',
               date, Setting.plugin_redmine_cmi['qa_tracker'], date ]
      Issue.count :joins => :project, :conditions => cond
    end

    def nc_no_date
      cond = [ project.project_condition(Setting.display_subprojects_issues?) <<
               ' AND (start_date <= ?)' <<
               ' AND (tracker_id = ?)' <<
               ' AND (due_date IS NULL)',
               date, Setting.plugin_redmine_cmi['qa_tracker'] ]
      Issue.count :joins => :project, :conditions => cond
    end

    def qa_effort_incurred
      cond = [ project.project_condition(Setting.display_subprojects_issues?) <<
               ' AND (start_date <= ?)' <<
               ' AND (tracker_id = ?)',
               date, Setting.plugin_redmine_cmi['qa_tracker'] ]
      TimeEntry.sum(:hours,
                    :joins => [:project, :issue ],
                    :conditions => cond)
    end

    def qa_effort_percent
      if effort_done.zero?
        0.0
      else
        100.0 * qa_effort_incurred / effort_done
      end
    end

    def total_income_incurred
      bills_tracker_id = Setting.plugin_redmine_cmi['bill_tracker']
      amount_field_id = Setting.plugin_redmine_cmi['bill_amount_custom_field']
      paid_date_id = Setting.plugin_redmine_cmi['bill_tracker_paid_date_custom_field']
      paid_statuses = Setting.plugin_redmine_cmi['bill_paid_statuses']
      result = 0.0

      if bills_tracker_id.present? && amount_field_id.present? && paid_date_id.present? && paid_statuses.present?
        paid_statuses = paid_statuses.collect(&:to_i)   
        bills = Issue.find_all_by_project_id_and_tracker_id(project.id, bills_tracker_id)

        bills.each do |bill|
          paid_date = CustomValue.find_by_custom_field_id_and_customized_id(paid_date_id, bill.id)

          if bill.status_id.in?(paid_statuses) && (paid_date.value <= date.to_s)
            result += CustomValue.find_by_custom_field_id_and_customized_id(amount_field_id, bill.id).value.to_f
          end
        end
      end

      result
    end

    def total_income_scheduled
      bills_tracker_id = Setting.plugin_redmine_cmi['bill_tracker']
      amount_field_id = Setting.plugin_redmine_cmi['bill_amount_custom_field']
      paid_date_id = Setting.plugin_redmine_cmi['bill_tracker_paid_date_custom_field']
      result = 0.0

      if bills_tracker_id.present? && amount_field_id.present? && paid_date_id.present?
        bills = Issue.find_all_by_project_id_and_tracker_id(project.id, bills_tracker_id)

        bills.each do |bill|
          paid_date = CustomValue.find_by_custom_field_id_and_customized_id(paid_date_id, bill.id)

          if paid_date.value <= date.to_s
            result += CustomValue.find_by_custom_field_id_and_customized_id(amount_field_id, bill.id).value.to_f
          end
        end
      end

      result
    end

    def cashflow_current
      total_income_incurred - total_cost_incurred
    end

    def cashflow_percent
      if project.cmi_project_info.total_income.zero?
        0.0
      else
        100.0 * cashflow_current / project.cmi_project_info.total_income
      end
    end




    # Métricas para vista anual

    def effort_done_by_role_year(role, year)
      project.effort_done_by_role_yearly(role, ("01/01/"+year.to_s).to_time, [Date.today, ("31/12/"+year.to_s).to_time].min)
    end

    def effort_done_year(year)
      User.roles.inject(0.0) { |sum, role| sum + effort_done_by_role_year(role,year) }
    end

    def effort_scheduled_by_role_year(role, year)
      if year < [Date.today.year,project.finish_date.year].min
        result = effort_done_by_role_year(role, year)
      else
        if project.start_date.year < year
          total_scheduled_before = (project.start_date.year..year-1).inject(0.0){|sum, y| sum+effort_scheduled_by_role_year(role,y)}
        else
          total_scheduled_before = 0
        end
        project_effort_left = (@project.cmi_checkpoints.last.scheduled_role_effort(role).to_f - total_scheduled_before)

        if project_effort_left > effort_done_by_role_year(role, year)
          year_days_left = ([project.finish_date.to_date,("31/12/"+year.to_s).to_date].min - Date.today).to_f
          project_days_left = (project.finish_date.to_date - Date.today).to_f

          result = (year_days_left*project_effort_left)/project_days_left
        else
          result = project_effort_left
        end
      end

      result
    end

    def effort_scheduled_year(year)
      User.roles.inject(0.0) { |sum, role| sum + effort_scheduled_by_role_year(role,year) }
    end

    def effort_remaining_by_role_year(role, year)
      effort_scheduled_by_role_year(role, year) - effort_done_by_role_year(role, year)
    end

    def effort_remaining_year(year)
      User.roles.inject(0.0) { |sum, role| sum + effort_remaining_by_role_year(role,year) }
    end

    def material_cost_incurred_year(year)
      providers_tracker_id = Setting.plugin_redmine_cmi['providers_tracker']
      invoice_id = Setting.plugin_redmine_cmi['providers_tracker_custom_field']
      paid_date_id = Setting.plugin_redmine_cmi['providers_tracker_paid_date_custom_field']
      paid_statuses = Setting.plugin_redmine_cmi['providers_paid_statuses']
      result = 0.0

      if providers_tracker_id.present? && invoice_id.present? && paid_statuses.present? && paid_date_id.present?
        paid_statuses = paid_statuses.collect(&:to_i)   
        providers = Issue.find_all_by_project_id_and_tracker_id(project.id, providers_tracker_id)

        providers.each do |provider|
          paid_date = CustomValue.find_by_custom_field_id_and_customized_id(paid_date_id, provider.id)
          if provider.status_id.in?(paid_statuses) && (paid_date.value.to_date >= ("01/01/"+year.to_s).to_date) && (paid_date.value.to_date <= [("31/12/"+year.to_s).to_date, Date.today].min)
            result += CustomValue.find_by_custom_field_id_and_customized_id(invoice_id, provider.id).value.to_f
          end
        end
      end

      result
    end

    def material_cost_scheduled_year(year)
      providers_tracker_id = Setting.plugin_redmine_cmi['providers_tracker']
      invoice_id = Setting.plugin_redmine_cmi['providers_tracker_custom_field']
      paid_date_id = Setting.plugin_redmine_cmi['providers_tracker_paid_date_custom_field']

      result = 0.0
      
      if providers_tracker_id.present? && invoice_id.present?
        providers = Issue.find_all_by_project_id_and_tracker_id(project.id, providers_tracker_id)

        providers.each do |provider|
          paid_date = CustomValue.find_by_custom_field_id_and_customized_id(paid_date_id, provider.id)

          if paid_date.value.to_date.year == year
            result += CustomValue.find_by_custom_field_id_and_customized_id(invoice_id, provider.id).value.to_f
          end
        end
      end

      result
    end

    def material_cost_remaining_year(year)
      material_cost_scheduled_year(year) - material_cost_incurred_year(year)
    end

    def bpo_cost_incurred_year(year)
      bpo_tracker_id = Setting.plugin_redmine_cmi['bpo_tracker']
      coste_anyo_id = Setting.plugin_redmine_cmi['bpo_tracker_custom_field']
      cost = 0

      if bpo_tracker_id.present? && coste_anyo_id.present?
        project.issues.each do |issue|
          if issue.tracker.id == bpo_tracker_id.to_i && issue.due_date.present? && issue.start_date.present? && issue.start_date.to_date <= Date.today && issue.due_date.to_date.year >= year && issue.start_date.to_date.year <= year
            year_cost = CustomValue.find(:first, :conditions => ['custom_field_id = ? AND customized_id = ?', coste_anyo_id, issue.id]).value.to_f
            cost += (([issue.due_date.to_date,Date.today].min - [issue.start_date.to_date,("01/01/"+year.to_s).to_date].max + 1) / 365) * year_cost
          end
        end
      end

      cost
    end

    def bpo_cost_scheduled_year(year)
      bpo_tracker_id = Setting.plugin_redmine_cmi['bpo_tracker']
      coste_anyo_id = Setting.plugin_redmine_cmi['bpo_tracker_custom_field']
      cost = 0

      if bpo_tracker_id.present? && coste_anyo_id.present?
        project.issues.each do |issue|
          if issue.tracker.id == bpo_tracker_id.to_i && issue.due_date.present? && issue.start_date.present? && issue.start_date.to_date.year <= year && issue.due_date.to_date.year >= year
            year_cost = CustomValue.find(:first, :conditions => ['custom_field_id = ? AND customized_id = ?', coste_anyo_id, issue.id]).value.to_f
            cost += (([issue.due_date.to_date,("31/12/"+year.to_s).to_date].min - [issue.start_date.to_date,("01/01/"+year.to_s).to_date].max + 1) / 365) * year_cost
           end  
        end
      end

      cost
    end

    def bpo_cost_remaining_year(year)
      bpo_cost_scheduled_year(year) - bpo_cost_incurred_year(year)
    end

    def hhrr_cost_incurred_year(year)
      cond = [ project.project_condition(Setting.display_subprojects_issues?) <<
               ' AND (spent_on >= ?)' <<
               ' AND (spent_on <= ?)',
               ("01/01/"+year.to_s).to_date, ("31/12/"+year.to_s).to_date ]
      TimeEntry.sum(:cost,
                    :joins => :project,
                    :conditions => cond)
    end

    def hhrr_cost_scheduled_year(year)
      User.roles.inject(hhrr_cost_incurred_year(year)) { |sum, role|
        sum += ((effort_scheduled_by_role_year(role,year) - effort_done_by_role_year(role,year)) *
                (HistoryProfilesCost.find(:first,
                                          :conditions => ['profile = ? AND year <= ?', role, date.year],
                                          :order => 'year DESC').try(:value) || 0.0))
      }
    end

    def hhrr_cost_remaining_year(year)
      hhrr_cost_scheduled_year(year) - hhrr_cost_incurred_year(year)
    end

    def total_cost_incurred_year(year)
      hhrr_cost_incurred_year(year) + material_cost_incurred_year(year) + bpo_cost_incurred_year(year)
    end

    def total_cost_scheduled_year(year)
      hhrr_cost_scheduled_year(year) + material_cost_scheduled_year(year) + bpo_cost_scheduled_year(year)
    end

    def total_cost_remaining_year(year)
      total_cost_scheduled_year(year) - total_cost_incurred_year(year)
    end


    def hhrr_cost_percent_incurred_year(year)
      if hhrr_cost_scheduled_year(year).zero?
        0.0
      else
        100.0 * hhrr_cost_incurred_year(year) / hhrr_cost_scheduled_year(year)
      end
    end

    def material_cost_percent_incurred_year(year)
      if material_cost_scheduled_year(year).zero?
        0.0
      else
        100.0 * material_cost_incurred_year(year) / material_cost_scheduled_year(year)
      end
    end

    def bpo_cost_percent_incurred_year(year)
      if bpo_cost_scheduled_year(year).zero?
        0.0
      else
        100.0 * bpo_cost_incurred_year(year) / bpo_cost_scheduled_year(year)
      end
    end

    def total_cost_percent_incurred_year(year)
      if total_cost_scheduled_year(year).zero?
        0.0
      else
        100.0 * total_cost_incurred_year(year) / total_cost_scheduled_year(year)
      end
    end


    def hhrr_cost_percent_year(year)
      if total_cost_scheduled_year(year).zero?
        0.0
      else
        100.0 * hhrr_cost_scheduled_year(year) / total_cost_scheduled_year(year)
      end
    end

    def material_cost_percent_year(year)
      if total_cost_scheduled_year(year).zero?
        0.0
      else
        100.0 * material_cost_scheduled_year(year) / total_cost_scheduled_year(year)
      end
    end

    def bpo_cost_percent_year(year)
      if total_cost_scheduled_year(year).zero?
        0.0
      else
        100.0 * bpo_cost_scheduled_year(year) / total_cost_scheduled_year(year)
      end
    end


    def scheduled_margin_year(year)
      project.cmi_project_info.total_income_year(year) - total_cost_scheduled_year(year)
    end

    def scheduled_margin_percent_year(year)
      mc = scheduled_margin_year(year)
      ti = project.cmi_project_info.total_income_year(year)
      if mc == 0
        0.0
      elsif ti!=0
        100.0 * scheduled_margin_year(year) / project.cmi_project_info.total_income_year(year)
      else
        "< 0.0"
      end
    end
  end
end
