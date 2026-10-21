require_relative '../support/proxy_helper'

describe 'Component lists' do
  with 'Core 3.3.0' do
    include ProxyHelper

    let(:core_version) { '3.3.0' }
    let(:site) do
      build_site(core_version: core_version, 'sxls' => { 'tlc' => '1.3.0' },
                 'components' => { 'device' => { 'a' => {}, 'b' => {} } })
    end

    it 'keeps received component ordering and state across list updates' do
      proxy = build_site_proxy(core_version: core_version)
      proxy.instance_variable_set(:@site_settings, {})
      items = [{ 'id' => 'g/10', 'type' => 'sg', 'name' => 'Ten' },
               { 'id' => 'g/2', 'type' => 'sg', 'name' => 'Two' }]
      proxy.process_component_list(RSMP::ComponentList.new('components' => items))
      original = proxy.components['g/10']
      items.first['name'] = 'Updated'
      proxy.process_component_list(RSMP::ComponentList.new('components' => items))
      expect(proxy.components.keys).to be == %w[g/10 g/2]
      expect(proxy.components['g/10'].object_id).to be == original.object_id
      expect(original.name).to be == 'Updated'
      expect do
        proxy.process_component_list(RSMP::ComponentList.new('components' => [items.first, items.first]))
      end.to raise_exception(RSMP::MessageRejected)
      expect(proxy.components.keys).to be == %w[g/10 g/2]
    end

    it 'uses the component ID when a new or updated component list omits a name' do
      proxy = build_site_proxy(core_version: core_version)
      proxy.instance_variable_set(:@site_settings, {})
      item = { 'id' => 'g/1', 'type' => 'sg' }
      list = RSMP::ComponentList.new('components' => [item])
      expect(proxy.process_packet(JSON.generate(list.attributes)).success?).to be == true
      component = proxy.components['g/1']
      expect(component.name).to be == 'g/1'
      item['name'] = 'Signal group 1'
      proxy.process_component_list(list)
      expect(component.name).to be == 'Signal group 1'
      item.delete('name')
      proxy.process_component_list(list)
      expect(component.name).to be == 'g/1'
      expect(proxy.components['g/1'].object_id).to be == component.object_id
    end

    it 'keeps rejected-SXL components visible and broadcasts component changes only on 3.3' do
      connection = build_supervisor_proxy(site, core_version: core_version).tap(&:build_sxl_interfaces)
      legacy = build_supervisor_proxy(site, core_version: '3.2.2').tap(&:build_sxl_interfaces)
      connection.instance_variable_set(:@accepted_sxls, [])
      site.instance_variable_set(:@proxies, [connection, legacy])
      site.add_component(RSMP::Component.new(node: site, id: 'device/10', type: 'unaccepted/type'))
      site.add_component(RSMP::Component.new(node: site, id: 'device/2', type: 'unaccepted/type'))
      list = messages(connection).select { |message| message['type'] == 'ComponentList' }.last
      expect(list['components'].map { |item| item['id'] }).to be == %w[a b device/2 device/10]
      site.components['device/2'].update_metadata(name: 'renamed')
      site.remove_component('device/10')
      list = messages(connection).select { |message| message['type'] == 'ComponentList' }.last
      expect(list['components'].last['name']).to be == 'renamed'
      expect(messages(legacy)).to be == []
    end
  end
end
