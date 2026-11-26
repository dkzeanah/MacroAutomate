/**
 * Client half of the video-analysis sidebar entry. Registers a panel icon into
 * the left sidebar and a page into the `main` panel. The page accepts a video
 * file (upload or disk path) and POSTs it to the Host half, then renders the
 * multi-frame, sequence-aware descriptions the vision model produced.
 */
window.__ModuleLoader__.load({
  id: '@local/dsh-sidebar-entry',
  factory(require) {
    const React = require('react');
    const h = React.createElement;
    const { useCallback, useRef, useState } = React;

    const PANEL_ID = 'dsh-sidebar-entry';
    const ROUTE = '/dsh-sidebar-entry/analyze';

    function PanelIcon({ size }) {
      return h('svg', {
        viewBox: '0 0 24 24', width: size, height: size,
        'aria-hidden': true,
        style: { display: 'block' },
      },
        h('rect', { x: 4, y: 4, width: 7, height: 7, rx: 1.5, fill: 'currentColor' }),
        h('rect', { x: 13, y: 4, width: 7, height: 7, rx: 1.5, fill: 'currentColor' }),
        h('rect', { x: 4, y: 13, width: 7, height: 7, rx: 1.5, fill: 'currentColor' }),
        h('rect', { x: 13, y: 13, width: 7, height: 7, rx: 1.5, fill: 'currentColor' }),
      );
    }

    const base = {
      boxSizing: 'border-box',
      fontFamily: 'inherit',
    };

    function ModeButton({ active, label, onClick }) {
      return h('button', {
        type: 'button',
        onClick,
        style: {
          ...base,
          padding: '6px 12px',
          borderRadius: '8px',
          border: '1px solid ' + (active ? 'var(--dsw-alias-brand-primary)' : 'var(--dsw-alias-border-l1)'),
          background: active ? 'var(--dsw-alias-bg-layer-1)' : 'transparent',
          color: active ? 'var(--dsw-alias-label-primary)' : 'var(--dsw-alias-label-secondary)',
          fontSize: '13px',
          fontWeight: 500,
          cursor: 'pointer',
        },
      }, label);
    }

    function VideoAnalyzer() {
      const [mode, setMode] = useState('upload');
      const [videoPath, setVideoPath] = useState('');
      const [fileName, setFileName] = useState('');
      const [file, setFile] = useState(null);
      const [drag, setDrag] = useState(false);
      const [status, setStatus] = useState({ kind: 'idle', message: '' });
      const [result, setResult] = useState(null);
      const inputRef = useRef(null);

      const analyze = useCallback(async () => {
        setResult(null);
        setStatus({ kind: 'working', message: 'Extracting 1 fps frames…' });
        try {
          let res;
          if (mode === 'upload') {
            if (!file) {
              setStatus({ kind: 'error', message: 'Choose a video file first.' });
              return;
            }
            res = await fetch(ROUTE, { method: 'POST', headers: { 'x-file-name': file.name }, body: file });
          } else {
            if (!videoPath.trim()) {
              setStatus({ kind: 'error', message: 'Enter a path to a video file.' });
              return;
            }
            res = await fetch(ROUTE, {
              method: 'POST',
              headers: { 'content-type': 'application/json' },
              body: JSON.stringify({ videoPath: videoPath.trim() }),
            });
          }
          const data = await res.json().catch(() => null);
          if (!res.ok || !data || data.ok !== true) {
            setStatus({
              kind: 'error',
              message: (data && data.message) || ('Request failed (HTTP ' + res.status + ')'),
            });
            return;
          }
          setResult(data);
          setStatus({ kind: 'done', message: '' });
        } catch (error) {
          setStatus({ kind: 'error', message: String((error && error.message) || error) });
        }
      }, [mode, file, videoPath]);

      const onDrop = useCallback((event) => {
        event.preventDefault();
        setDrag(false);
        const dropped = event.dataTransfer && event.dataTransfer.files && event.dataTransfer.files[0];
        if (dropped) {
          setFile(dropped);
          setFileName(dropped.name);
        }
      }, []);

      const onPick = useCallback((event) => {
        const picked = event.target && event.target.files && event.target.files[0];
        if (picked) {
          setFile(picked);
          setFileName(picked.name);
        }
      }, []);

      const working = status.kind === 'working';

      return h('div', {
        style: {
          ...base,
          flex: 1,
          overflowY: 'auto',
          padding: '32px',
          background: 'var(--dsw-alias-bg-base)',
        },
      },
        h('div', { style: { maxWidth: '640px', margin: '0 auto', display: 'flex', flexDirection: 'column', gap: '20px' } },
          h('h1', {
            style: { margin: 0, fontSize: '20px', fontWeight: 600, color: 'var(--dsw-alias-label-primary)' },
          }, 'Video analysis'),
          h('p', {
            style: { margin: 0, fontSize: '14px', color: 'var(--dsw-alias-label-secondary)', lineHeight: '1.5' },
          }, 'Extract one frame per second from a video and generate multi-frame, sequence-aware descriptions with a vision model.'),

          h('div', { style: { display: 'flex', gap: '8px' } },
            h(ModeButton, { active: mode === 'upload', label: 'Upload file', onClick: () => setMode('upload') }),
            h(ModeButton, { active: mode === 'path', label: 'Disk path', onClick: () => setMode('path') }),
          ),

          mode === 'upload'
            ? h('div', {
                onClick: () => inputRef.current && inputRef.current.click(),
                onDragOver: (e) => { e.preventDefault(); setDrag(true); },
                onDragLeave: () => setDrag(false),
                onDrop,
                style: {
                  ...base,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  minHeight: '96px', padding: '16px',
                  border: '1.5px dashed ' + (drag ? 'var(--dsw-alias-brand-primary)' : 'var(--dsw-alias-border-l2)'),
                  borderRadius: '12px',
                  background: 'var(--dsw-alias-bg-layer-1)',
                  color: 'var(--dsw-alias-label-secondary)',
                  fontSize: '14px',
                  cursor: 'pointer',
                  textAlign: 'center',
                },
              },
                h('span', null, fileName || 'Drop a video here, or click to choose a file.'),
                h('input', {
                  ref: inputRef,
                  type: 'file',
                  accept: 'video/*',
                  onChange: onPick,
                  style: { display: 'none' },
                }),
              )
            : h('input', {
                type: 'text',
                value: videoPath,
                onChange: (e) => setVideoPath(e.target.value),
                placeholder: 'C:\\path\\to\\video.mp4',
                style: {
                  ...base,
                  width: '100%', padding: '10px 12px',
                  borderRadius: '8px',
                  border: '1px solid var(--dsw-alias-border-l2)',
                  background: 'var(--dsw-alias-bg-layer-1)',
                  color: 'var(--dsw-alias-label-primary)',
                  fontSize: '14px',
                },
              }),

          h('button', {
            type: 'button',
            onClick: analyze,
            disabled: working,
            style: {
              ...base,
              alignSelf: 'flex-start',
              padding: '10px 18px',
              borderRadius: '8px',
              border: 'none',
              background: 'var(--dsw-alias-brand-primary)',
              color: 'var(--dsw-alias-bg-base)',
              fontSize: '14px',
              fontWeight: 600,
              cursor: working ? 'default' : 'pointer',
              opacity: working ? 0.7 : 1,
            },
          }, working ? 'Analyzing…' : 'Analyze video'),

          status.message
            ? h('div', {
                style: {
                  padding: '10px 12px',
                  borderRadius: '8px',
                  fontSize: '13px',
                  background: status.kind === 'error' ? 'var(--dsw-alias-bg-layer-1)' : 'transparent',
                  color: status.kind === 'error' ? 'var(--dsw-alias-state-error-primary)' : 'var(--dsw-alias-label-secondary)',
                },
              }, status.message)
            : null,

          result
            ? h('div', { style: { display: 'flex', flexDirection: 'column', gap: '12px' } },
                h('div', {
                  style: { fontSize: '13px', color: 'var(--dsw-alias-label-secondary)' },
                }, `${result.frameCount} frames at ${result.fps} fps · ${result.model.provider}/${result.model.model}`),
                result.windows.map((window) => h('div', {
                  key: window.index,
                  style: {
                    padding: '14px 16px',
                    borderRadius: '10px',
                    background: 'var(--dsw-alias-bg-layer-1)',
                    border: '1px solid var(--dsw-alias-border-l1)',
                    display: 'flex', flexDirection: 'column', gap: '8px',
                  },
                },
                  h('div', {
                    style: { fontSize: '12px', fontWeight: 600, color: 'var(--dsw-alias-brand-primary)' },
                  }, `${window.seconds[0]}s – ${window.seconds[1]}s`),
                  h('div', {
                    style: { fontSize: '14px', lineHeight: '1.55', color: 'var(--dsw-alias-label-primary)', whiteSpace: 'pre-wrap' },
                  }, window.text),
                )),
              )
            : null,
        ),
      );
    }

    return {
      inject: ['slots'],
      apply(ctx) {
        ctx.slots.inject('sidebar.panellist', () => ctx.slots.register({
          name: 'sidebar.panellist',
          id: PANEL_ID,
          order: 50,
          label: 'Video analysis',
        }, PanelIcon));
        ctx.slots.inject('main', () => ctx.slots.register({
          name: 'main',
          key: PANEL_ID,
        }, VideoAnalyzer));
      },
    };
  },
});
