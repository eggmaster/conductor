#
# Copyright (C) 2009 Red Hat, Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA  02110-1301, USA.  A copy of the GNU General Public License is
# also available at http://www.gnu.org/copyleft/gpl.html.

# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class UserSessionsController < ApplicationController
  before_filter :require_no_user, :only => [:new, :create]
  before_filter :require_user, :only => :destroy
  layout 'login'

  def new
    @user_session = UserSession.new
  end

  def create
    authenticate!
    session[:javascript_enabled] = request.xhr?
    respond_to do |format|
      format.html do
        flash[:notice] = "Login successful!"
        redirect_back_or_default root_url
      end
      format.js { render :status => 201, :text => root_url }
    end
  end

  def unauthenticated
    Rails.logger.warn "Request is unauthenticated for #{request.remote_ip}"

    respond_to do |format|
      format.html do
        @user_session = UserSession.new(params[:user_session])
        flash[:warning] = "Login failed: The Username and Password you entered do not match"
        render :action => :new
      end
      format.js { render :status=> 401, :text => "Login failed: The Username and Password you entered do not match" }
    end

    return false
  end

  def destroy
    clear_breadcrumbs
    logout
    flash[:notice] = "Logout successful!"
    redirect_back_or_default login_url
  end
end
