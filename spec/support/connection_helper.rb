# Helpers for testing sites and supervisors
module RSMP::SpecHelper end
module RSMP::SpecHelper::ConnectionHelper
  # Run a supervisor and a site inside an Async reactor, and wait for the siste to connect to the supervisor.
  # Then yield to the passed block, which can then run test code
  def with_site_connected &block
    error = nil
    Async do |task|
      # run site and supervisor in separate tasks

      time_scale = 0.01
      supervisor_settings = {
        'port' => 13111,      # don't use default port 12111, to avoid interferance from other sites
        'guest' => {
          'sxl' => 'tlc',
          'intervals' => {
            'timer' => time_scale,
            'watchdog' => time_scale
          },
          'timeouts' => {
            'watchdog' => 4*time_scale,
            'acknowledgement' => 4*time_scale
          },
        },
    #   'one_shot' => true
      }
      site_settings = {
        'site_id' => 'RN+SI0001',
        'supervisors' => [
          { 'ip' => 'localhost', 'port' => 13111 }
        ],
        'intervals' => {
          'timer' => time_scale,
          'watchdog' => time_scale
        },
       'timeouts' => {
          'watchdog' => 4*time_scale,
          'acknowledgement' => 4*time_scale
        },
       }
      log_settings = {
        'active' => false,
        'hide_ip_and_port' => true,
        'debug' => true,
        'json' => false,
        'watchdogs' => false,
        'acknowledgements' => false
      }
      supervisor = RSMP::Supervisor.new(supervisor_settings: supervisor_settings,log_settings: log_settings.merge('active'=>false))
      site = RSMP::Site.new(site_settings: site_settings,log_settings: log_settings.merge('active'=>false))
      task.async { supervisor.start }
      task.async { site.start }

      # wait for site to connect
      site_proxy = supervisor.wait_for_site "RN+SI0001", 50*time_scale
      expect(site_proxy).to be_an(RSMP::SiteProxy)
      expect(site_proxy.site_id).to eq("RN+SI0001")
      site_proxy.wait_for_state :ready, 50*time_scale

      supervisor_proxy = site.proxies.first
      expect(supervisor_proxy).to be_an(RSMP::SupervisorProxy)
      supervisor_proxy.wait_for_state :ready, 50*time_scale

      # run test code
      yield task, supervisor, site, site_proxy, supervisor_proxy
    rescue StandardError, RSpec::Expectations::ExpectationNotMetError => e
      error = e
    ensure
      # stop
      site.stop
      supervisor.stop
      task.stop
    end
    raise error if error
  end
end