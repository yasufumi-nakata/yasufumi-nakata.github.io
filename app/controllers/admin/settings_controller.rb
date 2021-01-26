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

# config/settings.ymlの内容をいくつかのビューにわけて表示/編集するコントローラ
# 具体的には全体設定、文言設定、メール関連設定、フィード設定、その他設定の各タブの
# 表示/更新を行う。
class Admin::SettingsController < Admin::ApplicationController
  TABS = %w(main mail feed security)
  N_('Admin::SettingsController|main')
  N_('Admin::SettingsController|mail')
  N_('Admin::SettingsController|feed')
  N_('Admin::SettingsController|security')

  helper_method :current_setting

  def index
    @topics = [[s_("#{self.class.name}|#{params[:tab]}")]]
    @current_setting_hash = {}

    if params[:tab].blank? or !TABS.include?(params[:tab])
      redirect_to admin_settings_path(:tab => :main)
    end
  end

  def update_all
    @current_setting_hash = params[:settings] || {}
    objects = @current_setting_hash.dup.symbolize_keys
    settings = []
    Admin::Setting.transaction do
      settings = objects.map do |name, value|
        # remove blank values in array settings
        value.delete_if {|v| v.blank? } if value.is_a?(Array)
        if [:mypage_feed_settings].include? name
          value = {} if value.blank?
          value = value.values.delete_if { |item| (item.class == String) ? item.blank? : has_empty_value?(item.values) }
        end
        # Admin::Setting[name] = value と評価すると value の値がmapに収納されてしまうので
        Admin::Setting.[]=(name,value)
      end
      @error_messages = Admin::Setting.error_messages(settings)
      raise ActiveRecord::Rollback unless @error_messages.empty?
    end

    if @error_messages.empty?
      flash[:notice] = _('Settings were saved successfully.')
      redirect_to :action => 'index'
    else
      render :action => 'index'
    end
  end

  def ado_feed_item
    @feed_setting = {:url => '', :title => ''}
    @index =  params[:index]
    render :partial => 'feed_item'
  end

  def current_setting symbolize_key
    value = @current_setting_hash[symbolize_key] || ERB::Util.h(Admin::Setting.send(symbolize_key.to_s))
    if value == 'true'
      true
    elsif value == 'false'
      false
    else
      value
    end
  end

  private
  def has_empty_value?(array)
    array.each do |value|
      return true if value.blank?
    end
    false
  end

end
