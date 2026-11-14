require 'test_helper'

module Ses
  class DomainIdentityServiceTest < ActiveSupport::TestCase
    DkimAttributes = Struct.new(:tokens, :status)
    CreateResponse = Struct.new(:dkim_attributes)
    GetResponse = Struct.new(:verified_for_sending_status, :dkim_attributes)

    class FakeSesClient
      attr_reader :create_email_identity_args, :get_email_identity_args

      def initialize(tokens: %w[tok1 tok2 tok3], verified: false)
        @tokens = tokens
        @verified = verified
      end

      def create_email_identity(args)
        @create_email_identity_args = args
        CreateResponse.new(DkimAttributes.new(@tokens, 'PENDING'))
      end

      def get_email_identity(args)
        @get_email_identity_args = args
        GetResponse.new(@verified, DkimAttributes.new(@tokens, 'PENDING'))
      end
    end

    def build_client
      Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
                     email_sending_domain: 'loja.com.br')
    end

    test 'register! stores the dkim tokens and marks status as pending' do
      client = build_client
      fake_ses = FakeSesClient.new(tokens: %w[abc def ghi])

      DomainIdentityService.new(client, ses: fake_ses).register!('loja.com.br')

      client.reload
      assert_equal %w[abc def ghi], client.ses_dkim_tokens
      assert_equal 'pending', client.ses_verification_status
      assert_equal({ email_identity: 'loja.com.br' }, fake_ses.create_email_identity_args)
    end

    test 'refresh_status! marks the client as verified when SES confirms it' do
      client = build_client
      client.update!(ses_dkim_tokens: %w[abc def ghi], ses_verification_status: 'pending')
      fake_ses = FakeSesClient.new(verified: true)

      result = DomainIdentityService.new(client, ses: fake_ses).refresh_status!

      assert_equal 'verified', result
      client.reload
      assert_equal 'verified', client.ses_verification_status
      assert client.ses_verified_at.present?
    end

    test 'refresh_status! keeps the client as pending when SES has not verified it yet' do
      client = build_client
      client.update!(ses_dkim_tokens: %w[abc def ghi], ses_verification_status: 'pending')
      fake_ses = FakeSesClient.new(verified: false)

      result = DomainIdentityService.new(client, ses: fake_ses).refresh_status!

      assert_equal 'pending', result
      client.reload
      assert_equal 'pending', client.ses_verification_status
      assert_nil client.ses_verified_at
    end
  end
end
