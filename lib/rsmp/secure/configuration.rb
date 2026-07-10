require 'pathname'

module RSMP
  module Secure
    # Configuration helpers for Secure RSMP settings and path conventions.
    module Configuration
      def settings(raw)
        raw = stringify_keys(raw || {})
        {
          'profile' => PROFILE,
          'max_frame_size' => DEFAULT_MAX_FRAME_SIZE,
          'handshake_timeout' => DEFAULT_HANDSHAKE_TIMEOUT,
          'rekey_after_messages' => DEFAULT_REKEY_AFTER_MESSAGES,
          'rekey_after_seconds' => DEFAULT_REKEY_AFTER_SECONDS,
          'min_rekey_interval' => DEFAULT_MIN_REKEY_INTERVAL
        }.merge(raw)
      end

      def merge_peer_settings(local, peer, peer_id: nil)
        local = local_identity_settings(local)
        peer = stringify_keys(peer || {})
        peer = default_peer_paths(peer, peer['id'] || peer_id)
        return local unless peer_configured?(peer)

        settings_with_peers(local, [secure_peer(peer, peer['id'] || peer_id, supervisor_id: peer['supervisor_id'])])
      end

      def site_local_settings(site_settings)
        settings_with_config_dir(
          site_settings,
          site_settings['secure'],
          local_id: local_identity_id(site_settings)
        )
      end

      def site_peer_settings(site_settings, supervisor_settings)
        merge_peer_settings(site_local_settings(site_settings), supervisor_settings['secure'])
      end

      def supervisor_local_settings(supervisor_settings)
        secure_settings = supervisor_settings['secure'] || supervisor_settings.dig('default', 'secure')
        settings_with_config_dir(
          supervisor_settings,
          secure_settings,
          local_id: local_identity_id(supervisor_settings, fallback: DEFAULT_SUPERVISOR_ID)
        )
      end

      def supervisor_site_settings(supervisor_settings, site_settings, site_id: nil)
        merge_peer_settings(supervisor_local_settings(supervisor_settings),
                            site_settings['secure'],
                            peer_id: site_settings['site_id'] || site_id)
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

      def validate_local_identity!(secure_settings)
        secure_settings = settings(secure_settings)
        return unless mode?(secure_settings)

        validate_profile!(secure_settings)
        validate_local_identity_file!(secure_settings, 'private_key')
        validate_local_identity_file!(secure_settings, 'credential')
      end

      def validate_transport_mode!(secure_settings, connection_role:)
        secure_settings = stringify_keys(secure_settings || {})
        return true unless connection_role.to_s == 'server'
        return true unless secure_settings['enabled'] == true && secure_settings['required'] != true

        raise RSMP::ConfigurationError,
              'secure.enabled does not secure an inbound listener; use secure.required: true'
      end

      def validate_peer_files!(secure_settings)
        secure_settings = settings(secure_settings)
        return unless mode?(secure_settings)

        validate_profile!(secure_settings)
        (secure_settings['peers'] || []).each do |peer|
          validate_peer_file!(secure_settings, peer, 'public_key')
          validate_peer_file!(secure_settings, peer, 'credential')
        end
      end

      def expand_config_path(path, secure_settings)
        return path if Pathname.new(path).absolute?

        config_dir = secure_settings[CONFIG_DIR_KEY]
        return path unless config_dir

        File.expand_path(path, config_dir)
      end

      private

      def validate_profile!(secure_settings)
        Secure.validate_profile_name!(secure_settings['profile'])
      end

      def validate_local_identity_file!(secure_settings, key)
        path = secure_settings[key]
        raise RSMP::ConfigurationError, "secure.#{key} is required" unless path

        expanded = expand_config_path(path, secure_settings)
        raise RSMP::ConfigurationError, "secure.#{key} file not found: #{expanded}" unless File.file?(expanded)
      end

      def validate_peer_file!(secure_settings, peer, key)
        path = peer[key]
        raise RSMP::ConfigurationError, "secure peer #{peer['id']} #{key} is required" unless path

        expanded = expand_config_path(path, secure_settings)
        return if File.file?(expanded)

        raise RSMP::ConfigurationError, "secure peer #{peer['id']} #{key} file not found: #{expanded}"
      end

      def local_identity_settings(local)
        settings(local).except(*PEER_SETTING_KEYS)
      end

      def settings_with_config_dir(settings, secure_settings = settings['secure'], local_id: nil)
        secure_settings = stringify_keys(secure_settings || {})
        secure_settings = default_local_identity_paths(secure_settings, local_id)
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
            supervisor_id: secure['supervisor_id']
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

          peers << secure_peer(secure, site_id, site_id: site_id)
        end
      end

      def secure_peer(secure, peer_id, extra)
        {
          'id' => peer_id,
          'public_key' => secure['public_key'],
          'credential' => secure['credential']
        }.merge(stringify_keys(extra))
      end

      def peer_configured?(secure)
        secure['public_key'] && secure['credential']
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
          'public_key' => secure['public_key'] || default_public_key_path(id),
          'credential' => secure['credential'] || default_credential_path(id)
        )
      end

      def default_private_key_path(id)
        "secure/#{id}.private.key"
      end

      def default_public_key_path(id)
        "secure/#{id}.pub"
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
