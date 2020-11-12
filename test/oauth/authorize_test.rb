# frozen_string_literal: true

require "test_helper"

class RodauthOauthAuthorizeTest < RodaIntegration
  def test_authorize_get_public_area
    setup_application
    visit "/"
    assert page.html.include?("Unauthorized")
  end

  def test_authorize_get_authorize_not_logged_in_no_client_application
    setup_application
    visit "/authorize"
    assert page.current_path == "/login",
           "was redirected instead to #{page.current_path}"
  end

  def test_authorize_get_authorize
    setup_application
    login
    visit "/authorize"
    assert page.current_path == "/",
           "was redirected instead to #{page.current_path}"
  end

  def test_authorize_get_authorize_invalid_client_id
    setup_application
    login
    visit "/authorize?client_id=bla"
    assert page.current_url.end_with?("/?error=invalid_request"),
           "was redirected instead to #{page.current_url}"
  end

  def test_authorize_get_authorize_invalid_redirect_uri
    setup_application
    login
    visit "/authorize?client_id=#{oauth_application[:client_id]}&redirect_uri=bla"
    assert page.current_url.end_with?("/?error=invalid_request"),
           "was redirected instead to #{page.current_url}"
  end

  def test_authorize_get_authorize_invalid_scope
    setup_application
    login
    visit "/authorize?client_id=#{oauth_application[:client_id]}& "\
          "redirect_uri=#{oauth_application[:redirect_uri]}&" \
          "scope=marvel"
    assert page.current_url.include?("?error=invalid_scope"),
           "was redirected instead to #{page.current_url}"
  end

  def test_authorize_get_authorize_multiple_uris
    setup_application
    login

    application = oauth_application(redirect_uri: "http://redirect1 http://redirect2")

    visit "/authorize?client_id=#{application[:client_id]}&" \
          "scope=user.read+user.write"
    assert page.current_url.include?("?error=invalid_request"),
           "was redirected instead to #{page.current_url}"

    visit "/authorize?client_id=#{application[:client_id]}&" \
          "redirect_uri=http://redirect2&" \
          "scope=user.read+user.write"
    assert page.current_path == "/authorize",
           "was redirected instead to #{page.current_url}"
  end

  def test_authorize_post_authorize_same_code
    rodauth do
      oauth_unique_id_generator { "CODE" }
    end
    setup_application
    login

    _grant = oauth_grant(code: "CODE")

    # show the authorization form
    visit "/authorize?client_id=#{oauth_application[:client_id]}&scope=user.read+user.write"
    assert page.current_path == "/authorize",
           "was redirected instead to #{page.current_path}"

    # submit authorization request
    click_button "Authorize"

    assert db[:oauth_grants].count == 1,
           "grant has been created when it shouldn't"

    assert page.current_url.include?("?error=invalid_request&error_description=error+generating+unique+token"),
           "was redirected instead to #{page.current_url}"
  end

  def test_authorize_post_authorize
    setup_application
    login

    # show the authorization form
    visit "/authorize?client_id=#{oauth_application[:client_id]}&scope=user.read+user.write"
    assert page.current_path == "/authorize",
           "was redirected instead to #{page.current_path}"

    # submit authorization request
    click_button "Authorize"

    assert db[:oauth_grants].count == 1,
           "no grant has been created"

    oauth_grant = db[:oauth_grants].first

    assert page.current_url == "#{oauth_application[:redirect_uri]}?code=#{oauth_grant[:code]}",
           "was redirected instead to #{page.current_url}"
    assert oauth_grant[:access_type] == "offline"
  end

  def test_authorize_post_authorize_access_type_disabled
    rodauth do
      use_oauth_access_type? false
    end
    setup_application
    login

    # show the authorization form
    visit "/authorize?client_id=#{oauth_application[:client_id]}&scope=user.read+user.write&access_type=online"
    assert page.current_path == "/authorize",
           "was redirected instead to #{page.current_path}"

    # submit authorization request
    click_button "Authorize"

    assert db[:oauth_grants].count == 1,
           "no grant has been created"

    oauth_grant = db[:oauth_grants].first

    assert page.current_url == "#{oauth_application[:redirect_uri]}?code=#{oauth_grant[:code]}",
           "was redirected instead to #{page.current_url}"
    assert oauth_grant[:access_type] == "offline"
  end

  def test_authorize_post_authorize_access_type_online
    setup_application
    login

    # show the authorization form
    visit "/authorize?client_id=#{oauth_application[:client_id]}&scope=user.read+user.write&access_type=online"
    assert page.current_path == "/authorize",
           "was redirected instead to #{page.current_path}"

    # submit authorization request
    click_button "Authorize"

    assert db[:oauth_grants].count == 1,
           "no grant has been created"

    oauth_grant = db[:oauth_grants].first

    assert page.current_url == "#{oauth_application[:redirect_uri]}?code=#{oauth_grant[:code]}",
           "was redirected instead to #{page.current_url}"
    assert oauth_grant[:access_type] == "online"
  end

  def test_authorize_post_authorize_access_type_online_approval_prompt_auto_no_valid_grant
    setup_application
    login

    # no previous grant
    visit "/authorize?client_id=#{oauth_application[:client_id]}&scope=user.read+user.write&" \
          "access_type=online&approval_prompt=auto"
    assert page.current_path.start_with?("/authorize"),
           "was redirected instead to #{page.current_path}"

    # previous offline grant
    oauth_grant(access_type: "offline", expires_in: Sequel.date_add(Sequel::CURRENT_TIMESTAMP, seconds: 60))

    visit "/authorize?client_id=#{oauth_application[:client_id]}&scope=user.read+user.write&" \
          "access_type=online&approval_prompt=auto"
    assert page.current_path.start_with?("/authorize"),
           "was redirected instead to #{page.current_path}"
  end

  def test_authorize_post_authorize_access_type_online_approval_prompt_auto_wrong_scope
    setup_application
    login

    # OLD grant
    oauth_grant(access_type: "online", expires_in: Sequel.date_sub(Sequel::CURRENT_TIMESTAMP, seconds: 60))

    # extra scope
    visit "/authorize?client_id=#{oauth_application[:client_id]}&scope=user.read&" \
          "access_type=online&approval_prompt=auto"
    assert page.current_path.start_with?("/authorize"),
           "was redirected instead to #{page.current_path}"
  end

  def test_authorize_post_authorize_access_type_online_approval_prompt_auto
    setup_application
    login

    # OLD grant
    oauth_grant(access_type: "online", expires_in: Sequel.date_sub(Sequel::CURRENT_TIMESTAMP, seconds: 60))

    visit "/authorize?client_id=#{oauth_application[:client_id]}&scope=user.read+user.write&" \
          "access_type=online&approval_prompt=auto"

    new_grant = db[:oauth_grants].order(:id).last

    assert page.current_url == "#{oauth_application[:redirect_uri]}?code=#{new_grant[:code]}",
           "was redirected instead to #{page.current_url}"

    assert db[:oauth_grants].count == 2,
           "no new grant has been created"

    assert new_grant[:access_type] == "online"
  end

  def test_authorize_post_authorize_with_state
    setup_application
    login

    # show the authorization form
    visit "/authorize?client_id=#{oauth_application[:client_id]}&state=STATE"
    assert page.current_path == "/authorize",
           "was redirected instead to #{page.current_path}"

    # submit authorization request
    click_button "Authorize"

    assert db[:oauth_grants].count == 1,
           "no grant has been created"

    oauth_grant = db[:oauth_grants].first

    assert page.current_url == "#{oauth_application[:redirect_uri]}?code=#{oauth_grant[:code]}&state=STATE",
           "was redirected instead to #{page.current_url}"
  end

  def test_authorize_post_authorize_unsupported_response_type
    setup_application
    login

    # show the authorization form
    visit "/authorize?client_id=#{oauth_application[:client_id]}&scope=user.read+user.write&response_type=unknown"

    assert page.current_url.include?("?error=invalid_request"),
           "was redirected instead to #{page.current_url}"
  end

  def test_authorize_post_authorize_no_implicit_grant
    setup_application
    login

    # show the authorization form
    visit "/authorize?client_id=#{oauth_application[:client_id]}&scope=user.read+user.write&response_type=token"

    assert page.current_url.include?("?error=invalid_request"),
           "was redirected instead to #{page.current_url}"
  end

  def test_authorize_post_authorize_with_implicit_grant
    rodauth do
      use_oauth_implicit_grant_type? true
    end
    setup_application

    login

    # show the authorization form
    visit "/authorize?client_id=#{oauth_application[:client_id]}&response_type=token&state=STATE"
    assert page.current_path == "/authorize",
           "was redirected instead to #{page.current_path}"

    # submit authorization request
    click_button "Authorize"

    assert db[:oauth_tokens].count == 1,
           "no token has been created"

    oauth_token = db[:oauth_tokens].first

    assert page.current_url == "#{oauth_application[:redirect_uri]}#access_token=#{oauth_token[:token]}&" \
                             "token_type=bearer&expires_in=3600&state=STATE",
           "was redirected instead to #{page.current_url}"
  end

  def test_authorize_post_authorize_with_pkce
    setup_application

    login

    # show the authorization form
    visit "/authorize?client_id=#{oauth_application[:client_id]}&" \
          "code_challenge=#{PKCE_CHALLENGE}&code_challenge_method=S256"

    assert page.current_path == "/authorize",
           "was redirected instead to #{page.current_path}"

    # submit authorization request
    click_button "Authorize"

    assert db[:oauth_grants].count == 1,
           "no grant has been created"

    oauth_grant = db[:oauth_grants].first
    assert oauth_grant[:code_challenge] == PKCE_CHALLENGE
    assert oauth_grant[:code_challenge_method] == "S256"

    assert page.current_url == "#{oauth_application[:redirect_uri]}?code=#{oauth_grant[:code]}",
           "was redirected instead to #{page.current_url}"
  end

  def test_authorize_post_authorize_with_pkce_disabled
    rodauth do
      use_oauth_pkce? false
    end
    setup_application

    login

    # show the authorization form
    visit "/authorize?client_id=#{oauth_application[:client_id]}&" \
          "code_challenge=#{PKCE_CHALLENGE}&code_challenge_method=S256"

    assert page.current_path == "/authorize",
           "was redirected instead to #{page.current_path}"

    # submit authorization request
    click_button "Authorize"

    assert db[:oauth_grants].count == 1,
           "no grant has been created"

    oauth_grant = db[:oauth_grants].first
    assert oauth_grant[:code_challenge].nil?
    assert oauth_grant[:code_challenge_method].nil?

    assert page.current_url == "#{oauth_application[:redirect_uri]}?code=#{oauth_grant[:code]}",
           "was redirected instead to #{page.current_url}"
  end

  def test_authorize_post_authorize_with_forced_pkce_no_challenge
    rodauth do
      oauth_require_pkce true
    end
    setup_application

    login

    # show the authorization form
    visit "/authorize?client_id=#{oauth_application[:client_id]}"

    assert page.current_url.include?("?error=invalid_request"),
           "code challenge required"
  end

  def test_authorize_post_authorize_code_form_post
    setup_application
    login

    # show the authorization form
    visit "/authorize?client_id=#{oauth_application[:client_id]}&scope=user.read+user.write&response_mode=form_post"
    assert page.current_path == "/authorize",
           "was redirected instead to #{page.current_path}"

    # submit authorization request
    click_button "Authorize"

    assert db[:oauth_grants].count == 1,
           "no grant has been created"

    assert page.has_button?("Back to Client Application")
    click_button("Back to Client Application")

    assert page.current_url == oauth_application[:redirect_uri].to_s,
           "was redirected instead to #{page.current_url}"
  end

  def test_authorize_post_authorize_code_default_form_post
    rodauth do
      oauth_response_mode "form_post"
    end
    setup_application
    login

    # show the authorization form
    visit "/authorize?client_id=#{oauth_application[:client_id]}&scope=user.read+user.write"
    assert page.current_path == "/authorize",
           "was redirected instead to #{page.current_path}"

    # submit authorization request
    click_button "Authorize"

    assert db[:oauth_grants].count == 1,
           "no grant has been created"

    assert page.has_button?("Back to Client Application")
    click_button("Back to Client Application")

    assert page.current_url == oauth_application[:redirect_uri].to_s,
           "was redirected instead to #{page.current_url}"
  end
end
