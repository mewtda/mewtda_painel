module Ses
  class DomainIdentityService
    FAILED_DKIM_STATUSES = %w[FAILED TEMPORARY_FAILURE].freeze

    def initialize(client, ses: Aws::SESV2::Client.new)
      @client = client
      @ses = ses
    end

    def register!(domain)
      client.update!(email_sending_domain: domain, ses_dkim_tokens: dkim_tokens_for(domain),
                     ses_verification_status: 'pending', ses_verified_at: nil)
    end

    def refresh_status!
      status = status_from(ses.get_email_identity(email_identity: client.email_sending_domain))
      client.update!(ses_verification_status: status, ses_verified_at: verified_at_for(status))
      status
    end

    private

    attr_reader :client, :ses

    def dkim_tokens_for(domain)
      ses.create_email_identity(email_identity: domain).dkim_attributes.tokens
    rescue Aws::SESV2::Errors::AlreadyExistsException
      ses.get_email_identity(email_identity: domain).dkim_attributes.tokens
    end

    def status_from(identity)
      return 'verified' if identity.verified_for_sending_status
      return 'failed' if identity.dkim_attributes.status.in?(FAILED_DKIM_STATUSES)

      'pending'
    end

    def verified_at_for(status)
      client.ses_verified_at || Time.current if status == 'verified'
    end
  end
end
