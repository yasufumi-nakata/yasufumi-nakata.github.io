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

require 'jcode'
require 'open-uri'
require "resolv-replace"
require 'timeout'
require 'feed-normalizer'
class MypageController < ApplicationController
  before_filter :setup_layout
  before_filter :load_user
  skip_before_filter :verify_authenticity_token, :only => :apply_ident_url

  verify :method => :post,
    :only => [ :update_profile, :update_message_unsubscribes, :apply_password, :change_read_state, :apply_email],
    :redirect_to => { :action => :index }
  verify :method => [:post, :put], :only => [ :update_customize], :redirect_to => { :action => :index }

  helper_method :recent_day

  # ================================================================================
  #  tab menu actions
  # ================================================================================

  # mypage > home
  def index
    # ============================================================
    #  right side area
    # ============================================================
    @year, @month, @day = parse_date
    @recent_groups =  Group.active.recent(recent_day).order_recent.limit(5)
    @recent_users = User.recent(recent_day).order_recent.limit(5) - [current_user]

    # ============================================================
    #  main area top messages
    # ============================================================
    # あなたへのお知らせ(未読のもののみ)
    @mail_your_messages = mail_your_messages

    # ============================================================
    #  main area entries
    # ============================================================
    @questions = find_questions_as_locals({:recent_day => recent_day})

    # 複数tableのカラムを伴うソートをするため非常に重くなる(実行計画ではUsing temporary)のでキャッシュ(1回/h)
    @today_popular_blogs_cache_key = "today_popular_blog_#{Time.now.strftime('%Y%m%d%H')}"
    if SkipEmbedded::InitialSettings['mypage'] && SkipEmbedded::InitialSettings['mypage']['show_today_popular_blogs_box']
      unless read_fragment(@today_popular_blogs_cache_key)
        expire_fragment_without_locale("today_popular_blog_#{Time.now.ago(1.hour).strftime('%Y%m%d%H')}") # 古いcacheの除去
        @today_popular_blogs = BoardEntry.publication_type_eq('public').scoped(
          :conditions => "board_entry_points.today_access_count > 0",
          :order => "board_entry_points.today_access_count DESC, board_entry_points.access_count DESC, board_entries.last_updated DESC, board_entries.id DESC",
          :include => [ :user, :state ]
        ).timeline.recent(recent_day.day).limit(10)
      end
    end

    @recent_popular_blogs_cache_key = "recent_popular_blog_#{Time.now.strftime('%Y%m%d%H')}"
    if SkipEmbedded::InitialSettings['mypage'] && SkipEmbedded::InitialSettings['mypage']['show_recent_popular_blogs_box']
      unless read_fragment(@recent_popular_blogs_cache_key)
        expire_fragment_without_locale("recent_popular_blog_#{Time.now.ago(1.hour).strftime('%Y%m%d%H')}") # 古いcacheの除去
        @recent_popular_blogs = BoardEntry.publication_type_eq('public').scoped(
          :order => "board_entry_points.access_count DESC, board_entries.last_updated DESC, board_entries.id DESC",
          :include => [ :user, :state ]
        ).timeline.recent(recent_day.day).limit(10)
      end
    end

    @recent_blogs = find_recent_blogs_as_locals({:per_page => per_page})
    @timelines = find_timelines_as_locals({:per_page => per_page}) if current_user.custom.display_entries_format == 'tabs'
    @recent_bbs = recent_bbs

    # ============================================================
    #  main area bookmarks
    # ============================================================
    @bookmarks = Bookmark.publicated.recent(10).order_new.limit(5)
  end

  # mypage > profile
  def profile
    flash.keep(:notice)
    redirect_to get_url_hash('show')
  end

  # mypage > blog
  def blog
    redirect_to get_url_hash('blog', :archive => 'all', :sort_type => 'date')
  end

  # mypage > file
  def share_file
    redirect_to get_url_hash('share_file')
  end

  # mypage > social
  def social
    redirect_to get_url_hash('social')
  end

  # mypage > group
  def group
    redirect_to get_url_hash('group')
  end

  # mypage > bookmark
  def bookmark
    redirect_to get_url_hash('bookmark')
  end

  # mypage > trace(足跡)
  def trace
    @access_count = current_user.user_access.access_count
    @access_tracks = current_user.tracks
  end

  # mypage > manage(管理)
  def manage
    @title = _("Self Admin")
    @user = current_user
    @menu = params[:menu] || "manage_profile"
    case @menu
    when "manage_profile"
      @profiles = current_user.user_profile_values
    when "manage_password"
      redirect_to_with_deny_auth(:action => :manage) and return unless login_mode?(:password)
    when "manage_email"
      @applied_email = AppliedEmail.find_by_user_id(session[:user_id]) || AppliedEmail.new
    when "manage_openid"
      redirect_to_with_deny_auth(:action => :manage) and return unless login_mode?(:free_rp)
      @openid_identifier = @user.openid_identifiers.first || OpenidIdentifier.new
    when "manage_portrait"
      @picture = current_user.picture || current_user.build_picture
      render :template => 'pictures/new', :layout => 'layout' and return
    when "manage_message"
      @unsubscribes = UserMessageUnsubscribe.get_unscribe_array(session[:user_id])
    else
      render_404 and return
    end
    render :partial => @menu, :layout => "layout"
  end

  # ================================================================================
  #  mypage > home 関連
  # ================================================================================

  # 公開されている記事一覧画面を表示
  def entries
    unless params[:list_type]
      redirect_to :controller => 'search', :action => 'entry_search' and return
    end
    unless valid_list_types.include?(params[:list_type])
      render_404 and return
    end
    locals = find_as_locals(params[:list_type], {:per_page => 20})
    @id_name = locals[:id_name]
    @title_icon = locals[:title_icon]
    @title_name = locals[:title_name]
    @entries = locals[:pages]
    @symbol2name_hash = locals[:symbol2name_hash]
  end

  # 指定日の投稿記事一覧画面を表示
  def entries_by_date
    year, month, day = parse_date
    @selected_day = Date.new(year, month, day)
    @entries = find_entries_at_specified_date(@selected_day)
    @next_day = first_entry_day_after_specified_date(@selected_day)
    @prev_day = last_entry_day_before_specified_date(@selected_day)
  end

  # アンテナ毎の記事一覧画面を表示
  def entries_by_antenna
    @antenna_entry = antenna_entry(params[:target_type], params[:target_id], params[:read])
    @antenna_entry.title = antenna_entry_title(@antenna_entry)
    if @antenna_entry.need_search?
      @entries = @antenna_entry.scope.order_new.paginate(:page => params[:page], :per_page => 20)
      @user_unreadings = unread_entry_id_hash_with_user_reading(@entries.map {|entry| entry.id}, params[:target_type])
      @symbol2name_hash = BoardEntry.get_symbol2name_hash(@entries)
    end
  end

  # ajax_action
  # 未読・既読を変更する
  def change_read_state
    ur = UserReading.create_or_update(session[:user_id], params[:board_entry_id], params[:read])
    render :text => ur.read? ? _('Entry was successfully marked read.') : _('Entry was successfully marked unread.')
  end

  # ajax_action
  # [公開された記事]のページ切り替えを行う。
  # param[:target]で指定した内容をページ単位表示する
  def load_entries
    option = { :per_page => per_page }
    option[:recent_day] = params[:recent_day].to_i if params[:recent_day]
    save_current_page_to_cookie
    render :partial => params[:page_name], :locals => find_as_locals(params[:target], option)
  end

  # ajax_action
  # 右側サイドバーのRSSフィードを読み込む
  def load_rss_feed
    render :partial => "rss_feed", :locals => { :feeds => unifed_feeds }
  rescue Timeout::Error
    render :text => _("Timeout while loading rss.")
    return false
  rescue Exception => e
    logger.error e
    e.backtrace.each { |line| logger.error line}
    render :text => _("Failed to load rss.")
    return false
  end

  # ================================================================================
  #  mypage > manage(管理) 関連
  # ================================================================================

  # post_action
  def update_profile
    @user = current_user
    @user.attributes = params[:user]
    @profiles = @user.find_or_initialize_profiles(params[:profile_value])

    User.transaction do
      @user.save!
      @profiles.each{|profile| profile.save!}
    end
    flash[:notice] = _('User information was successfully updated.')
    redirect_to :action => 'profile'
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
    @error_msg = []
    @error_msg.concat @user.errors.full_messages unless @user.valid?
    @error_msg.concat SkipUtil.full_error_messages(@profiles)

    render :partial => 'manage_profile', :layout => "layout"
  end

  # post_action
  # メール通知設定
  # 画面表示とテーブルレコードが逆なので注意
  # SystemMessage::MESSAGE_TYPESにあるけど、params["message_type"]にないときにcreate
  def update_message_unsubscribes
    UserMessageUnsubscribe.delete_all(["user_id = ?", session[:user_id]])
    SystemMessage::MESSAGE_TYPES.each do |message_type|
      unless  params["message_type"] && params["message_type"][message_type]
        UserMessageUnsubscribe.create(:user_id => session[:user_id], :message_type => message_type )
      end
    end
    flash[:notice] = _('Updated notification email settings.')
    redirect_to :action => 'manage', :menu => 'manage_message'
  end

  def apply_password
    redirect_to_with_deny_auth(:action => :manage) and return unless login_mode?(:password)

    @user = current_user
    @user.change_password(params[:user])
    if @user.errors.empty?
      flash[:notice] = _('Password was successfully updated.')
      redirect_to :action => :manage, :menu => :manage_password
    else
      @menu = 'manage_password'
      render :partial => 'manage_password', :layout => 'layout'
    end
  end

  def apply_email
    if @applied_email = AppliedEmail.find_by_user_id(session[:user_id])
      @applied_email.email = params[:applied_email][:email]
    else
      @applied_email = AppliedEmail.new(params[:applied_email])
      @applied_email.user_id = session[:user_id]
    end

    if @applied_email.save
      UserMailer::Smtp.deliver_sent_apply_email_confirm(@applied_email.email, "#{root_url}mypage/update_email/#{@applied_email.onetime_code}/")
      flash.now[:notice] = _("Your request of changing email address accepted. Check your email to complete the process.")
    else
      flash.now[:warn] = _("Failed to process your request. Try resubmitting your request again.")
    end
    @menu = 'manage_email'
    @user = current_user
    render :partial => 'manage_email', :layout => "layout"
  end

  def update_email
    if @applied_email = AppliedEmail.find_by_user_id_and_onetime_code(session[:user_id], params[:id])
      @user = current_user
      old_email = @user.email
      @user.email = @applied_email.email
      if @user.save
        @applied_email.destroy
        flash[:notice] = _("Email address was updated successfully.")
        redirect_to :action => 'profile'
      else
        @user.email = old_email
        @menu = 'manage_email'
        flash[:notice] = _("The specified email address has already been registered. Try resubmitting the request with another address.")
        render :partial => 'manage_email', :layout => "layout"
      end
    else
      flash[:notice] = _('Specified page not found.')
      redirect_to :action => 'index'
    end
  end

  def apply_ident_url
    redirect_to_with_deny_auth(:action => :manage) and return unless login_mode?(:free_rp)
    @openid_identifier = current_user.openid_identifiers.first || current_user.openid_identifiers.build
    if using_open_id?
      begin
        authenticate_with_open_id do |result, identity_url|
          if result.successful?
            @openid_identifier.url = identity_url
            if @openid_identifier.save
              flash[:notice] = _('OpenID URL was successfully set.')
              redirect_to :action => :manage, :menu => :manage_openid
              return
            else
              render :partial => 'manage_openid', :layout => 'layout'
            end
          else
            flash.now[:error] = _("OpenId process is cancelled or failed.")
            render :partial => 'manage_openid', :layout => 'layout'
          end
        end
      rescue OpenIdAuthentication::InvalidOpenId
        flash.now[:error] = _("Invalid OpenID URL format.")
        render :partial => 'manage_openid', :layout => 'layout'
      end
    else
      flash.now[:error] = _("Please input OpenID URL.")
      render :partial => 'manage_openid', :layout => 'layout'
    end
  end

  # POST or PUT action
  def update_customize
    @user_custom = current_user.custom
    if @user_custom.update_attributes(params[:user_custom])
      setup_custom_cookies(@user_custom)
      flash[:notice] = _('Updated successfully.')
    end
    redirect_to root_path
  end

  # [最近]を表す日数
  def recent_day
    10
  end

  private
  def per_page
    current_user.custom.display_entries_format == 'tabs' ? Admin::Setting.entry_showed_tab_limit_per_page : 8
  end

  def setup_layout
    @main_menu = @title = _('My Page')
  end

  # 日付情報を解析して返す。
  def parse_date
    year = params[:year] ? params[:year].to_i : Time.now.year
    month = params[:month] ? params[:month].to_i : Time.now.month
    day = params[:day] ? params[:day].to_i : Time.now.day
    unless Date.valid_date?(year, month, day)
      year, month, day = Time.now.year, Time.now.month, Time.now.day
    end
    return year, month, day
  end

  def antenna_entry(key, target_id = nil, read = true)
    unless key.blank?
      if target_id
        if %w(user group).include?(key)
          UserAntennaEntry.new(current_user, key, target_id, read)
        else
          raise ActiveRecord::RecordNotFound
        end
      else
        if %w(message comment bookmark joined_group).include?(key)
          SystemAntennaEntry.new(current_user, key, read)
        else
          raise ActiveRecord::RecordNotFound
        end
      end
    else
      AntennaEntry.new(current_user, read)
    end
  end

  class AntennaEntry
    attr_reader :key, :antenna
    attr_accessor :title

    def initialize(current_user, read = true)
      @read = read
      @current_user = current_user
    end

    def scope
      scope = BoardEntry.accessible(@current_user)
      scope = scope.unread(@current_user) unless @read
      scope
    end

    def need_search?
      true
    end
  end

  class SystemAntennaEntry < AntennaEntry
    def initialize(current_user, key, read = true)
      @current_user = current_user
      @key = key
      @read = read
    end

    def scope
      scope = case
              when @key == 'message'  then BoardEntry.accessible(@current_user).notice
              when @key == 'comment'  then BoardEntry.accessible(@current_user).commented(@current_user)
              when @key == 'bookmark' then scope_for_entries_by_system_antenna_bookmark
              when @key == 'joined_group'    then scope_for_entries_by_system_antenna_group
              end

      unless @read
        if @key == 'message'
          scope = scope.unread_only_notice(@current_user)
        else
          scope = scope.unread(@current_user)
        end
      end
      scope
    end

    def need_search?
      !(@key == 'group' && @current_user.group_symbols.size == 0)
    end

    private
    # #TODO BoardEntryに移動する
    # システムアンテナ[bookmark]の記事を取得するための検索条件
    def scope_for_entries_by_system_antenna_bookmark
      bookmarks = Bookmark.find(:all,
                                :conditions => ["bookmark_comments.user_id = ? and bookmarks.url like '/page/%'", @current_user.id],
                                :include => [:bookmark_comments])
      ids = []
      bookmarks.each do |bookmark|
        ids << bookmark.url.gsub(/\/page\//, "")
      end

      BoardEntry.accessible(@current_user).scoped(
        :conditions => ['board_entries.id IN (?)', ids]
      )
    end

    # #TODO BoardEntryに移動する
    # システムアンテナ[group]の記事を取得するための検索条件
    def scope_for_entries_by_system_antenna_group
      find_params = BoardEntry.make_conditions @current_user.belong_symbols, { :symbols => @current_user.group_symbols }
      BoardEntry.scoped(
        :conditions=> find_params[:conditions],
        :include => find_params[:include]
      )
    end
  end

  class UserAntennaEntry < AntennaEntry
    def initialize(current_user, type, id, read = true)
      @current_user = current_user
      @type = type
      @read = read
      @owner = type.humanize.constantize.find id
      @title = @owner.name
    end

    def scope
      scope = BoardEntry.accessible(@current_user).owned(@owner)
      scope = scope.unread(@current_user) unless @read
      scope
    end

    def need_search?
      true
    end
  end

  # TODO BoardEntryに移動する
  def mail_your_messages
    {
      :id_name => 'message',
      :title_icon => "email",
      :title_name => _("Notices for you"),
      :pages => pages = BoardEntry.from_recents.accessible(current_user).notice.unread_only_notice(current_user).order_new,
      :symbol2name_hash => BoardEntry.get_symbol2name_hash(pages)
    }
  end

  def find_as_locals target, options
    group_categories = GroupCategory.all.map{ |gc| gc.code.downcase }
    case
    when target == 'questions'             then find_questions_as_locals options
    when target == 'recent_blogs'          then find_recent_blogs_as_locals options
    when target == 'timelines'             then find_timelines_as_locals options
    when group_categories.include?(target) then find_recent_bbs_as_locals target, options
# TODO 例外出すなどの対応をしないとアプリケーションエラーになってしまう。
#    else
    end
  end

  # 質問記事一覧を取得する（partial用のオプションを返す）
  def find_questions_as_locals options
    pages = BoardEntry.from_recents.question.visible.accessible(current_user).order_new.scoped(:include => [:state, :user])

    locals = {
      :id_name => 'questions',
      :title_icon => "user_comment",
      :title_name => _('Recent Questions'),
      :pages => pages,
      :per_page => options[:per_page],
      :recent_day => options[:recent_day],
      :symbol2name_hash => BoardEntry.get_symbol2name_hash(pages)
    }
  end

  # 記事一覧を取得する（partial用のオプションを返す）
  def find_recent_blogs_as_locals options
    find_params = BoardEntry.make_conditions(current_user.belong_symbols, {:entry_type=>'DIARY', :publication_type => 'public'})
    id_name = 'recent_blogs'
    pages = BoardEntry.scoped(
      :conditions => find_params[:conditions],
      :include => find_params[:include] | [ :user, :state ]
    ).from_recents.timeline.order_new.paginate(:page => target_page(id_name), :per_page => options[:per_page])

    locals = {
      :id_name => id_name,
      :title_icon => "user",
      :title_name => _('Blogs'),
      :pages => pages,
      :per_page => options[:per_page],
      :symbol2name_hash => BoardEntry.get_symbol2name_hash(pages)
    }
  end

  def find_timelines_as_locals options
    id_name = 'timelines'
    pages = BoardEntry.from_recents.accessible(current_user).timeline.order_new.scoped(:include => [:state, :user]).paginate(:page => target_page(id_name), :per_page => options[:per_page])
    locals = {
      :id_name => id_name,
      :title_name => _('See all'),
      :per_page => options[:per_page],
      :pages => pages,
      :symbol2name_hash => BoardEntry.get_symbol2name_hash(pages)
    }
  end

  # BBS記事一覧を取得するメソッドを動的に生成(partial用のオプションを返す)
  def find_recent_bbs_as_locals code, options = {}
    category = GroupCategory.find_by_code(code)
    title   = category.name
    id_name = category.code.downcase
    pages = []

    find_options = {:exclude_entry_type=>'DIARY'}
    find_options[:symbols] = options[:group_symbols] || Group.gid_by_category[category.id]
    if find_options[:symbols].size > 0
      find_params = BoardEntry.make_conditions(current_user.belong_symbols, find_options)
      pages = BoardEntry.scoped(
        :conditions => find_params[:conditions],
        :include => find_params[:include] | [ :user, :state ]
      ).from_recents.timeline.order_new.paginate(:page => target_page(id_name), :per_page => options[:per_page])
    end
    locals = {
      :id_name => id_name,
      :title_icon => "group",
      :title_name => title,
      :per_page => options[:per_page],
      :pages => pages,
      :symbol2name_hash => BoardEntry.get_symbol2name_hash(pages)
    }
  end

  def recent_bbs
    recent_bbs = []
    gid_by_category = Group.gid_by_category
    GroupCategory.ascend_by_sort_order.each do |category|
      options = { :group_symbols => gid_by_category[category.id], :per_page => per_page }
      recent_bbs << find_recent_bbs_as_locals(category.code.downcase, options)
    end
    recent_bbs
  end

  def unifed_feeds
    returning [] do |feeds|
      Admin::Setting.mypage_feed_settings.each do |setting|
        feed = nil
        timeout(Admin::Setting.mypage_feed_timeout.to_i) do
          feed = open(setting[:url], :proxy => SkipEmbedded::InitialSettings['proxy_url']) do |f|
            FeedNormalizer::FeedNormalizer.parse(f.read)
          end
        end
        feed.title = setting[:title] if setting[:title]
        limit = (setting[:limit] || Admin::Setting.mypage_feed_default_limit)
        feed.items.slice!(limit..-1) if feed.items.size > limit
        feeds << feed
      end
    end
  end

  def get_url_hash action, options = {}
    login_user_symbol_type, login_user_symbol_id = Symbol.split_symbol(session[:user_symbol])
    { :controller => 'user', :action => action, :uid => login_user_symbol_id }.merge options
  end

  def valid_list_types
    %w(questions recent_blogs) | GroupCategory.all.map{ |gc| gc.code.downcase }
  end

  # TODO BoardEntryに移動する
  # 指定日の記事一覧を取得する
  def find_entries_at_specified_date(selected_day)
    find_params = BoardEntry.make_conditions(current_user.belong_symbols, {:entry_type=>'DIARY'})
    find_params[:conditions][0] << " and DATE(date) = ?"
    find_params[:conditions] << selected_day
    BoardEntry.find(:all, :conditions=> find_params[:conditions], :order=>"date ASC",
                          :include => find_params[:include] | [ :user, :state ])
  end

  # TODO BoardEntryに移動する
  # 指定日以降で最初に記事が存在する日
  def first_entry_day_after_specified_date(selected_day)
    find_params = BoardEntry.make_conditions(current_user.belong_symbols, {:entry_type=>'DIARY'})
    find_params[:conditions][0] << " and DATE(date) > ?"
    find_params[:conditions] << selected_day
    next_day = BoardEntry.find(:first, :select => "date, DATE(date) as count_date, count(board_entries.id) as count",
                               :conditions=> find_params[:conditions],
                               :group => "count_date",
                               :order => "date ASC",
                               :limit => 1,
                               :joins => "LEFT OUTER JOIN entry_publications ON entry_publications.board_entry_id = board_entries.id")
    next_day ? next_day.date : nil
  end

  # TODO BoardEntryに移動する
  # 指定日以前で最後に記事が存在する日
  def last_entry_day_before_specified_date(selected_day)
    find_params = BoardEntry.make_conditions(current_user.belong_symbols, {:entry_type=>'DIARY'})
    find_params[:conditions][0] << " and DATE(date) < ?"
    find_params[:conditions] << selected_day
    prev_day = BoardEntry.find(:first, :select => "date, DATE(date) as count_date, count(board_entries.id) as count",
                               :conditions=> find_params[:conditions],
                               :group => "count_date",
                               :order => "date DESC",
                               :limit => 1,
                               :joins => "LEFT OUTER JOIN entry_publications ON entry_publications.board_entry_id = board_entries.id")
    prev_day ? prev_day.date : nil
  end

  # TODO helperへ移動する
  # アンテナの記事一覧のタイトル
  def antenna_entry_title(antenna_entry)
    if antenna = antenna_entry.antenna
      antenna.name
    else
      key = antenna_entry.key
      case
      when key == 'message'  then _("Notices for you")
      when key == 'comment'  then _("Entries you have made comments")
      when key == 'bookmark' then _("Entries bookmarked by yourself")
      when key == 'joined_group'    then _("Posts in the groups joined")
      else
        _('List of unread entries')
      end
    end
  end

  # TODO UserReadingに移動する
  # TODO SystemAntennaEntry等の記事取得の際に一緒に取得するようなロジックに出来ないか?
  #   => target_typeの判定ロジックが複数箇所に現れるのをなくしたい
  # 指定した記事idのをキーとした未読状態のUserReadingのハッシュを取得
  def unread_entry_id_hash_with_user_reading(entry_ids, target_type)
    result = {}
    if entry_ids && entry_ids.size > 0
      user_readings_conditions =
        # readがmysqlの予約語なのでバッククォートで括らないとエラー
        if target_type == 'message'
          ["user_id = ? AND board_entry_id in (?) AND `read` = ? AND notice_type = ?", current_user.id, entry_ids, false, 'notice']
        else
          ["user_id = ? AND board_entry_id in (?) AND `read` = ?", current_user.id, entry_ids, false]
        end
      user_readings = UserReading.find(:all, :conditions => user_readings_conditions)
      user_readings.map { |user_reading| result[user_reading.board_entry_id] = user_reading }
    end
    result
  end

  # TODO mypageのcontroller及びviewで@userを使うのをやめてcurrent_target_userにしてなくしたい。
  def load_user
    @user = current_user
  end

  def current_target_user
    current_user
  end

  def target_page target = nil
    if target
      target_key2current_pages = cookies[:target_key2current_pages]
      if target_key2current_pages.blank?
        params[:page]
      else
        params[:page] || JSON.parse(target_key2current_pages)[target] || 1
      end
    else
      params[:page]
    end
  end

  def save_current_page_to_cookie
    if params[:target] && params[:page]
      target_key2current_pages =
        begin
          JSON.parse(cookies[:target_key2current_pages])
        rescue => e
          {}
        end
      target_key2current_pages[params[:target]] = params[:page]
      cookies[:target_key2current_pages] = { :value => target_key2current_pages.to_json, :expires => 30.days.from_now }
      true
    else
      false
    end
  end
end
