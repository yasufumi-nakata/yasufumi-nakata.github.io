# SKIP(Social Knowledge & Innovation Platform)
# Copyright (C) 2008-2010 TIS Inc.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

class GroupsController < ApplicationController
  before_filter :setup_layout, :except => %w(new create)

  verify :method => :post, :only => [ :create ],
          :redirect_to => { :action => :index }

  # tab_menu
  # グループの一覧表示
  def index
    params[:yet_participation] ||= "true"

    scope = Group.active.partial_match_name_or_description(params[:keyword]).
      categorized(params[:group_category_id]).order_active
    scope = scope.unjoin(current_user) if params[:yet_participation] == 'true'
    # paginteの検索条件にgroup byが含まれる場合、countでgroup by が考慮されないので
    @groups = scope.paginate(:count => {:select => 'distinct(groups.id)'}, :page => params[:page], :per_page => 50)

    flash.now[:notice] = _('No matching groups found.') if @groups.empty?
  end

  # tab_menu
  # グループの新規作成画面の表示
  def new
    @main_menu = @title = _('Create a new %{group}') % {:group => name_of_group}
    @group = Group.new(:default_publication_type => 'public', :default_stock_entry => 'true')
    @group_categories = GroupCategory.all
  end

  # post_action
  # グループの新規作成の処理
  def create
    @main_menu = @title = _('Create a new %{group}') % {:group => name_of_group}
    @group = Group.new(params[:group])
    @group_categories = GroupCategory.all
    @group.group_participations.build(:user_id => session[:user_id], :owned => true)

    if Admin::Setting.generate_gid_auto
      @group.gid = Time.now.strftime("%y%m%d%H%M%S")
    end

    if @group.save
      current_user.notices.create!(:target => @group)

      flash[:notice] = _('%{group} was created successfully.') % {:group => name_of_group}
      redirect_to :controller => 'group', :action => 'show', :gid => @group.gid
    else
      flash[:error] = _("Please re-create the group again.")
      render :action => 'new'
    end
  end

private
  def setup_layout
    @main_menu = @title = name_of_group
  end
end
