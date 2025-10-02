# frozen_string_literal: true

module RSMP
  class Proxy
    module Modules
      # Version negotiation and handling
      # Manages RSMP version handshake between sites and supervisors
      module VersionHandling
        def core_versions
          version = @site_settings['core_version']
          if version == 'latest'
            [RSMP::Schema.latest_core_version]
          elsif version
            [version]
          else
            RSMP::Schema.core_versions
          end
        end

        def check_core_version(message)
          versions = core_versions
          # find versions that both we and the client support
          candidates = message.versions & versions
          if candidates.any?
            @core_version = candidates.max_by { |v| Gem::Version.new(v) } # pick latest version
          else
            reason = "RSMP versions [#{message.versions.join(', ')}] requested, " \
                     "but only [#{versions.join(', ')}] supported."
            dont_acknowledge message, 'Version message rejected', reason, force: true
            raise HandshakeError, reason
          end
        end

        def process_version(message); end

        def extraneous_version(message)
          dont_acknowledge message, 'Received', 'extraneous Version message'
        end

        def send_version(site_id, core_versions)
          versions = if core_versions == 'latest'
                       [RSMP::Schema.latest_core_version]
                     elsif core_versions == 'all'
                       RSMP::Schema.core_versions
                     else
                       [core_versions].flatten
                     end
          versions_array = versions.map { |v| { 'vers' => v } }

          site_id_array = [site_id].flatten.map { |id| { 'sId' => id } }

          version_response = Version.new({
                                           'RSMP' => versions_array,
                                           'siteId' => site_id_array,
                                           'SXL' => sxl_version.to_s
                                         })
          send_message version_response
        end

        def version_acknowledged; end

        # Use Gem class to check version requirement
        # Requirement must be a string like '1.1', '>=1.0.3' or '<2.1.4',
        # or list of strings, like ['<=1.4','<1.5']
        def self.version_meets_requirement?(version, requirement)
          Gem::Requirement.new(requirement).satisfied_by?(Gem::Version.new(version))
        end
      end
    end
  end
end
