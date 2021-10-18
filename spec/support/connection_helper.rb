# Helpers for testing sites and supervisors
module RSMP::SpecHelper end
module RSMP::SpecHelper::ConnectionHelper
  # Run a supervisor and a site inside an Async reactor, and wait for the siste to connect to the supervisor.
  # Then yield to the passed block, which can then run test code
  def with_site_connected &block
    error = nil
    Async do |task|
      # run site and supervisor in separate tasks
      supervisor_settings = {
        'port' => 13111,      # don't use default port 12111, to avoid interferance from other sites
        'guest' => {
          'sxl' => 'tlc'
        },
        'intervals' => {
          'timer' => 0.001,
          'watchdog' => 0.001
        }
      }
      site_settings = {
        'site_id' => 'RN+SI0001',
        'supervisors' => [
          { 'ip' => 'localhost', 'port' => 13111 }
        ],
        'intervals' => {
          'timer' => 0.001,
          'watchdog' => 0.001
        }
      }
      log_settings = {
        'active' => false,
        'hide_ip_and_port' => true,
        'debug' => true,
        'json' => false
      }
      supervisor = RSMP::Supervisor.new(supervisor_settings: supervisor_settings,log_settings: log_settings)
      site = RSMP::Site.new(site_settings: site_settings,log_settings: log_settings.merge('active'=>false))
      task.async { supervisor.start }
      task.async { site.start }

      # wait for site to connect
      site_proxy = supervisor.wait_for_site "RN+SI0001", 0.1
      expect(site_proxy).to be_an(RSMP::SiteProxy)
      expect(site_proxy.site_id).to eq("RN+SI0001")
      expect { site_proxy.wait_for_state(:ready, 0.1) }.not_to raise_error

      supervisor_proxy = site.proxies.first
      expect(supervisor_proxy).to be_an(RSMP::SupervisorProxy)
      expect(supervisor_proxy.ready?).to be_truthy

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