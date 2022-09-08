# frozen_string_literal: true

module Rodauth
  Feature.define(:oauth_implicit_grant, :OauthImplicitGrant) do
    depends :oauth_authorize_base

    private

    def check_valid_response_type?
      response_type = param_or_nil("response_type")

      response_type.nil? || response_type == "token" || super
    end

    def do_authorize(response_params = {}, response_mode = param_or_nil("response_mode"))
      return super unless param("response_type") == "token"

      response_mode ||= "fragment"
      response_params.replace(_do_authorize_token)

      response_params["state"] = param("state") if param_or_nil("state")

      [response_params, response_mode]
    end

    def _do_authorize_token
      grant_params = {
        oauth_grants_oauth_application_id_column => oauth_application[oauth_applications_id_column],
        oauth_grants_scopes_column => scopes,
        oauth_grants_account_id_column => account_id
      }
      oauth_grant = generate_token(grant_params, false)

      json_access_token_payload(oauth_grant)
    end

    def authorize_response(params, mode)
      return super unless mode == "fragment"

      redirect_url = URI.parse(redirect_uri)
      params = params.map { |k, v| "#{k}=#{v}" }
      params << redirect_url.query if redirect_url.query
      redirect_url.fragment = params.join("&")
      redirect(redirect_url.to_s)
    end

    def oauth_server_metadata_body(*)
      super.tap do |data|
        data[:response_types_supported] << "token"
        data[:response_modes_supported] << "fragment"
        data[:grant_types_supported] << "implicit"
      end
    end

    def check_valid_response_type?
      return true if param_or_nil("response_type") == "token"

      super
    end
  end
end
