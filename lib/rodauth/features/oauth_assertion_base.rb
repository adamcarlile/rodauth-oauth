# frozen-string-literal: true

require "rodauth/oauth/refinements"

module Rodauth
  Feature.define(:oauth_assertion_base, :OauthAssertionBase) do
    using PrefixExtensions

    depends :oauth_base

    auth_value_methods(
      :assertion_grant_type?,
      :client_assertion_type?,
      :assertion_grant_type,
      :client_assertion_type
    )

    private

    def validate_oauth_token_params
      return super unless assertion_grant_type?

      redirect_response_error("invalid_grant") unless param_or_nil("assertion")
    end

    def require_oauth_application
      if assertion_grant_type?
        @oauth_application = __send__(:"require_oauth_application_from_#{assertion_grant_type}_assertion_issuer", param("assertion"))
      elsif client_assertion_type?
        @oauth_application = __send__(:"require_oauth_application_from_#{client_assertion_type}_assertion_subject",
                                      param("client_assertion"))
      else
        return super
      end

      redirect_response_error("invalid_grant") unless @oauth_application

      if client_assertion_type? &&
         (client_id = param_or_nil("client_id")) &&
         client_id != @oauth_application[oauth_applications_client_id_column]
        # If present, the value of the
        # "client_id" parameter MUST identify the same client as is
        # identified by the client assertion.
        redirect_response_error("invalid_grant")
      end
    end

    def account_from_bearer_assertion_subject(subject)
      __insert_or_do_nothing_and_return__(
        db[accounts_table],
        account_id_column,
        [login_column],
        login_column => subject
      )
    end

    def create_oauth_token(grant_type)
      return super unless assertion_grant_type?(grant_type) && supported_grant_type?(grant_type)

      account = __send__(:"account_from_#{assertion_grant_type}_assertion", param("assertion"))

      redirect_response_error("invalid_grant") unless account

      grant_scopes = if param_or_nil("scope")
                       redirect_response_error("invalid_grant") unless check_valid_scopes?
                       scopes
                     else
                       @oauth_application[oauth_applications_scopes_column]
                     end

      create_params = {
        oauth_tokens_account_id_column => account[account_id_column],
        oauth_tokens_oauth_application_id_column => @oauth_application[oauth_applications_id_column],
        oauth_tokens_scopes_column => grant_scopes
      }

      generate_oauth_token(create_params, false)
    end

    def assertion_grant_type?(grant_type = param("grant_type"))
      grant_type.start_with?("urn:ietf:params:oauth:grant-type:")
    end

    def client_assertion_type?(client_assertion_type = param("client_assertion_type"))
      client_assertion_type.start_with?("urn:ietf:params:oauth:client-assertion-type:")
    end

    def assertion_grant_type(grant_type = param("grant_type"))
      grant_type.delete_prefix("urn:ietf:params:oauth:grant-type:").tr("-", "_")
    end

    def client_assertion_type(assertion_type = param("client_assertion_type"))
      assertion_type.delete_prefix("urn:ietf:params:oauth:client-assertion-type:").tr("-", "_")
    end
  end
end