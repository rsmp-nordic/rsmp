module RSMP
  module Secure
    # Immutable binding between an authenticated credential and RSMP negotiation.
    class AuthorizationContext
      attr_reader :credential_id, :rsmp_id, :role, :core_version

      def initialize(credential_id:, rsmp_id:, role:, core_version:)
        @credential_id = String(credential_id).dup.freeze
        @rsmp_id = String(rsmp_id).dup.freeze
        @role = role.to_sym
        @core_version = String(core_version).dup.freeze
        freeze
      end

      def to_h
        {
          credential_id: credential_id,
          rsmp_id: rsmp_id,
          role: role,
          core_version: core_version
        }.freeze
      end
    end
  end
end
