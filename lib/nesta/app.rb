require "sinatra/base"
require "builder"
require "haml"
require "sass"

require File.expand_path('cache', File.dirname(__FILE__))
require File.expand_path('config', File.dirname(__FILE__))
require File.expand_path('models', File.dirname(__FILE__))
require File.expand_path('path', File.dirname(__FILE__))
require File.expand_path('plugins', File.dirname(__FILE__))
require File.expand_path('overrides', File.dirname(__FILE__))

Nesta::Plugins.load_local_plugins

module Nesta
  class App < Sinatra::Base
    register Sinatra::Cache

    set :root, File.expand_path('../..', File.dirname(__FILE__))
    set :views, File.expand_path('../../views', File.dirname(__FILE__))
    set :cache_enabled, Config.cache

    helpers Overrides::Renderers

    helpers do
      def set_from_config(*variables)
        variables.each do |var|
          instance_variable_set("@#{var}", Nesta::Config.send(var))
        end
      end
  
      def set_from_page(*variables)
        variables.each do |var|
          instance_variable_set("@#{var}", @page.send(var))
        end
      end
  
      def set_title(page)
        if page.respond_to?(:parent) && page.parent
          @title = "#{page.heading} - #{page.parent.heading}"
        else
          @title = "#{page.heading} - #{Nesta::Config.title}"
        end
      end
  
      def display_menu(menu, options = {})
        defaults = { :class => nil, :levels => 2 }
        options = defaults.merge(options)
        if options[:levels] > 0
          haml_tag :ul, :class => options[:class] do
            menu.each do |item|
              haml_tag :li do
                if item.respond_to?(:each)
                  display_menu(item, :levels => (options[:levels] - 1))
                else
                  haml_tag :a, :href => item.abspath do
                    haml_concat item.heading
                  end
                end
              end
            end
          end
        end
      end

      def no_widow(text)
        text.split[0...-1].join(" ") + "&nbsp;#{text.split[-1]}"
      end
  
      def set_common_variables
        @menu_items = Nesta::Menu.for_path('/')
        @site_title = Nesta::Config.title
        set_from_config(:title, :subtitle, :google_analytics_code)
        @heading = @title
      end

      def url_for(page)
        File.join(base_url, page.path)
      end
  
      def base_url
        url = "http://#{request.host}"
        request.port == 80 ? url : url + ":#{request.port}"
      end
  
      def absolute_urls(text)
        text.gsub!(/(<a href=['"])\//, '\1' + base_url + '/')
        text
      end
  
      def nesta_atom_id_for_page(page)
        published = page.date.strftime('%Y-%m-%d')
        "tag:#{request.host},#{published}:#{page.abspath}"
      end
  
      def atom_id(page = nil)
        if page
          page.atom_id || nesta_atom_id_for_page(page)
        else
          "tag:#{request.host},2009:/"
        end
      end
  
      def format_date(date)
        date.strftime("%d %B %Y")
      end
  
      def local_stylesheet?
        # Checks for the existence of local/views/local.sass. Useful for
        # themes that want to give the user the option to add their own
        # CSS rules.
        File.exist?(
            File.join(File.dirname(__FILE__), *%w[local views local.sass]))
      end
    end

    not_found do
      set_common_variables
      haml(:not_found)
    end

    error do
      set_common_variables
      haml(:error)
    end unless Nesta::App.environment == :development

    # If you want to change Nesta's behaviour, you have two options:
    #
    # 1. Create an app.rb file in your project's root directory.
    # 2. Make a theme or a plugin, and put all your code in there.
    #
    # You can add new routes, or modify the behaviour of any of the
    # default objects in app.rb, or replace any of the default view
    # templates by creating replacements of the same name in a ./views
    # folder situated in the root directory of the project for your
    # site.
    #
    # Your ./views folder gets searched first when rendering a template
    # or Sass file, then the currently configured theme is searched, and
    # finally Nesta will check if the template exists in the views
    # folder in the Nesta gem (which is where the default look and feel
    # is defined).
    #
    Overrides.load_local_app
    Overrides.load_theme_app

    get "/css/:sheet.css" do
      content_type "text/css", :charset => "utf-8"
      cache sass(params[:sheet].to_sym)
    end

    get "/" do
      set_common_variables
      set_from_config(:title, :subtitle, :description, :keywords)
      @heading = @title
      @title = "#{@title} - #{@subtitle}"
      @articles = Page.find_articles[0..7]
      @body_class = "home"
      cache haml(:index)
    end

    get %r{/attachments/([\w/.-]+)} do
      file = File.join(Nesta::Config.attachment_path, params[:captures].first)
      send_file(file, :disposition => nil)
    end

    get "/articles.xml" do
      content_type :xml, :charset => "utf-8"
      set_from_config(:title, :subtitle, :author)
      @articles = Page.find_articles.select { |a| a.date }[0..9]
      cache builder(:atom)
    end

    get "/sitemap.xml" do
      content_type :xml, :charset => "utf-8"
      @pages = Page.find_all
      @last = @pages.map { |page| page.last_modified }.inject do |latest, page|
        (page > latest) ? page : latest
      end
      cache builder(:sitemap)
    end

    get "*" do
      set_common_variables
      parts = params[:splat].map { |p| p.sub(/\/$/, "") }
      @page = Nesta::Page.find_by_path(File.join(parts))
      raise Sinatra::NotFound if @page.nil?
      set_title(@page)
      set_from_page(:description, :keywords)
      cache haml(@page.template, :layout => @page.layout)
    end
  end
end