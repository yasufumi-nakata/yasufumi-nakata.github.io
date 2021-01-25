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

module RankingsHelper
  def ranking_title contents_type
    case contents_type
    when :entry_access
      _("Ranking of Popular Blogs (Access)")
    when :entry_comment
      _("Ranking of Popular Blogs (Comments)")
    when :entry_he
     _("Ranking of Popular Blogs (%s)") % h(_(Admin::Setting.point_button))
    when :user_access
      _("Ranking of Popular Users (Access)")
    when :user_entry
      _("Ranking of Popular Users (Blog Entries Posted)")
    when :commentator
      _("Ranking of Popular Users (Comments Posted)")
    when :received_thankyou
      _("Ranking of Received %{thankyou_label}") % {:thankyou_label => Thankyou.thankyou_label}
    else
      ""
    end
  end

  def ranking_caption contents_type
    case contents_type
    when :entry_access
      _("Most read blog / forum entries (public entries only)")
    when :entry_comment
      _("Entries most commented (public entries only)")
    when :entry_he
      _("Blog / forum entries got most %s from others (public entries only)") % h(_(Admin::Setting.point_button))
    when :user_access
      _("Users got most access to his / her entries and profile.")
    when :user_entry
      _("Users posted most blog entries (disregarding the publicity)")
    when :commentator
      _("Users made most comments (disregarding the publicity)")
    when :received_thankyou
      _("Users received most %{thankyou_label}") % {:thankyou_label => Thankyou.thankyou_label}
    else
      ""
    end
  end

  def ranking_amount_name contents_type
    case contents_type
    when :entry_access
      _("Access Count")
    when :entry_comment
      _("Comment Count")
    when :entry_he
      h(_(Admin::Setting.point_button))
    when :user_access
      _("Access Count")
    when :user_entry
      _("Blog Entry Count")
    when :commentator
      _("Comment Count")
    when :received_thankyou
      _("Received %{thankyou_label} Count") % {:thankyou_label => Thankyou.thankyou_label}
    else
      ""
    end
  end

  def show_title_col? contents_type
    ranking_data_type(contents_type).to_s == "entry"
  end

  def ranking_data_type contents_type
    case contents_type
    when :entry_access
      "entry"
    when :entry_comment
      "entry"
    when :entry_he
      "entry"
    when :user_access
      "user"
    when :user_entry
      "user"
    when  :commentator
      "user"
    else
      ""
    end
  end

  def ranking_navi_for_month(dates, select_year, select_month)
    container = dates.map do |date|
      year, month = date.split("-")
      [date, monthly_path(:year => year, :month => month)]
    end
    options_for_select(container, monthly_path(:year => select_year, :month => select_month.to_s.rjust(2,'0')))
  end

  def ranking_list_of_month(dates)
    dates.map do |date|
      year, month = date.split("-")
      [date, monthly_path(:year => year, :month => month)]
    end
  end

end
