class HistoryUserProfileController < ApplicationController
  unloadable
  def edit
    data = params[:history_user_profile]
    hup = HistoryUserProfile.find_by_id(params[:id])

    if params[:at_present].present?
      data[:finished_on]=nil
    end

    if hup.update_attributes(data)
      flash[:notice] = l(:notice_successful_update)
    else
      error_msg = ""
      hup.errors.full_messages.each do |msg|
        if error_msg != ""
          error_msg << "<br>"
        end
        error_msg << msg
      end

      #flash[:error] = "Se ha producido un error durante la edición del perfil"
      flash[:error] = error_msg
    end

    #render :nothing => true

    redirect_to request.referrer
  end

  def new
    data = params[:history_user_profile]
#    data[:editor_id] = User.current.id

    if params['at_present']=="1"
      data['finished_on'] = nil
    end

    @history_user_profile = HistoryUserProfile.new(data)

    if @history_user_profile.save
      flash[:notice] = l(:notice_successful_create) 
    else
      error_msg = ""
      @history_user_profile.errors.full_messages.each do |msg|
        if error_msg != ""
          error_msg << "<br>"
        end
        error_msg << msg
      end

      #flash[:error] = "Se ha producido un error durante la edición del perfil"
      flash[:error] = error_msg
    end

    redirect_to request.referrer
  end

  def destroy
    hup = HistoryUserProfile.find(params[:id])

    if hup.destroy
      flash[:notice] = l(:notice_successful_delete)
    else
      error_msg = ""
      hup.errors.full_messages.each do |msg|
        if error_msg != ""
          error_msg << "<br>"
        end
        error_msg << msg
      end

      #flash[:error] = "Se ha producido un error durante la edición del perfil"
      flash[:error] = error_msg
    end

    redirect_to request.referrer
  end
end
