module Hpricotscape
  

  class Browser
    attr_accessor :cookies, :url, :html, :history, :debug
    
    def initialize preset_cookies = [], debug_mode = false
      self.cookies = preset_cookies ? preset_cookies.dup : []
      self.debug = debug_mode
      self.history = []
    end
    
    # GET a resource
    def load(url)
      _load(url, :get)
    end
    
    # Submit a form on the page, with given input values.  If the input values don't exist on the page, they will *NOT* be added.
    def submit(form_selector = 'form', submit_matcher = 'submit', input_values_hash = {})
      forms = (self.html/form_selector)
      
      if forms.length != 1
        raise "Problem with parsing form page -- expected only 1 form tag on `#{self.url}` matching selector `#{form_selector}`, but selected `#{forms.length}` fom tags\n#{forms.inspect}"
      end
      
      form_values = Hpricotscape::Form.parse(forms[0])
      full_action_url = form_values[:action].starts_with?('/') ? 
        "#{self.url.split('://').first}://#{self.url.split('://').last.split('/').first}#{form_values[:action]}" : 
        form_values[:action]
      
      # Allow user to use strings or symbols for input values, and merge them into the form
      form_values[:inputs].keys.each do |k|
        form_values[:inputs][k.to_s] = input_values_hash[k.to_s] if input_values_hash.has_key?(k.to_s)
        form_values[:inputs][k.to_s] = input_values_hash[k.to_sym] if input_values_hash.has_key?(k.to_sym)
      end
      
      submit_key = form_values[:submits].keys.select { |k| k.downcase.index(submit_matcher) }.first
      form_post_body = form_values[:inputs].merge(submit_key => form_values[:submits][submit_key])

      _load(full_action_url, :post, form_post_body)
    end  
    
    
    def _load(url, method = :get, send_body = nil)
      loaded = Hpricotscape::Net.access_and_hpricot(url, self.cookies, self.url, method, send_body, nil, self.debug)
      self.cookies = loaded[:cookies]
      self.url = loaded[:url]
      self.history << self.url
      self.html = loaded[:hpricot]
    end
  end
  
  
  
  module Form
    
    # Simply a helper for parsing a form embedded in a page, usually used for building up a form submission
    def self.parse(form_hpricot)
      form_values = {:inputs => {}, :submits => {}, :action => form_hpricot.attributes['action'], :buttons => {}}

      # Check each input
      (form_hpricot/'input').each do |i| 
        # Ignore submits for later
        if i.attributes['type'] == 'submit'
          next
        # Only take checked checkboxes
        elsif i.attributes['type'].downcase == 'checkbox'
          form_values[:inputs][i.attributes['name']] = "#{i.attributes['value']}" if !i.attributes['checked'].blank? and i.attributes['checked'].downcase != 'false'
        # Only take checked radio buttons
        elsif i.attributes['type'].downcase == 'radio' and !form_values[:inputs][i.attributes['name']].blank?
          form_values[:inputs][i.attributes['name']] = "#{i.attributes['value']}" if !i.attributes['checked'].blank? and i.attributes['checked'].downcase != 'false'
        else
          form_values[:inputs][i.attributes['name']] = "#{i.attributes['value']}"
        end
      end

      # Check each select 
      # TODO take default option and get option value
      (form_hpricot/'select').each do |s|
        selected_option = (s/'option[@selected=\'selected\']')
        default_option = selected_option.length > 1 ? selected_option[0] : (s/'option')[0]
        form_values[:inputs][s.attributes['name']] = "#{default_option.attributes['value']}"
      end

      # Check each textarea 
      (form_hpricot/'textarea').each do |i|
        form_values[:inputs][i.attributes['name']] = "#{i.inner_text}"
      end

      # look for submit buttons
      (form_hpricot/'*[@type=\'submit\']').each do |i|
        form_values[:submits][i.attributes['name']] = "#{i.attributes['value']}"
      end

      form_values
    end
    
  end
  
  # Handles all access helpers, including gzipping
  module Net
    DEFAULT_UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_2) AppleWebKit/535.7 (KHTML, like Gecko) Chrome/16.0.912.77 Safari/535.7'
    
    def self.access_and_hpricot(full_url, cookies= [], referer = nil, method = :get, send_body = nil, override_cookie_string = nil, debug_mode = false, user_agent = DEFAULT_UA)
      puts "[INFO #{Time.now}] GET #{full_url}" if debug_mode
      
      action_uri = URI.parse(full_url)
      http = ::Net::HTTP.new(action_uri.host, action_uri.port)
      
      http.set_debug_output $stderr if debug_mode
      
      if full_url[0..6].starts_with? 'https'
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      
      cookie_string = override_cookie_string ? override_cookie_string : cookies.map {|c| "#{c.keys[0]}=#{c[c.keys[0]][:value]}"}.join('; ')
      
      request = (method == :post ? ::Net::HTTP::Post : ::Net::HTTP::Get).new(action_uri.path, { 
        'Cookie' => cookie_string, 
        'Referer' => referer.to_s, 
        'User-Agent' => user_agent, 
        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8', 
        'Accept-Encoding' => 
        'gzip,deflate,sdch', 
        'Accept-Language' => 'en-US,en;q=0.8', 
        'Accept-Charset' => 'ISO-8859-1,utf-8;q=0.7,*;q=0.3' 
      })
      request.set_form_data(send_body) if send_body

      response = http.request(request)

      new_cookies = cookies
      if response.header['Set-Cookie']
        new_cookies = Hpricotscape::Cookie.parse_set_cookies(cookies, response.header['Set-Cookie'])
      end

      redirect_url = nil
      
      if response.header['location'] # let 'open-uri' do follow all redirects
        redirect_url = response.header['location'].starts_with?('/') ? "#{base_url(full_url)}#{response.header['location']}" : response.header['location']
        
        puts "[INFO #{Time.now}] +--- Got redirected to #{redirect_url}" if debug_mode
        
        redirect_settings = { 
          'Cookie' => cookie_string, 
          'Referer' => full_url, 
          'User-Agent' => user_agent, 
          :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE 
        }
        
        final_doc = open(redirect_url, redirect_settings) do |f| 
          new_cookies = parse_set_cookies(new_cookies, f.meta['set-cookie'])
          Hpricot(f)
        end 
      else
        final_doc = Hpricot(unzipped_body(response))
      end
      
      return { cookies: new_cookies, hpricot: final_doc, url: redirect_url ? redirect_url : full_url }
    end

    def self.base_url(url)
      url[0...url.index('/', 8)]
    end
    
    def self.unzipped_body(res)
      if res.header[ 'Content-Encoding' ].eql?( 'gzip' ) then
        sio = StringIO.new( res.body )
        gz = Zlib::GzipReader.new( sio )
        page = gz.read()
      else    
        page = res.body
      end
      page
    end
  end
  
  
  # Handles set-cookie parsing and merging, much of this borrowed from webrick
  module Cookie
    
    # File webrick/httputils.rb, line 190
    def self.dequote(str)
      ret = (/\A"(.*)"\Z/ =~ str) ? $1 : str.dup
      ret.gsub!(/\\(.)/, "\\1")
      ret
    end

    # File webrick/cookie.rb, line 79
    def self.parse_set_cookie(str)
      cookie_elem = str.split(';')
      first_elem = cookie_elem.shift
      first_elem.strip!
      key, value = first_elem.split('=', 2)
      cookie = {key => {:value => dequote(value)}}
      cookie_elem.each{|pair|
        pair.strip!
        key, value = pair.split('-', 2)
        if value
          value = dequote(value.strip)
        end
        case key.downcase
        when "domain"  then cookie[:domain]  = value
        when "path"    then cookie[:path]    = value
        when "expires" then cookie[:expires] = value
        when "max-age" then cookie[:max_age] = Integer(value)
        when "comment" then cookie[:comment] = value
        when "version" then cookie[:version] = Integer(value)
        when "secure"  then cookie[:secure] = true
        end
      }
      return cookie
    end
    
    
    # File webrick/cookie.rb, line 104
    def self.parse_set_cookies(existing_cookies, str)
      new_cookies = str ? str.split(/,(?=[^;,]*=)|,$/).collect{ |c| parse_set_cookie(c) } : []
      if new_cookies == nil or new_cookies.empty?
        return existing_cookies
      else
        final_cookies = existing_cookies
        new_cookies.each do |new_cookie|
          new_cookie.each_pair do |k,v|
            cookie_already_exists = false
            final_cookies.each do |cookie|

              # Try to update an existing cookie
              if cookie.has_key?(k)
                cookie[k] = v
                cookie_already_exists = true
                next
              end

            end

            # Otherwise, we didn't find it so pre-pend it
            final_cookies.unshift({k => v}) unless cookie_already_exists

          end
        end

        return final_cookies
      end
    end
  end
end
