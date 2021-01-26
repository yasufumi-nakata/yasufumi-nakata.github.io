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

class Tag < ActiveRecord::Base
  has_many :board_entries, :through => :entry_tags
  has_many :entry_tags
  has_many :chains, :through => :chain_tags
  has_many :chain_tags
  has_many :share_files, :through => :share_file_tags
  has_many :share_file_tags
  has_many :bookmark_comments, :through => :bookmark_comment_tags
  has_many :bookmark_comment_tags

  named_scope :follow_chains_by, proc { |user|
    { :conditions => ['chains.from_user_id = ?', user.id], :joins => [:chains], :group => 'tags.id' }
  }

  named_scope :against_chains_by, proc { |user|
    { :conditions => ['chains.to_user_id = ?', user.id], :joins => [:chains], :group => 'tags.id' }
  }

  named_scope :except_follow_chains_by, proc { |user|
    { :conditions => ['chains.from_user_id != ?', user.id], :joins => [:chains], :group => 'tags.id' }
  }

  named_scope :on_chains, proc {
    { :joins => [:chains] }
  }

  named_scope :entries_owned_by, proc { |owner|
    { :conditions => ['board_entries.symbol = ?', owner.symbol], :joins => [:board_entries], :group => 'tags.id' }
  }

  named_scope :share_files_owned_by, proc { |owner|
    { :conditions => ['share_files.owner_symbol = ?', owner.symbol], :joins => [:share_files], :group => 'tags.id' }
  }

  named_scope :bookmark_comments_by, proc { |user|
    { :conditions => ['bookmark_comments.user_id = ?', user.id], :joins => [:bookmark_comments], :group => 'tags.id' }
  }

  named_scope :commented_to, proc { |bookmark|
    { :conditions => ['bookmark_comments.id IN (?)', bookmark.bookmark_comments.map(&:id)], :joins => [:bookmark_comments], :group => 'tags.id'}
  }

  named_scope :order_popular, proc {
    { :group => 'tags.id', :order => 'count(tags.id) DESC' }
  }

  named_scope :order_new, proc {
    { :order => 'updated_at DESC' }
  }

  named_scope :limit, proc { |num| { :limit => num } }

  def tag
    "[#{name}]"
  end

  def self.get_standard_tags
    self.find_all_by_tag_type("STANDARD").map {|tag| tag.name }
  end

  # 文字列をタグの名前の配列に分解する
  # "[zzz][xxx][yyy]" => ["zzz", "xxx", "yyy"]
  def self.split_tags tags_as_string
    tag_as_array = []
    tags_as_string.split(/\s*\]\s*/).each do |tag_word|
      tag_as_array << tag_word.sub(/\[/, "")
    end
    tag_as_array
  end

  def self.validate_tags tags_as_string
    return [] unless tags_as_string
    errors = []
    tags_as_string.split(',').each do |tag_name|
      if tag_name.split(//u).size > 30
        errors << _("A tag can only accept 30 characters.")
      end
    end

    unless tags_as_string =~ /^(\w|\+|\/|\.|\-|\_|,|\s)*$/
      errors << _("Acceptable symbols are \"+/.-\" and \",\" (for separation of multiple tags) only. Other symbols and white spaces are not accepted.")
    end

    if tags_as_string.split(//u).size > 255
      errors << _('accepts 255 or less characters only.')
    end

    return errors
  end

  def self.create_by_comma_tags comma_tags, middle_records
    middle_records.clear
    unless comma_tags.blank?
      comma_tags.split(',').each do |tag_name|
        tag = find_by_name(tag_name.strip) || create(:name => tag_name.strip)
        middle_records.create(:tag_id => tag.id)
      end
    end
  end
end
