/**
 * Client half of the sidebar-entry bundle. Registers one panel icon into the
 * left sidebar's `sidebar.panellist` list and the matching page into the
 * root-scoped `main` keyed slot. The sidebar owns the button, label, and
 * selection: the same id (`dsh-sidebar-entry`) addresses the main panel, so a
 * click selects it with no extra wiring.
 */
window.__ModuleLoader__.load({
  id: '@local/dsh-sidebar-entry',
  factory(require) {
    const React = require('react');
    const h = React.createElement;

    const PANEL_ID = 'dsh-sidebar-entry';

    function PanelIcon({ size }) {
      return h('svg', {
        viewBox: '0 0 24 24',
        width: size,
        height: size,
        'aria-hidden': true,
        style: { display: 'block' },
      },
        h('rect', { x: 4, y: 4, width: 7, height: 7, rx: 1.5, fill: 'currentColor' }),
        h('rect', { x: 13, y: 4, width: 7, height: 7, rx: 1.5, fill: 'currentColor' }),
        h('rect', { x: 4, y: 13, width: 7, height: 7, rx: 1.5, fill: 'currentColor' }),
        h('rect', { x: 13, y: 13, width: 7, height: 7, rx: 1.5, fill: 'currentColor' }),
      );
    }

    function PanelPage() {
      return h('div', {
        style: {
          flex: 1,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '32px',
          textAlign: 'center',
          background: 'var(--dsw-alias-bg-base)',
        },
      },
        h('h1', {
          style: {
            margin: '0 0 8px',
            fontSize: '20px',
            fontWeight: 600,
            color: 'var(--dsw-alias-label-primary)',
          },
        }, 'Sidebar entry'),
        h('p', {
          style: {
            margin: 0,
            fontSize: '14px',
            color: 'var(--dsw-alias-label-secondary)',
          },
        }, 'This panel was added by the @local/dsh-sidebar-entry plugin.'),
      );
    }

    return {
      inject: ['slots'],
      apply(ctx) {
        ctx.slots.inject('sidebar.panellist', () => ctx.slots.register({
          name: 'sidebar.panellist',
          id: PANEL_ID,
          order: 50,
          label: 'Sidebar entry',
        }, PanelIcon));
        ctx.slots.inject('main', () => ctx.slots.register({
          name: 'main',
          key: PANEL_ID,
        }, PanelPage));
      },
    };
  },
});
