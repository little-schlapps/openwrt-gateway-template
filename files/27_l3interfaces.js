// SPDX-License-Identifier: Apache-2.0
//
// Status > Overview section: every layer-3 interface with its addressing,
// firewall zone and the physical ports it is attached to.

'use strict';
'require baseclass';
'require network';
'require firewall';

function portLabel(dev) {
	const name = dev.getName();
	const carrier = dev.getCarrier();
	const speed = dev.getSpeed();
	let state;

	if (!carrier)
		state = _('no link');
	else if (speed > 0)
		state = (speed >= 1000 ? '%d G'.format(speed / 1000) : '%d M'.format(speed)) +
			(dev.getDuplex() == 'half' ? ' ' + _('half') : '');
	else
		state = _('up');

	return E('span', {
		'class': 'ifacebadge',
		'style': 'margin:0 .25em .25em 0;display:inline-block' + (carrier ? '' : ';opacity:.55'),
		'title': carrier ? _('Link up') : _('No carrier')
	}, [ E('strong', [ name ]), ' ', E('small', [ state ]) ]);
}

function lines(list, empty) {
	list = (list || []).filter(function(x) { return x != null && x !== ''; });
	if (!list.length)
		return E('em', [ empty || '-' ]);

	return E('div', {}, list.map(function(x) { return E('div', [ x ]); }));
}

function zoneBadge(zone) {
	if (!zone)
		return E('em', [ _('none') ]);

	return E('span', {
		'class': 'zonebadge',
		'style': firewall.getZoneColorStyle(zone)
	}, [ zone.getName() ]);
}

return baseclass.extend({
	title: _('Layer 3 Interfaces'),

	load: function() {
		return Promise.all([
			network.getNetworks(),
			firewall.getZones()
		]);
	},

	render: function(data) {
		const nets = (data[0] || []).filter(function(net) {
			return net.getName() != 'loopback';
		});
		const zones = data[1] || [];

		const table = E('table', { 'class': 'table' }, [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, [ _('Interface') ]),
				E('th', { 'class': 'th' }, [ _('Zone') ]),
				E('th', { 'class': 'th' }, [ _('Protocol') ]),
				E('th', { 'class': 'th' }, [ _('Device') ]),
				E('th', { 'class': 'th' }, [ _('Physical ports') ]),
				E('th', { 'class': 'th' }, [ _('IPv4 address') ]),
				E('th', { 'class': 'th' }, [ _('Gateway / metric') ]),
				E('th', { 'class': 'th' }, [ _('DNS') ])
			])
		]);

		nets.forEach(function(net) {
			const name = net.getName();
			const up = net.isUp();
			const zone = zones.filter(function(z) {
				return (z.getNetworks() || []).indexOf(name) > -1;
			})[0];

			const dev = net.getL3Device() || net.getDevice();
			let ports = [];
			if (dev) {
				const members = dev.getPorts ? dev.getPorts() : null;
				ports = (members && members.length) ? members : [ dev ];
			}

			const gw = net.getGatewayAddr();
			const metric = net.getMetric();

			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td', 'data-title': _('Interface') }, [
					E('strong', [ name ]), E('br'),
					E('small', { 'style': up ? 'color:#2e7d32' : 'color:#c62828' }, [
						up ? _('up %s').format('%t'.format(net.getUptime())) : _('down')
					])
				]),
				E('td', { 'class': 'td', 'data-title': _('Zone') }, [ zoneBadge(zone) ]),
				E('td', { 'class': 'td', 'data-title': _('Protocol') }, [ net.getI18n ? net.getI18n() : net.getProtocol() ]),
				E('td', { 'class': 'td', 'data-title': _('Device') }, [ dev ? dev.getName() : E('em', [ '-' ]) ]),
				E('td', { 'class': 'td', 'data-title': _('Physical ports') }, ports.length ? ports.map(portLabel) : [ E('em', [ '-' ]) ]),
				E('td', { 'class': 'td', 'data-title': _('IPv4 address') }, [ lines(net.getIPAddrs()) ]),
				E('td', { 'class': 'td', 'data-title': _('Gateway / metric') }, [
					gw ? gw : E('em', [ '-' ]),
					(gw && metric != null) ? E('small', [ ' (%s %d)'.format(_('metric'), metric) ]) : ''
				]),
				E('td', { 'class': 'td', 'data-title': _('DNS') }, [ lines(net.getDNSAddrs()) ])
			]));
		});

		if (!nets.length)
			table.appendChild(E('tr', { 'class': 'tr placeholder' }, [
				E('td', { 'class': 'td' }, [ E('em', [ _('No interfaces configured.') ]) ])
			]));

		return table;
	}
});
