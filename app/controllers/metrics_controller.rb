class MetricsController < ApplicationController
  unloadable

  menu_item :metrics
  before_filter :find_project_by_project_id, :authorize
  before_filter :get_roles

  helper :cmi, :view

  def show
    begin
      @user_preference = UserPreference.find_by_user_id(User.current.id)

      @checkpoints = @project.cmi_checkpoints.find(:all,
                                                   :order => 'checkpoint_date DESC',
                                                   :limit => (2 if params[:metrics].nil?),
                                                   :include => :cmi_checkpoint_efforts)
      @metrics = @checkpoints.collect { |checkpoint| CMI::CheckpointMetrics.new checkpoint }
      @metrics.insert 0, CMI::ProjectMetrics.new(@project)
      raise CMI::Exception, I18n.t(:'cmi.no_project_info', :project => @project) if @project.cmi_project_info.nil?
      raise CMI::Exception, I18n.t(:'cmi.no_actual_start_date', :project => @project) if @project.cmi_project_info.actual_start_date.nil?
      raise CMI::Exception, I18n.t(:'cmi.cmi_no_checkpoints_found', :project => @project) if @checkpoints.empty?
      respond_to do |format|
          format.html { render :layout => !request.xhr? }
          format.js { render(:update) {|page| page.replace_html "tab-content-metrics", :partial => 'metrics/show_metrics'} }
      end
    rescue CMI::Exception => e
      flash[:error] = e.message
    end
  end

  def yearly
    @user_preference = UserPreference.find_by_user_id(User.current.id)
    
    finish_date = @project.finish_date
    start_date = @project.start_date 

    @years = (start_date.year..finish_date.year).to_a

    @checkpoints = []
    @years.each do |year|
      checkpoint = CmiCheckpoint.new
      checkpoint[:project_id] = @project.id
      checkpoint[:checkpoint_date] = ("01/01/"+year.to_s).to_time
    

      @checkpoints << checkpoint
    end

    @metrics = @checkpoints.collect { |checkpoint| CMI::CheckpointMetrics.new checkpoint }
    # Métrica para la columna 'Total'
    @metrics << CMI::ProjectMetrics.new(@project)

    
    respond_to do |format|
        format.html { render :layout => !request.xhr? }
        format.js { render(:update) {|page| page.replace_html "tab-content-metrics", :partial => 'metrics/show_yearly'} }
    end
  end

  def info
    @cmi_project_info = CmiProjectInfo.find_by_project_id @project.id
    unless @cmi_project_info
      @cmi_project_info = CmiProjectInfo.new :project_id => @project.id
    end
    if request.put? || request.post?
      @cmi_project_info.attributes = params[:cmi_project_info]
      flash[:notice] = l(:notice_successful_update) if @cmi_project_info.save
    end
  end

  def edit_preferences
    options = {'metrics' => [:cmi_metrics_effort, :cmi_metrics_time, :cmi_metrics_cost, :cmi_metrics_advance, :cmi_metrics_profitability, :cmi_metrics_income, :cmi_metrics_cashflow, :cmi_metrics_deviation, :cmi_metrics_others],
               'yearly' => [:cmi_yearly_effort, :cmi_yearly_cost, :cmi_yearly_pal]}
    user_preference = UserPreference.find_by_user_id(User.current.id)

    options[params[:preference_type]].each do |option|
      if params[:preference].present? and params[:preference].include?(option)
        user_preference[option] = params[:preference][option]
      else
        user_preference[option] = '0'
      end
    end
   
    user_preference.save

    if params[:preference_type] == 'metrics'
      redirect_to :controller => 'metrics', :action => 'show'
    else
      redirect_to :controller => 'metrics', :action => 'yearly'
    end
  end

  private

  def get_roles
    @roles = User.roles
  end
end
