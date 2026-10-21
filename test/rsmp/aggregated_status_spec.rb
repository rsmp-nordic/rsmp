require_relative '../support/proxy_helper'

describe 'Aggregated status' do
  with 'Core 3.3.0' do
    include ProxyHelper

    let(:core_version) { '3.3.0' }
    let(:site) do
      build_site(core_version: core_version, 'sxls' => { 'tlc' => '1.3.0' },
                 'components' => { 'device' => { 'a' => {}, 'b' => {} } })
    end

    it 'combines all component and alarm conditions independently of accepted SXLs' do
      proxy = build_supervisor_proxy(site, core_version: core_version).tap(&:build_sxl_interfaces)
      proxy.instance_variable_set(:@accepted_sxls, [])
      expect(site.site_aggregated_status).to be == Array.new(8, false)
      site.components['a'].set_aggregated_status(%i[local_control normal])
      site.components['b'].set_aggregated_status(:rest)
      alarm = site.components['b'].get_alarm_state('A0001')
      alarm.activate
      proxy.send_aggregated_status
      status = messages(proxy).last
      expect(status['se']).to be == [true, false, false, true, false, false, true, false]
      expect(status.keys & %w[cId fP fS]).to be == []
      alarm.deactivate
      expect(site.site_aggregated_status[3]).to be == false
      site.components['a'].set_aggregated_status([])
      site.components['b'].set_aggregated_status([])
      expect(site.site_aggregated_status).to be == Array.new(8, false)
    end
  end

  with 'Core 3.2.2' do
    include ProxyHelper

    let(:core_version) { '3.2.2' }

    it 'keeps component-addressed aggregated status and normal bit on legacy connections' do
      site = build_site(core_version: core_version, 'sxls' => { 'tlc' => '1.3.0' }, 'components' => { 'main' => { 'C1' => {} } })
      proxy = build_supervisor_proxy(site, core_version: core_version).tap(&:build_sxl_interfaces)
      proxy.send_aggregated_status(site.main)
      status = messages(proxy).last
      expect(status.values_at('cId', 'fP', 'fS')).to be == ['C1', nil, nil]
      expect(status['se'][5]).to be == true
    end
  end
end
