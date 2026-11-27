require 'pathname'
require_relative 'configuration/validation'

module RSMP
  module Secure
    # Configuration helpers for Secure RSMP settings and path conventions.
    module Configuration
      include ConfigurationValidation

      def settings(raw)
        raw = stringify_keys(raw || {})
        {
          'profile' => PROFILE,
          'max_frame_size' => DEFAULT_MAX_FRAME_SIZE,
          'handshake_timeout' => DEFAULT_HANDSHAKE_TIMEOUT,
          'rekey_after_messages' => DEFAULT_REKEY_AFTER_MESSAGES,
          'rekey_after_bytes' => DEFAULT_REKEY_AFTER_BYTES,
          'rekey_after_seconds' => DEFAULT_REKEY_AFTER_SECONDS,
          'rekey_timeout' => DEFAULT_REKEY_TIMEOUT,
          'log_decrypted_payloads' => false
        }.merge(raw)
      end

      def merge_peer_settings(local, peer, peer_id: nil, peer_role: nil)
        local = local_identity_settings(local)
        peer = stringify_keys(peer || {})
        peer = default_peer_paths(peer, peer['id'] || peer_id)
        return local unless peer_configured?(peer)

        authorized_id = peer['supervisor_id'] || peer_id || peer['id']
        settings_with_peers(
          local,
          [secure_peer(peer, peer['id'] || peer_id, rsmp_id: authorized_id, rsmp_role: peer_role)]
        )
      end

      def site_local_settings(site_settings)
        settings_with_config_dir(
          site_settings,
          site_settings['secure'],
          local_id: local_identity_id(site_settings),
          credential_id: local_identity_id(site_settings)
        )
      end

      def site_peer_settings(site_settings, supervisor_settings)
        merge_peer_settings(site_local_settings(site_settings), supervisor_settings['secure'], peer_role: 'supervisor')
      end

      def supervisor_local_settings(supervisor_settings)
        secure_settings = supervisor_settings['secure'] || supervisor_settings.dig('default', 'secure')
        local_id = local_identity_id(supervisor_settings, fallback: DEFAULT_SUPERVISOR_ID)
        settings_with_config_dir(
          supervisor_settings,
          secure_settings,
          local_id: local_id,
          credential_id: secure_settings && secure_settings['id']
        )
      end

      def supervisor_site_settings(supervisor_settings, site_settings, site_id: nil)
        merge_peer_settings(supervisor_local_settings(supervisor_settings),
                            site_settings['secure'],
                            peer_id: site_settings['site_id'] || site_id,
                            peer_role: 'site')
      end

      def site_inbound_settings(site_settings)
        peers = supervisors_to_peers(site_settings['supervisors'] || [])
        settings_with_peers(site_local_settings(site_settings), peers)
      end

      def supervisor_inbound_settings(supervisor_settings)
        sites = supervisor_settings['sites'] || {}
        local = supervisor_local_settings(supervisor_settings)
        settings_with_peers(local, sites_to_peers(sites, include_all: required?(local)))
      end

      def expand_config_path(path, secure_settings)
        return path if Pathname.new(path).absolute?

        config_dir = secure_settings[CONFIG_DIR_KEY]
        return path unless config_dir

        File.expand_path(path, config_dir)
      end

      private

      def local_identity_settings(local)
        settings(local).except(*PEER_SETTING_KEYS)
      end

      def settings_with_config_dir(settings, secure_settings = settings['secure'], local_id: nil, credential_id: nil)
        secure_settings = stringify_keys(secure_settings || {})
        secure_settings = default_local_identity_paths(secure_settings, local_id)
        if credential_id && mode?(secure_settings)
          secure_settings = secure_settings.merge(LOCAL_ID_KEY => credential_id)
        end
        config_dir = settings[CONFIG_DIR_KEY]
        return secure_settings unless config_dir

        secure_settings.merge(CONFIG_DIR_KEY => config_dir)
      end

      def settings_with_peers(local, peers)
        merged = local_identity_settings(local)
        return merged if peers.empty?

        merged.merge('peers' => peers)
      end

      def supervisors_to_peers(supervisors)
        supervisors.each_with_object([]) do |supervisor, peers|
          next unless supervisor.key?('secure')

          secure = stringify_keys(supervisor['secure'] || {})
          secure = default_peer_paths(secure, secure['id'])
          next unless peer_configured?(secure)

          peers << secure_peer(
            secure,
            secure['id'] || "#{supervisor['ip']}:#{supervisor['port']}",
            credential_id: secure['id'],
            rsmp_id: secure['supervisor_id'] || secure['id'],
            rsmp_role: 'supervisor'
          )
        end
      end

      def sites_to_peers(sites, include_all: false)
        sites.each_with_object([]) do |(site_id, site_settings), peers|
          next if site_id == 'default'
          next unless include_all || site_settings.key?('secure')

          secure = stringify_keys(site_settings['secure'] || {})
          secure = default_peer_paths(secure, site_id)
          next unless peer_configured?(secure)

          peers << secure_peer(secure, site_id, credential_id: site_id, rsmp_id: site_id, rsmp_role: 'site')
        end
      end

      def secure_peer(secure, peer_id, credential_id: peer_id, rsmp_id: peer_id, rsmp_role: nil)
        peer = {
          'id' => peer_id,
          'credential' => secure['credential']
        }
        peer[PEER_ID_KEY] = credential_id if credential_id
        peer[RSMP_ID_KEY] = rsmp_id if rsmp_id
        peer[RSMP_ROLE_KEY] = rsmp_role if rsmp_role
        peer[CORE_VERSIONS_KEY] = secure['core_versions'] if secure['core_versions']
        peer
      end

      def peer_configured?(secure)
        secure['credential']
      end

      def local_identity_id(settings, fallback: nil)
        settings.dig('secure', 'id') || settings['site_id'] || fallback
      end

      def default_local_identity_paths(secure, id)
        return secure unless id && mode?(secure)

        secure.merge(
          'private_key' => secure['private_key'] || default_private_key_path(id),
          'credential' => secure['credential'] || default_credential_path(id)
        )
      end

      def default_peer_paths(secure, id)
        return secure unless id

        secure.merge(
          'credential' => secure['credential'] || default_credential_path(id)
        )
      end

      def default_private_key_path(id)
        "secure/#{id}.private.key"
      end

      def default_credential_path(id)
        "secure/#{id}.cred"
      end

      def stringify_keys(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, val), memo| memo[key.to_s] = stringify_keys(val) }
        when Array
          value.map { |item| stringify_keys(item) }
        else
          value
        end
      end
    end
  end
end
